import sys
import os
import bcrypt

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "app")))
from db import get_connection


def seed_users():
    users = [
        ("مدير النظام", "admin", "admin123", "Admin"),
        ("د. سارة (المعمل)", "lab", "lab123", "Lab_Tech"),
        ("أ. محمد (الاستقبال)", "staff", "staff123", "Bank_Staff"),
    ]

    conn = get_connection()
    cursor = conn.cursor()

    for full_name, username, raw_password, role in users:
        hashed = bcrypt.hashpw(raw_password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
        cursor.execute(
            """
            INSERT IGNORE INTO Users (full_name, username, password_hash, role, hospital_id)
            VALUES (%s, %s, %s, %s, NULL)
            """,
            (full_name, username, hashed, role),
        )

    conn.commit()
    print(f"تم تجهيز {cursor.rowcount} مستخدمين بنجاح!")
    cursor.close()
    conn.close()


if __name__ == "__main__":
    seed_users()