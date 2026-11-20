# Blood Bank Management System | نظام إدارة بنك الدم

نظام لإدارة بنك دم مركزي بيخدم مستشفيات متعاقدة: تسجيل المتبرعين، تتبع أكياس الدم من التبرع للصرف، فحص الأكياس، وتلبية طلبات المستشفيات.

## المميزات
- حجر صحي وفحص (HIV, HBV, HCV, Syphilis) قبل ما الكيس يبقى متاح
- صلاحية الكيس 35 يوم وتحويله تلقائياً لـ Expired
- فترة انتظار بين التبرعات: 90 يوم للذكور / 120 للإناث
- توافق الفصائل (Blood_Compatibility)
- كل القواعد الطبية متفرضة جوه الداتابيز (Triggers)

## الأدوات
Python 3.12+ · MySQL 8 · MySQL Workbench · Flask · Git

## طريقة التشغيل
1. استنسخ المشروع:
   ```
   git clone https://github.com/OmarBahaa1/blood-bank-system.git
   cd blood-bank-system
   ```
2. اعمل virtual environment وثبّت المكتبات:
   ```
   python -m venv venv
   venv\Scripts\activate
   pip install -r requirements.txt
   ```
3. انسخ `.env.example` لـ `.env` وحط باسورد MySQL بتاعك.
4. في MySQL Workbench شغّل بالترتيب:
   - `database/01_create_tables.sql`
   - `database/02_seed_reference_data.sql`
   - `database/03_triggers.sql`
5. اختبر الاتصال: `python app/db.py`

## هيكل المشروع
```
app/        كود Python (Flask لاحقاً)
database/   ملفات SQL (شغّلها بالترتيب)
docs/       ERD والتوثيق
```