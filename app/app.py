import os
from datetime import date
from functools import wraps
import bcrypt
import mysql.connector
from dotenv import load_dotenv
from flask import Flask, render_template, request, redirect, url_for, session, flash
from db import get_connection

load_dotenv()

app = Flask(__name__, template_folder="pages", static_folder="assets")
app.secret_key = os.getenv("SECRET_KEY", "wateen_blood_bank_secret_2026")


@app.context_processor
def inject_globals():
    return {
        "project_name": os.getenv("APP_NAME", "وَتِين | Wateen"),
        "project_tagline": os.getenv("APP_TAGLINE", "شريان حياة يصل في الوقت المناسب"),
        "today": date.today().isoformat(),
    }


def translate_db_error(err):
    msg = str(err)
    errors_map = {
        "ERR_DONOR_NOT_FOUND": "المتبرع غير مسجل في النظام.",
        "ERR_DONOR_NOT_ELIGIBLE": "عذراً، هذا المتبرع غير مؤهل للتبرع حالياً (موقوف طبياً).",
        "ERR_DONOR_AGE_OUT_OF_RANGE": "عمر المتبرع يجب أن يكون بين 18 و 60 عاماً.",
        "ERR_DONOR_DEFERRAL_PERIOD": "لم تمر فترة الراحة القانونية (90 يوم للرجال / 120 للسيدات) منذ آخر تبرع.",
        "ERR_TEST_ALREADY_FINAL": "تم اعتماد نتيجة هذا الفحص مسبقاً ولا يمكن تعديلها.",
        "ERR_REQUEST_NOT_FOUND": "طلب المستشفى غير موجود.",
        "ERR_REQUEST_ALREADY_FULFILLED": "هذا الطلب مكتمل بالفعل.",
        "ERR_UNIT_NOT_AVAILABLE": "كيس الدم غير متاح للصرف حالياً.",
        "ERR_UNIT_EXPIRED": "صلاحية كيس الدم منتهية.",
        "ERR_BLOOD_TYPE_INCOMPATIBLE": "فصيلة الدم غير متوافقة مع فصيلة الطلب.",
        "chk_weight": "وزن المتبرع يجب ألا يقل عن 50 كجم.",
        "chk_national_id": "الرقم القومي يجب أن يتكون من 14 رقماً صحيحاً.",
        "Duplicate entry": "الرقم القومي مسجل بالفعل لمتبرع آخر.",
    }
    for key, arabic_msg in errors_map.items():
        if key in msg:
            return arabic_msg
    return f"حدث خطأ في قاعدة البيانات: {msg}"


def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if "user_id" not in session:
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorated


def role_required(*allowed_roles):
    def decorator(f):
        @wraps(f)
        def decorated(*args, **kwargs):
            if "user_id" not in session:
                return redirect(url_for("login"))
            if session.get("role") not in allowed_roles:
                flash("ليس لديك صلاحية للوصول إلى هذه الصفحة.", "warning")
                return redirect(url_for("dashboard"))
            return f(*args, **kwargs)
        return decorated
    return decorator


# ==========================================
# 1. تسجيل الدخول والخروج
# ==========================================
@app.route("/")
def index():
    if "user_id" in session:
        return redirect(url_for("dashboard"))
    return redirect(url_for("login"))


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")

        conn = get_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM Users WHERE username = %s", (username,))
        user = cursor.fetchone()
        cursor.close()
        conn.close()

        if user and bcrypt.checkpw(password.encode("utf-8"), user["password_hash"].encode("utf-8")):
            session["user_id"] = user["user_id"]
            session["full_name"] = user["full_name"]
            session["role"] = user["role"]
            if user["role"] == "Lab_Tech":
                return redirect(url_for("lab_screening"))
            return redirect(url_for("dashboard"))

        flash("اسم المستخدم أو كلمة المرور غير صحيحة", "danger")

    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


# ==========================================
# 2. لوحة التحكم (Dashboard)
# ==========================================
@app.route("/dashboard")
@login_required
def dashboard():
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)

    cursor.execute("SELECT * FROM v_stock_by_type")
    stock_by_type = cursor.fetchall()

    cursor.execute("SELECT * FROM v_net_shortage WHERE state = 'SHORTAGE'")
    shortages = cursor.fetchall()

    cursor.execute("SELECT * FROM v_available_units WHERE days_left <= 7")
    expiring_soon = cursor.fetchall()

    cursor.execute("SELECT * FROM v_open_requests")
    open_requests = cursor.fetchall()

    cursor.execute("SELECT COUNT(*) AS cnt FROM Blood_Units WHERE status = 'Quarantine'")
    quarantine_count = cursor.fetchone()["cnt"]

    cursor.close()
    conn.close()

    total_available = sum(item["units_available"] for item in stock_by_type)

    return render_template(
        "dashboard.html",
        stock_by_type=stock_by_type,
        shortages=shortages,
        expiring_soon=expiring_soon,
        open_requests=open_requests,
        quarantine_count=quarantine_count,
        total_available=total_available,
    )


# ==========================================
# 3. إدارة المتبرعين والتبرع الجديد (Donors)
# ==========================================
@app.route("/donors")
@role_required("Admin", "Bank_Staff")
def donors():
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)

    cursor.execute("""
        SELECT d.*, bt.type_name
          FROM Donors d
          JOIN Blood_Types bt ON d.blood_type_id = bt.blood_type_id
         ORDER BY d.created_at DESC, d.donor_id DESC
    """)
    donors_list = cursor.fetchall()

    cursor.execute("SELECT * FROM Blood_Types ORDER BY blood_type_id")
    blood_types = cursor.fetchall()

    cursor.close()
    conn.close()

    return render_template("donors.html", donors=donors_list, blood_types=blood_types)


@app.route("/donors/add", methods=["POST"])
@role_required("Admin", "Bank_Staff")
def add_donor():
    full_name = request.form.get("full_name", "").strip()
    national_id = request.form.get("national_id", "").strip()
    gender = request.form.get("gender")
    birth_date = request.form.get("birth_date")
    phone = request.form.get("phone", "").strip()
    city = request.form.get("city", "").strip()
    weight_kg = request.form.get("weight_kg")
    blood_type_id = request.form.get("blood_type_id")

    # شرط العمر (18-60 سنة مكتملة) يُفحص هنا قبل الحفظ؛ السيرفر هو المرجع وليس الواجهة.
    # نفس منطق TIMESTAMPDIFF(YEAR, birth_date, ...) في trigger جدول Blood_Units.
    from datetime import datetime

    def age_words(n):
        if n == 0:
            return "أقل من سنة"
        if n == 1:
            return "سنة واحدة"
        if n == 2:
            return "سنتان"
        if 3 <= n % 100 <= 10:
            return f"{n} سنوات"
        return f"{n} سنة"

    if not birth_date:
        flash("أدخل تاريخ ميلاد المتبرع.", "danger")
        return redirect(url_for("donors"))
    try:
        born = datetime.strptime(birth_date, "%Y-%m-%d").date()
    except ValueError:
        flash("تاريخ الميلاد غير صحيح. أدخل تاريخًا حقيقيًا (اليوم والشهر والسنة).", "danger")
        return redirect(url_for("donors"))

    today = date.today()
    if born > today:
        flash("تاريخ الميلاد لم يأتِ بعد. راجع التاريخ.", "danger")
        return redirect(url_for("donors"))

    age = today.year - born.year - ((today.month, today.day) < (born.month, born.day))
    if age < 18 or age > 60:
        flash(
            f"المتبرع عمره {age_words(age)}. التبرع بالدم متاح من عمر 18 إلى 60 سنة "
            "حفاظًا على سلامة المتبرع. تأكد من تاريخ الميلاد.",
            "danger",
        )
        return redirect(url_for("donors"))

    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            INSERT INTO Donors (full_name, national_id, gender, birth_date, phone, city, weight_kg, blood_type_id)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (full_name, national_id, gender, birth_date, phone, city, weight_kg, blood_type_id),
        )
        conn.commit()
        flash(f"تم تسجيل المتبرع ({full_name}) بنجاح!", "success")
    except mysql.connector.Error as err:
        conn.rollback()
        flash(translate_db_error(err), "danger")
    finally:
        cursor.close()
        conn.close()

    return redirect(url_for("donors"))


@app.route("/donations/add", methods=["POST"])
@role_required("Admin", "Bank_Staff")
def add_donation():
    donor_id = request.form.get("donor_id")
    collection_date = request.form.get("collection_date")
    volume_ml = request.form.get("volume_ml", 450)
    storage_location = request.form.get("storage_location", "ثلاجة الحجر الصحي A1").strip()

    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT blood_type_id, full_name FROM Donors WHERE donor_id = %s", (donor_id,))
        donor = cursor.fetchone()
        if not donor:
            flash("المتبرع غير موجود.", "danger")
            return redirect(url_for("donors"))

        cursor.execute(
            """
            INSERT INTO Blood_Units (donor_id, blood_type_id, collection_date, expiry_date, volume_ml, storage_location)
            VALUES (%s, %s, %s, DATE_ADD(%s, INTERVAL 42 DAY), %s, %s)
            """,
            (donor_id, donor["blood_type_id"], collection_date, collection_date, volume_ml, storage_location),
        )
        conn.commit()
        flash(
            f"تم تسجيل تبرع ({donor['full_name']}) وإرسال الكيس إلى الحجر الصحي (Quarantine) للفحص المعملي.",
            "success",
        )
    except mysql.connector.Error as err:
        conn.rollback()
        flash(translate_db_error(err), "danger")
    finally:
        cursor.close()
        conn.close()

    return redirect(url_for("donors"))


# ==========================================
# 4. فحوصات المعمل (Lab Screening)
# ==========================================
@app.route("/lab")
@role_required("Admin", "Lab_Tech")
def lab_screening():
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)

    cursor.execute("""
        SELECT t.test_id, t.unit_id, t.hiv_result, t.hbv_result, t.hcv_result, t.syphilis_result,
               u.collection_date, u.expiry_date, u.volume_ml, u.storage_location,
               bt.type_name, d.full_name AS donor_name
          FROM Blood_Tests t
          JOIN Blood_Units u ON u.unit_id = t.unit_id
          JOIN Blood_Types bt ON bt.blood_type_id = u.blood_type_id
          JOIN Donors d ON d.donor_id = u.donor_id
         WHERE t.final_result = 'Pending'
         ORDER BY u.collection_date ASC, t.test_id ASC
    """)
    pending_tests = cursor.fetchall()

    cursor.execute("""
        SELECT t.test_id, t.unit_id, t.hiv_result, t.hbv_result, t.hcv_result, t.syphilis_result,
               t.final_result, t.test_date, bt.type_name, usr.full_name AS tested_by_name
          FROM Blood_Tests t
          JOIN Blood_Units u ON u.unit_id = t.unit_id
          JOIN Blood_Types bt ON bt.blood_type_id = u.blood_type_id
          LEFT JOIN Users usr ON usr.user_id = t.tested_by
         WHERE t.final_result <> 'Pending'
         ORDER BY t.test_date DESC, t.test_id DESC
         LIMIT 12
    """)
    completed_tests = cursor.fetchall()

    cursor.close()
    conn.close()

    return render_template(
        "lab.html",
        pending_tests=pending_tests,
        completed_tests=completed_tests,
    )


@app.route("/lab/submit/<int:test_id>", methods=["POST"])
@role_required("Admin", "Lab_Tech")
def submit_lab_test(test_id):
    hiv = request.form.get("hiv_result")
    hbv = request.form.get("hbv_result")
    hcv = request.form.get("hcv_result")
    syphilis = request.form.get("syphilis_result")

    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            UPDATE Blood_Tests
               SET hiv_result = %s,
                   hbv_result = %s,
                   hcv_result = %s,
                   syphilis_result = %s,
                   tested_by = %s
             WHERE test_id = %s
            """,
            (hiv, hbv, hcv, syphilis, session["user_id"], test_id),
        )
        conn.commit()
        if "Positive" in (hiv, hbv, hcv, syphilis):
            flash("تم تسجيل نتيجة إيجابية: تم استبعاد الكيس وإيقاف أهلية المتبرع تلقائياً.", "warning")
        else:
            flash("الفحص سليم 100%: تم اعتماد الكيس وإضافته للمخزون المتاح (Available).", "success")
    except mysql.connector.Error as err:
        conn.rollback()
        flash(translate_db_error(err), "danger")
    finally:
        cursor.close()
        conn.close()

    return redirect(url_for("lab_screening"))


# ==========================================
# 5. طلبات المستشفيات وصرف الأكياس (FEFO)
# ==========================================
@app.route("/requests")
@role_required("Admin", "Bank_Staff")
def requests_page():
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)

    cursor.execute("""
        SELECT r.request_id, h.name AS hospital_name, h.city, bt.type_name,
               r.units_needed, r.units_fulfilled, (r.units_needed - r.units_fulfilled) AS units_missing,
               r.request_date, r.urgency, r.status
          FROM Requests r
          JOIN Hospitals h ON h.hospital_id = r.hospital_id
          JOIN Blood_Types bt ON bt.blood_type_id = r.blood_type_id
         WHERE r.status IN ('Pending', 'Partial')
         ORDER BY (r.urgency = 'Urgent') DESC, r.request_date ASC, r.request_id ASC
    """)
    open_requests = cursor.fetchall()

    cursor.execute("""
        SELECT r.request_id, h.name AS hospital_name, h.city, bt.type_name,
               r.units_needed, r.units_fulfilled, r.request_date, r.urgency, r.status
          FROM Requests r
          JOIN Hospitals h ON h.hospital_id = r.hospital_id
          JOIN Blood_Types bt ON bt.blood_type_id = r.blood_type_id
         WHERE r.status = 'Fulfilled'
         ORDER BY r.request_id DESC
         LIMIT 10
    """)
    fulfilled_requests = cursor.fetchall()

    cursor.execute("SELECT * FROM Hospitals ORDER BY name")
    hospitals = cursor.fetchall()

    cursor.execute("SELECT * FROM Blood_Types ORDER BY blood_type_id")
    blood_types = cursor.fetchall()

    cursor.close()
    conn.close()

    return render_template(
        "requests.html",
        open_requests=open_requests,
        fulfilled_requests=fulfilled_requests,
        hospitals=hospitals,
        blood_types=blood_types,
    )


@app.route("/requests/add", methods=["POST"])
@role_required("Admin", "Bank_Staff")
def add_request():
    hospital_id = request.form.get("hospital_id")
    blood_type_id = request.form.get("blood_type_id")
    units_needed = request.form.get("units_needed")
    urgency = request.form.get("urgency", "Normal")

    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            INSERT INTO Requests (hospital_id, blood_type_id, units_needed, request_date, urgency)
            VALUES (%s, %s, %s, CURDATE(), %s)
            """,
            (hospital_id, blood_type_id, units_needed, urgency),
        )
        conn.commit()
        flash("تم تسجيل طلب المستشفى بنجاح!", "success")
    except mysql.connector.Error as err:
        conn.rollback()
        flash(translate_db_error(err), "danger")
    finally:
        cursor.close()
        conn.close()

    return redirect(url_for("requests_page"))


@app.route("/requests/<int:request_id>/issue", methods=["POST"])
@role_required("Admin", "Bank_Staff")
def issue_request_units(request_id):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.callproc("sp_issue_units", [request_id, session["user_id"]])
        result_row = None
        for res in cursor.stored_results():
            result_row = res.fetchone()
        conn.commit()

        if result_row:
            issued, missing, status = result_row
            if issued == 0:
                flash("لا توجد أكياس متاحة أو متوافقة في المخزون حالياً لصرف هذا الطلب.", "warning")
            elif missing == 0:
                flash(f"تم صرف {issued} كيس بنظام FEFO واكتمال الطلب بالكامل!", "success")
            else:
                flash(f"تم صرف {issued} كيس بنظام FEFO (صرف جزئي — متبقي {missing} كيس).", "info")
    except mysql.connector.Error as err:
        conn.rollback()
        flash(translate_db_error(err), "danger")
    finally:
        cursor.close()
        conn.close()

    return redirect(url_for("requests_page"))


# ==========================================
# 6. سجل المخزون الكامل (Inventory)
# ==========================================
@app.route("/inventory")
@role_required("Admin", "Bank_Staff")
def inventory():
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)

    cursor.execute("""
        SELECT u.unit_id, bt.type_name, d.full_name AS donor_name,
               u.collection_date, u.expiry_date,
               DATEDIFF(u.expiry_date, CURDATE()) AS days_left,
               u.volume_ml, u.storage_location, u.status
          FROM Blood_Units u
          JOIN Blood_Types bt ON bt.blood_type_id = u.blood_type_id
          JOIN Donors d ON d.donor_id = u.donor_id
         ORDER BY FIELD(u.status, 'Available', 'Quarantine', 'Reserved', 'Used', 'Expired', 'Rejected'),
                  u.expiry_date ASC, u.unit_id DESC
    """)
    units = cursor.fetchall()

    cursor.close()
    conn.close()

    return render_template("inventory.html", units=units)


if __name__ == "__main__":
    app.run(debug=True)