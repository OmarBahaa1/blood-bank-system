USE blood_bank;

DROP PROCEDURE IF EXISTS sp_seed_add_unit;
DROP PROCEDURE IF EXISTS sp_seed_demo_data;

DELIMITER $$

-- helper: register one bag and push it through the lab
CREATE PROCEDURE sp_seed_add_unit(IN p_donor INT, IN p_bt TINYINT UNSIGNED,
                                  IN p_days_ago INT, IN p_outcome VARCHAR(20))
BEGIN
    DECLARE v_unit INT;
    DECLARE v_col  DATE;

    SET v_col = DATE_SUB(CURDATE(), INTERVAL p_days_ago DAY);

    INSERT INTO Blood_Units (donor_id, blood_type_id, collection_date)
    VALUES (p_donor, p_bt, v_col);
    SET v_unit = LAST_INSERT_ID();

    IF p_outcome <> 'PENDING' THEN
        UPDATE Blood_Tests
           SET hiv_result      = IF(p_outcome = 'FAIL_HIV',  'Positive', 'Negative'),
               hbv_result      = IF(p_outcome = 'FAIL_HBV',  'Positive', 'Negative'),
               hcv_result      = IF(p_outcome = 'FAIL_HCV',  'Positive', 'Negative'),
               syphilis_result = IF(p_outcome = 'FAIL_SYPH', 'Positive', 'Negative'),
               test_date       = DATE_ADD(v_col, INTERVAL IF(p_days_ago > 0, 1, 0) DAY)
         WHERE unit_id = v_unit;

        -- old bags that passed the lab but were never used -> expired
        IF p_outcome = 'PASS' AND p_days_ago > 35 THEN
            UPDATE Blood_Units SET status = 'Expired' WHERE unit_id = v_unit;
        END IF;
    END IF;
END$$

CREATE PROCEDURE sp_seed_demo_data()
BEGIN
    DECLARE i        INT DEFAULT 1;
    DECLARE j        INT DEFAULT 1;
    DECLARE v_h0     INT;
    DECLARE v_gender VARCHAR(10);
    DECLARE v_first  VARCHAR(30);
    DECLARE v_name   VARCHAR(100);
    DECLARE v_birth  DATE;
    DECLARE v_ci     INT;
    DECLARE v_tn     VARCHAR(3);
    DECLARE v_bt     TINYINT UNSIGNED;
    DECLARE v_d      INT;
    DECLARE v_p      INT;
    DECLARE v_r      INT;

    IF (SELECT COUNT(*) FROM Donors) > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_DB_NOT_EMPTY: rerun 01, 02, 03 first';
    END IF;

    -- ---------- hospitals ----------
    INSERT INTO Hospitals (name, city, phone) VALUES
      ('مستشفى قصر العيني',            'القاهرة',    '0223654444'),
      ('مستشفى أبو الريش للأطفال',      'القاهرة',    '0223682222'),
      ('المعهد القومي للأورام',          'القاهرة',    '0223644444'),
      ('مستشفى الإسكندرية الجامعي',      'الإسكندرية', '0334861111'),
      ('مستشفى المنصورة الجامعي',        'المنصورة',   '0502202222'),
      ('مستشفى أسيوط الجامعي',          'أسيوط',      '0882413333');
    SET v_h0 = LAST_INSERT_ID();

    -- ---------- 60 donors + their donations ----------
    WHILE i <= 60 DO
        SET v_gender = IF(MOD(i, 3) = 0, 'Female', 'Male');
        SET v_ci     = MOD(i, 6) + 1;

        SET v_first = IF(v_gender = 'Male',
            ELT(MOD(i,10)+1, 'أحمد','محمد','محمود','مصطفى','عمر','علي','حسن','إبراهيم','خالد','يوسف'),
            ELT(MOD(i,10)+1, 'منى','سارة','نورهان','هدى','فاطمة','مريم','آية','دينا','ياسمين','رنا'));

        SET v_name = CONCAT(v_first, ' ',
            ELT(MOD(i*3,10)+1, 'محمد','أحمد','علي','حسن','إبراهيم','سعيد','فتحي','جمال','ناصر','طارق'), ' ',
            ELT(MOD(i*7,10)+1, 'السيد','عبد الرحمن','حسين','الشافعي','النجار','فرج','عطية','سلامة','البنا','رمضان'));

        SET v_birth = DATE_ADD('1975-01-01', INTERVAL MOD(i*263, 10500) DAY);

        SET v_tn = ELT(MOD(i,19)+1, 'O+','O+','O+','O+','O+','O+','O+','O+',
                                     'A+','A+','A+','A+','B+','B+','AB+','O-','A-','B-','AB-');
        SELECT blood_type_id INTO v_bt FROM Blood_Types WHERE type_name = v_tn;

        INSERT INTO Donors (full_name, national_id, gender, birth_date, phone, city, weight_kg, blood_type_id)
        VALUES (
            v_name,
            -- Egyptian ID: century + yymmdd + governorate + 4-digit serial (odd=male) + check digit
            CONCAT(IF(v_birth >= '2000-01-01', '3', '2'),
                   DATE_FORMAT(v_birth, '%y%m%d'),
                   ELT(v_ci, '01','21','02','12','27','31'),
                   LPAD(i*2 + IF(v_gender = 'Male', 1, 0), 4, '0'),
                   MOD(i, 10)),
            v_gender,
            v_birth,
            CONCAT(ELT(MOD(i,4)+1, '010','011','012','015'), LPAD(10000000 + i*137, 8, '0')),
            ELT(v_ci, 'القاهرة','الجيزة','الإسكندرية','المنصورة','أسيوط','طنطا'),
            55 + MOD(i*7, 40),
            v_bt);
        SET v_d = LAST_INSERT_ID();

        SET v_p = MOD(i, 5);
        IF v_p = 1 THEN
            CALL sp_seed_add_unit(v_d, v_bt, 1 + MOD(i*7, 30), 'PASS');
        ELSEIF v_p = 2 THEN
            CALL sp_seed_add_unit(v_d, v_bt, 2 + MOD(i*11, 32), 'PASS');
        ELSEIF v_p = 3 THEN
            -- repeat donor: an old bag (expired) then a recent one
            CALL sp_seed_add_unit(v_d, v_bt, 150 + MOD(i*9, 50), 'PASS');
            CALL sp_seed_add_unit(v_d, v_bt, 1 + MOD(i*5, 30), 'PASS');
        ELSEIF v_p = 4 THEN
            IF MOD(i, 10) = 4 THEN
                CALL sp_seed_add_unit(v_d, v_bt, 5 + MOD(i*3, 28),
                     ELT(MOD(FLOOR(i/10), 4) + 1, 'FAIL_HIV','FAIL_HBV','FAIL_HCV','FAIL_SYPH'));
            ELSE
                CALL sp_seed_add_unit(v_d, v_bt, MOD(i, 3), 'PENDING');
            END IF;
        END IF;
        -- v_p = 0: new donor, no donation yet

        SET i = i + 1;
    END WHILE;

    -- ---------- 14 requests, issued with the FEFO procedure ----------
    WHILE j <= 14 DO
        SET v_tn = ELT(j, 'A+','O+','B+','A+','O+','AB+','O+','A+','B+','O-','A-','AB-','O+','B+');
        SELECT blood_type_id INTO v_bt FROM Blood_Types WHERE type_name = v_tn;

        INSERT INTO Requests (hospital_id, blood_type_id, units_needed, request_date, urgency)
        VALUES (v_h0 + MOD(j, 6), v_bt,
                ELT(j, 2,2,1,1,2,1,3,1,2,2,1,2,2,1),
                DATE_SUB(CURDATE(), INTERVAL (1 + MOD(j*2, 20)) DAY),
                IF(MOD(j, 4) = 0, 'Urgent', 'Normal'));
        SET v_r = LAST_INSERT_ID();
        CALL sp_issue_units(v_r, NULL);
        SET j = j + 1;
    END WHILE;

    -- ---------- fresh requests: some partial, some untouched ----------
    SELECT blood_type_id INTO v_bt FROM Blood_Types WHERE type_name = 'O-';
    INSERT INTO Requests (hospital_id, blood_type_id, units_needed, request_date, urgency)
    VALUES (v_h0, v_bt, 4, CURDATE(), 'Urgent');
    CALL sp_issue_units(LAST_INSERT_ID(), NULL);

    SELECT blood_type_id INTO v_bt FROM Blood_Types WHERE type_name = 'B-';
    INSERT INTO Requests (hospital_id, blood_type_id, units_needed, request_date, urgency)
    VALUES (v_h0 + 3, v_bt, 3, DATE_SUB(CURDATE(), INTERVAL 1 DAY), 'Urgent');

    SELECT blood_type_id INTO v_bt FROM Blood_Types WHERE type_name = 'AB+';
    INSERT INTO Requests (hospital_id, blood_type_id, units_needed, request_date, urgency)
    VALUES (v_h0 + 4, v_bt, 5, DATE_SUB(CURDATE(), INTERVAL 2 DAY), 'Normal');

    -- spread issue dates realistically (after collection, not before the request)
    UPDATE Request_Units ru
      JOIN Requests r    ON r.request_id = ru.request_id
      JOIN Blood_Units bu ON bu.unit_id = ru.unit_id
       SET ru.issue_date = LEAST(CURDATE(),
                           GREATEST(r.request_date, DATE_ADD(bu.collection_date, INTERVAL 1 DAY)));

    -- summary
    SELECT (SELECT COUNT(*) FROM Donors)    AS donors,
           (SELECT COUNT(*) FROM Hospitals) AS hospitals,
           (SELECT COUNT(*) FROM Blood_Units) AS units,
           (SELECT COUNT(*) FROM Blood_Units WHERE status = 'Available')  AS available,
           (SELECT COUNT(*) FROM Blood_Units WHERE status = 'Used')       AS used,
           (SELECT COUNT(*) FROM Blood_Units WHERE status = 'Expired')    AS expired,
           (SELECT COUNT(*) FROM Blood_Units WHERE status = 'Rejected')   AS rejected,
           (SELECT COUNT(*) FROM Blood_Units WHERE status = 'Quarantine') AS quarantine,
           (SELECT COUNT(*) FROM Requests)  AS requests;
END$$

DELIMITER ;

CALL sp_seed_demo_data();

DROP PROCEDURE sp_seed_demo_data;
DROP PROCEDURE sp_seed_add_unit;