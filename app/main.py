"""API minima para la demo DevSecOps."""
import os

from fastapi import FastAPI

app = FastAPI(title="devsecops-demo")


@app.get("/")
def root() -> dict:
    return {"service": "devsecops-demo", "version": os.getenv("APP_VERSION", "dev")}


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


import subprocess  # noqa: E402


@app.get("/ping")
def ping(host: str) -> dict:
    out = subprocess.run(f"ping -c 1 {host}", shell=True, capture_output=True, text=True)
    return {"output": out.stdout}
