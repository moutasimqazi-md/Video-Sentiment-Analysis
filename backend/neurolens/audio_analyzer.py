"""Audio emotion analysis: decodes the video's audio track in-process (PyAV) and
scores 10-second windows against the same 16 emotions with CLAP zero-shot."""

import threading

import av
import numpy as np
import torch
from transformers import ClapModel, ClapProcessor

SAMPLE_RATE = 48000
WINDOW_SECONDS = 10
MAX_DECODE_SECONDS = 300
MAX_WINDOWS = 12
BATCH_SIZE = 6
SILENCE_RMS = 0.003

AUDIO_PROMPTS = {
    "confident": [
        "confident swagger hip hop beat with heavy bass",
        "bold attitude trap music",
    ],
    "motivated": [
        "epic motivational cinematic music building up",
        "intense inspiring workout anthem",
    ],
    "focused": [
        "intense gym workout music with a driving beat",
        "heavy breathing and weights clanging in a gym",
    ],
    "inspired": [
        "uplifting emotional orchestral music",
        "inspiring transformation soundtrack",
    ],
    "excited": [
        "celebration with a cheering crowd and party music",
        "fireworks and excited screaming",
    ],
    "happy": [
        "upbeat cheerful pop dance music",
        "people laughing and a fun trending song",
    ],
    "funny": [
        "comedic sound effects and laughter",
        "silly funny meme sounds",
    ],
    "romantic": [
        "soft romantic love song",
        "gentle acoustic love ballad",
    ],
    "hungry": [
        "sizzling frying food cooking sounds",
        "crunchy eating and chewing sounds",
    ],
    "peaceful": [
        "calm peaceful ambient nature sounds with birds and water",
        "soft relaxing lo-fi music",
    ],
    "heartbroken": [
        "heartbreaking emotional breakup ballad with sad vocals",
        "crying with a sad slow song",
    ],
    "sad": [
        "sad slow melancholic piano song",
        "gloomy sad instrumental music",
    ],
    "angry": [
        "aggressive angry rap or metal with shouting",
        "furious screaming and heavy distorted guitars",
    ],
    "lost": [
        "lonely atmospheric ambient music with echo",
        "quiet dreamy reverb night drone",
    ],
    "tired": [
        "slow tired lo-fi music with a sigh",
        "stressful noise and heavy sighing",
    ],
    "depressed": [
        "dark hopeless slow drone music",
        "bleak eerie minimal sound",
    ],
}

_model = None
_processor = None
_text_embeds = None
_load_lock = threading.Lock()


def _load_model():
    global _model, _processor
    with _load_lock:
        if _model is None:
            model = ClapModel.from_pretrained("laion/clap-htsat-unfused")
            model.eval()
            _processor = ClapProcessor.from_pretrained("laion/clap-htsat-unfused")
            _model = model
    return _model, _processor


def warm_up():
    model, processor = _load_model()
    _category_embeddings()
    with torch.inference_mode():
        silence = np.zeros(SAMPLE_RATE, dtype=np.float32)
        _as_tensor(model.get_audio_features(**processor(audio=[silence], sampling_rate=SAMPLE_RATE, return_tensors="pt")))


def _as_tensor(out):
    # transformers >=5 may return a wrapper whose pooler_output is the projected embedding
    return out if isinstance(out, torch.Tensor) else out.pooler_output


def _category_embeddings():
    global _text_embeds
    if _text_embeds is not None:
        return _text_embeds
    model, processor = _load_model()
    embeds = []
    with torch.no_grad():
        for prompts in AUDIO_PROMPTS.values():
            inputs = processor(text=prompts, return_tensors="pt", padding=True)
            feats = _as_tensor(model.get_text_features(**inputs))
            feats = feats / feats.norm(dim=-1, keepdim=True)
            mean_vec = feats.mean(dim=0)
            embeds.append(mean_vec / mean_vec.norm())
    _text_embeds = torch.stack(embeds)
    return _text_embeds


def load_audio(video_path):
    """Decode the first audio stream to mono float32 at 48 kHz. None if there is no audio."""
    container = av.open(video_path)
    try:
        stream = next((s for s in container.streams if s.type == "audio"), None)
        if stream is None:
            return None
        resampler = av.AudioResampler(format="flt", layout="mono", rate=SAMPLE_RATE)
        chunks, total = [], 0
        limit = MAX_DECODE_SECONDS * SAMPLE_RATE
        for frame in container.decode(stream):
            for rf in resampler.resample(frame):
                arr = rf.to_ndarray().reshape(-1)
                chunks.append(arr)
                total += arr.size
            if total >= limit:
                break
        if not chunks:
            return None
        return np.concatenate(chunks).astype(np.float32)
    finally:
        container.close()


def _windows(audio):
    size = WINDOW_SECONDS * SAMPLE_RATE
    if audio.size <= size:
        return [(0.0, audio)]
    starts = list(range(0, audio.size - size + 1, size))
    if starts[-1] + size < audio.size:
        starts.append(audio.size - size)  # keep the tail instead of dropping it
    if len(starts) > MAX_WINDOWS:
        idx = np.linspace(0, len(starts) - 1, MAX_WINDOWS).round().astype(int)
        starts = [starts[i] for i in idx]
    return [(s / SAMPLE_RATE, audio[s : s + size]) for s in starts]


def analyze_audio(video_path):
    """Returns None when there is no usable audio, else a dict of per-emotion percentages."""
    audio = load_audio(video_path)
    if audio is None:
        return {"available": False, "reason": "no audio track"}

    overall_rms = float(np.sqrt(np.mean(audio**2)))
    if overall_rms < SILENCE_RMS:
        return {"available": False, "reason": "audio is silent"}

    model, processor = _load_model()
    text_embeds = _category_embeddings()
    categories = list(AUDIO_PROMPTS.keys())
    scale = float(model.logit_scale_a.exp()) if hasattr(model, "logit_scale_a") else 100.0

    windows = _windows(audio)
    probs_all, feat_all, loud = [], [], []
    with torch.inference_mode():
        for i in range(0, len(windows), BATCH_SIZE):
            batch = [w for _, w in windows[i : i + BATCH_SIZE]]
            inputs = processor(audio=batch, sampling_rate=SAMPLE_RATE, return_tensors="pt")
            feats = _as_tensor(model.get_audio_features(**inputs))
            feats = feats / feats.norm(dim=-1, keepdim=True)
            probs_all.append(torch.softmax(feats @ text_embeds.T * scale, dim=-1))
            feat_all.append(feats)
            loud.extend(float(np.sqrt(np.mean(w**2))) for w in batch)

    probs = torch.cat(probs_all).numpy()
    means = probs.mean(axis=0)
    averages = {c: round(float(m) * 100, 1) for c, m in zip(categories, means)}
    mean_embedding = torch.cat(feat_all).mean(dim=0)
    mean_embedding = (mean_embedding / mean_embedding.norm()).tolist()
    return {
        "available": True,
        "averages": averages,
        "dominant": max(averages, key=averages.get),
        "windows_analyzed": len(windows),
        "loudness_db": round(20 * np.log10(max(overall_rms, 1e-6)), 1),
        "quiet_ratio": round(float(np.mean(np.array(loud) < SILENCE_RMS * 3)), 2),
        "embedding": mean_embedding,
    }
