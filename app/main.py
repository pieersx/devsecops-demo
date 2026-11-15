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
