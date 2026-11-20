import glob
import os
import subprocess
import sys
import mysql.connector

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(BASE_DIR, "app"))
from app import app


def strip_sql_comment(line):
  in_quote = False
  for i in range(len(line) - 1):
    if line[i] == "'" and (i == 0 or line[i - 1] != "\\"):
      in_quote = not in_quote
    if (
        not in_quote
        and line[i : i + 2] == "--"
        and (i + 2 == len(line) or line[i + 2] in (" ", "\t", "\r", "\n"))
    ):
      return line[:i]
  return line


@app.route("/init-db")
def init_db():
  logs = []
  try:
    conn = mysql.connector.connect(
        host=os.getenv("DB_HOST"),
        port=int(os.getenv("DB_PORT", 3306)),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        database=os.getenv("DB_NAME"),
    )
    cursor = conn.cursor()
    try:
      cursor.execute("SET SESSION sql_require_primary_key = 0")
    except Exception:
      pass

    sql_files = sorted(glob.glob(os.path.join(BASE_DIR, "database", "*.sql")))
    logs.append(f"Found {len(sql_files)} SQL files.")

    for filepath in sql_files:
      filename = os.path.basename(filepath)
      with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()

      delimiter = ";"
      statement = []
      for raw_line in lines:
        line = strip_sql_comment(raw_line)
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
          continue
        if stripped.upper().startswith("DELIMITER"):
          delimiter = stripped[9:].strip()
          continue
        line_fixed = line.replace("`blood_bank`", "`defaultdb`").replace(
            "blood_bank", "defaultdb"
        )
        statement.append(line_fixed)
        joined = "".join(statement).strip()
        if joined.endswith(delimiter):
          sql = joined[: -len(delimiter)].strip()
          statement = []
          if not sql:
            continue
          upper_sql = sql.upper().lstrip()
          if upper_sql.startswith("CREATE DATABASE") or upper_sql.startswith(
              "DROP DATABASE"
          ):
            continue
          cursor.execute(sql)
      conn.commit()
      logs.append(f"OK: {filename}")

    cursor.close()
    conn.close()

    seed_script = os.path.join(BASE_DIR, "database", "seed_users.py")
    if os.path.exists(seed_script):
      env = os.environ.copy()
      env["PYTHONPATH"] = os.pathsep.join(sys.path)
      res = subprocess.run(
          [sys.executable, seed_script],
          capture_output=True,
          text=True,
          env=env,
      )
      logs.append(f"seed_users exit={res.returncode}: {res.stdout} {res.stderr}")

    logs.append("ALL DONE! Log in with admin / admin123")
    return "<pre>" + "\n".join(logs) + "</pre>", 200
  except Exception as e:
    logs.append(f"ERROR: {e}")
    return "<pre>" + "\n".join(logs) + "</pre>", 500