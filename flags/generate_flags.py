import hmac
import hashlib

BOX_ID = "expert-the-annex"


def flag_for(secret: str, n: int) -> str:
    digest = hmac.new(secret.encode(), f"{BOX_ID}:{n}".encode(), hashlib.sha256).hexdigest()
    return f"HLC{{{digest[:10]}}}"


def secret_for(secret: str, label: str) -> str:
    """A non-flag-shaped derived secret (e.g. the final archive's password)."""
    digest = hmac.new(secret.encode(), f"{BOX_ID}:secret:{label}".encode(), hashlib.sha256).hexdigest()
    return digest[:20]
