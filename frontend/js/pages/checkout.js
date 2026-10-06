/* Checkout (demo): confirms a plan locally. No payment is processed. */
(() => {
  const $ = (id) => document.getElementById(id);
  const q = new URLSearchParams(location.search);
  const plan = NL.PLANS[q.get("plan")];
  const cycle = q.get("cycle") === "yearly" ? "yearly" : "monthly";

  if (!plan || plan.id === "free") { location.replace("pricing.html"); return; }

  const per = plan[cycle];
  const total = cycle === "yearly" ? per * 12 : per;
  $("summary").innerHTML = `
    <h2 class="h3">Order summary</h2>
    <div class="sum-row" style="margin-top:10px"><span>${NL.esc(plan.name)}</span><b>$${per} / mo</b></div>
    <div class="sum-row"><span class="muted">Billing</span><span>${cycle === "yearly" ? "Yearly" : "Monthly"}</span></div>
    <div class="sum-row total"><span>Total today</span><span>$${total}</span></div>
    <ul style="padding-left:18px;margin:16px 0 0;color:var(--muted);font-size:14px">${plan.features.slice(0, 4).map((f) => `<li>${NL.esc(f)}</li>`).join("")}</ul>`;

  const user = NL.user.get();
  if (user) { $("cName").value = user.name; $("cEmail").value = user.email; }

  $("payBtn").onclick = () => {
    const name = $("cName").value.trim(), email = $("cEmail").value.trim();
    const err = $("chkErr");
    if (!name || !/^\S+@\S+\.\S+$/.test(email)) { err.textContent = "Enter your name and a valid email."; err.hidden = false; return; }
    if (!user) NL.user.login(name, email);
    NL.plan.set(plan.id, cycle);
    location.href = "account.html?welcome=1";
  };
})();
