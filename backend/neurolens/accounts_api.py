"""Sign up, sign in, profile, plans and subscription for the mobile app."""

import os

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from neurolens import accounts, guard

router = APIRouter(prefix="/api")
PAYMENTS = os.environ.get("NL_PAYMENTS", "demo")  # "demo": choosing a plan switches it on without charging anyone
user = Depends(guard.user_actor)


def _ip(request: Request):
    fwd = request.headers.get("x-forwarded-for")
    return (fwd.split(",")[0].strip() if fwd else (request.client.host if request.client else "")) or "?"


def _fail(e: accounts.AuthError):
    raise HTTPException(e.status, e.message)


def charge_analysis(request: Request):
    """For the analysis routes: if a signed-in user sent their token, make sure they have analyses left. Returns their id, or
    None for callers without one (the website). A token that no longer works is a 401 so the app can ask to sign in again."""
    tok = request.headers.get("x-user-token")
    if not tok:
        return None
    u = accounts.by_token(tok)
    if not u:
        raise HTTPException(401, "Please sign in again.")
    if accounts.remaining(u["user_id"]) <= 0:
        plan = accounts.PLANS.get(u["plan"], accounts.PLANS["free"])
        raise HTTPException(402, f"You have used this month's {plan['quota']} analyses on the {plan['name']} plan. Upgrade or wait until it resets.")
    return u["user_id"]


class SignupIn(BaseModel):
    name: str = ""
    email: str
    password: str
    device: str = ""


class LoginIn(BaseModel):
    email: str
    password: str
    device: str = ""


class ProfileIn(BaseModel):
    name: str | None = None


class PasswordIn(BaseModel):
    current: str
    new: str


class SubscribeIn(BaseModel):
    plan: str
    cycle: str = "monthly"


class DeleteIn(BaseModel):
    password: str


@router.get("/plans")
def plans():
    return {"plans": list(accounts.PLANS.values()), "payments": PAYMENTS}


@router.post("/auth/signup")
def signup(body: SignupIn, request: Request):
    if not accounts.rate_ok(_ip(request)):
        raise HTTPException(429, "Too many accounts were created from this connection today. Try again tomorrow.")
    try:
        uid, token = accounts.signup(body.name, body.email, body.password, body.device)
    except accounts.AuthError as e:
        _fail(e)
    return {"token": token, "me": accounts.status(uid)}


@router.post("/auth/login")
def login(body: LoginIn, request: Request):
    try:
        uid, token = accounts.login(body.email, body.password, _ip(request), body.device)
    except accounts.AuthError as e:
        _fail(e)
    return {"token": token, "me": accounts.status(uid)}


@router.post("/auth/logout")
def logout(request: Request, a=user):
    accounts.revoke(request.headers.get("x-user-token", ""))
    return {"ok": True}


@router.get("/me")
def me(a=user):
    return accounts.status(a.uid)


@router.put("/me")
def update_me(body: ProfileIn, a=user):
    accounts.update_profile(a.uid, name=body.name)
    return accounts.status(a.uid)


@router.post("/me/password")
def change_password(body: PasswordIn, request: Request, a=user):
    try:
        accounts.change_password(a.uid, body.current, body.new, keep_token=request.headers.get("x-user-token"))
    except accounts.AuthError as e:
        _fail(e)
    return {"ok": True}


@router.post("/me/subscribe")
def subscribe(body: SubscribeIn, a=user):
    """Switch plan. In demo mode this is instant and free; a real payment provider would confirm the payment first."""
    if body.plan not in accounts.PLANS:
        raise HTTPException(400, "Unknown plan")
    if PAYMENTS != "demo":
        raise HTTPException(501, "Payments are not set up on this server.")
    accounts.set_plan(a.uid, body.plan, body.cycle)
    return {"me": accounts.status(a.uid), "demo": True, "message": "Demo mode: your plan was switched on without a charge."}


@router.post("/me/cancel")
def cancel(a=user):
    accounts.set_plan(a.uid, "free")
    return {"me": accounts.status(a.uid)}


@router.post("/me/delete")
def delete_account(body: DeleteIn, a=user):
    """Permanently deletes the account and everything stored for it on the server. Needs the password."""
    if not accounts.confirm_password(a.uid, body.password):
        raise HTTPException(403, "That password is wrong.")
    accounts.delete_user(a.uid)
    return {"ok": True}
