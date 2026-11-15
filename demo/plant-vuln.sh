#!/usr/bin/env bash
# Planta vulnerabilidades a proposito en una rama para mostrar como el pipeline las bloquea.
set -euo pipefail

git checkout -b demo/vulnerable

# 1) Dependencia con CVE conocido (Trivy debe fallar con CRITICAL/HIGH)
echo "pyyaml==5.3.1" >> app/requirements.txt

# 2) Codigo inseguro: ejecucion de comandos con shell=True y entrada del usuario (Semgrep debe fallar)
cat >> app/main.py <<'EOF'


import subprocess  # noqa: E402


@app.get("/ping")
def ping(host: str) -> dict:
    out = subprocess.run(f"ping -c 1 {host}", shell=True, capture_output=True, text=True)
    return {"output": out.stdout}
EOF

git add -A
git commit -m "demo: introducir vulnerabilidades a proposito"
echo "Rama demo/vulnerable creada. Haz push y abre un Pull Request para ver el pipeline fallar."
