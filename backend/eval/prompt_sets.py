"""Candidate prompt sets. V2 is written once from general knowledge of each mood's *visual* cues (people, settings, objects, framing),
with several phrasings per mood, so the text prototype covers more of what that mood looks like. It is not tuned on the labeled set."""

V2 = {
    "confident": [
        "a person striking a confident pose with strong attitude", "a stylish person walking with swagger in sunglasses",
        "a well-dressed person looking powerful and self-assured", "a bold fashion photoshoot with a confident model",
        "a man in a sharp suit with a serious cool expression", "a woman with a fierce confident look at the camera",
    ],
    "motivated": [
        "an intense motivational scene of someone pushing to succeed", "a person running at sunrise training hard toward a goal",
        "a silhouette climbing a mountain with determination", "an athlete pushing through a tough workout",
        "a motivational video with powerful text and a determined person", "a person studying or working hard late at night to reach a goal",
    ],
    "focused": [
        "a person lifting weights in a gym", "an athlete training with intense focus and discipline",
        "a close-up of someone concentrating on work", "a bodybuilder doing a heavy lift", "a person boxing or doing martial arts training",
        "someone coding or studying with deep concentration",
    ],
    "inspired": [
        "a dramatic before and after transformation", "a glow-up or life transformation moment", "a person achieving an amazing goal",
        "an uplifting cinematic moment of achievement", "a body transformation comparison photo", "a breathtaking creative or artistic accomplishment",
    ],
    "excited": [
        "a celebration with confetti, fireworks and cheering people", "a party or festive event with excited crowds",
        "a crowd cheering at a concert or stadium", "people jumping and screaming with excitement", "a birthday or wedding party with lights and dancing",
        "a thrilling sports moment with a celebrating crowd",
    ],
    "happy": [
        "friends laughing and smiling together", "a bright cheerful joyful moment", "kids playing happily outdoors",
        "a smiling person looking at the camera", "a happy family spending time together", "people dancing happily and having fun",
    ],
    "funny": [
        "a person making a silly exaggerated face", "a comedy skit with people acting goofy", "a meme with a funny caption text",
        "friends pranking each other and laughing hard", "a funny relatable everyday situation", "a comedian or actor delivering a joke",
        "a cartoon or animated funny scene", "a person reacting with comic surprise or confusion", "a viral humorous video clip",
    ],
    "romantic": [
        "a romantic couple hugging, kissing or holding hands", "a love scene with flowers, candlelight or a wedding",
        "a bride and groom on their wedding day", "a couple walking together at sunset", "a man and woman looking lovingly at each other",
        "a proposal with a ring and roses",
    ],
    "hungry": [
        "a photo of delicious appetizing food", "a close-up of someone eating food", "a plate of tasty food being prepared or served",
        "a chef cooking in a kitchen", "street food being fried or grilled", "a table full of dishes at a restaurant", "a close-up of a burger, pizza or biryani",
    ],
    "peaceful": [
        "a serene aesthetic nature landscape with soft light", "calm mountains, ocean, forest or sunset scenery", "a quiet lake at sunrise with mist",
        "a cozy peaceful room with soft warm light", "a calm slow nature timelapse", "a person meditating or praying in a quiet place",
    ],
    "heartbroken": [
        "a person crying alone after a breakup", "a torn photo, empty room and emotional heartbreak", "a person holding a broken heart or an old photo",
        "a lonely person watching rain through a window with tears", "a sad couple parting ways", "a person sitting alone staring at a phone with sadness",
    ],
    "sad": [
        "a sad person looking down with tears, feeling low", "a rainy window with a gloomy, melancholic mood", "a person sitting alone looking sad",
        "a gloomy grey scene with a lonely figure", "a sad face with tears on a dark background", "a melancholic slow moment with muted colours",
    ],
    "angry": [
        "an angry person shouting with a furious face", "a rage scene with clenched fists and intense aggression", "people arguing and fighting loudly",
        "a person with a fierce aggressive stare", "an intense dark confrontation scene", "a furious face with a red dramatic background",
    ],
    "lost": [
        "a lonely person standing alone in a vast empty place", "a silhouette lost in deep thought at night", "a person walking alone in an empty street at night",
        "a figure staring into the distance on a foggy road", "someone sitting alone on a rooftop looking at the city lights",
    ],
    "tired": [
        "an exhausted stressed person overwhelmed by work", "a person with their head down, drained and burnt out", "someone asleep at a desk surrounded by papers",
        "a tired person rubbing their eyes late at night", "a stressed worker in front of a computer at night",
    ],
    "depressed": [
        "a very dark, hopeless, depressing scene in shadows", "a person isolated in a dark room, emotionally numb", "a person curled up in bed in a dark room",
        "a dark silhouette hiding their face in despair", "an empty dark room with a single dim light",
    ],
}
