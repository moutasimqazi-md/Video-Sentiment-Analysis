/* Account page: profile, current plan, usage, cancel. */
(() => {
  const $ = (id) => document.getElementById(id);
  const user = NL.user.get();

  if (!user) { $("acct").hidden = true; $("needLogin").hidden = false; return; }

  const plan = NL.plan.get();
  const cycle = NL.plan.cycle();
  $("uName").textContent = user.name;
  $("uEmail").textContent = user.email;
  $("uSince").textContent = NL.fmtDate(user.since);
  $("pName").textContent = plan.name;
  $("pBill").textContent = plan.monthly ? `$${plan[cycle]} / mo · ${cycle}` : "Free";
  const used = NL.usage.count();
  $("pUse").textContent = `${used} / ${plan.quota}`;
  $("pBar").style.width = Math.min(100, (used / plan.quota) * 100) + "%";
  $("cancel").hidden = plan.id === "free";

  $("logout").onclick = () => { NL.user.logout(); location.href = "../index.html"; };
  $("cancel").onclick = () => {
    if (confirm("Cancel your subscription and go back to the free Starter plan?")) {
      NL.plan.set("free");
      location.href = "account.html";
    }
  };
  if (new URLSearchParams(location.search).get("welcome")) NL.toast(`You're on ${plan.name} 🎉`);
})();
