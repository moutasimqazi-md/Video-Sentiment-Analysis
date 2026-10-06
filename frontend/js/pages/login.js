/* Login / sign-up (demo): the profile is kept in this browser only; no password is stored or checked. */
(() => {
  const $ = (id) => document.getElementById(id);
  let signup = false;

  function paint() {
    $("authTitle").textContent = signup ? "Create your account" : "Welcome back";
    $("authBtn").textContent = signup ? "Sign up" : "Log in";
    $("nameField").hidden = !signup;
    $("swapText").textContent = signup ? "Already have an account?" : "New here?";
    $("swapBtn").textContent = signup ? "Log in" : "Create an account";
  }
  $("swapBtn").onclick = () => { signup = !signup; paint(); };

  $("authBtn").onclick = () => {
    const email = $("aEmail").value.trim();
    const name = signup ? $("aName").value.trim() : (NL.user.get() || {}).name || email.split("@")[0];
    const err = $("authErr");
    if (!/^\S+@\S+\.\S+$/.test(email) || $("aPass").value.length < 6 || !name) {
      err.textContent = "Enter a valid email and a password of at least 6 characters" + (signup ? ", plus your name." : ".");
      err.hidden = false;
      return;
    }
    NL.user.login(name, email);
    location.href = "dashboard.html";
  };
  paint();
})();
