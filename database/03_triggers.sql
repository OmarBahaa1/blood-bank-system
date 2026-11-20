USE blood_bank;

DROP TRIGGER IF EXISTS trg_units_bi;
DROP TRIGGER IF EXISTS trg_units_ai;
DROP TRIGGER IF EXISTS trg_units_bu;
DROP TRIGGER IF EXISTS trg_tests_bu;
DROP TRIGGER IF EXISTS trg_tests_au;
DROP TRIGGER IF EXISTS trg_ru_bi;
DROP TRIGGER IF EXISTS trg_ru_ai;
DROP EVENT   IF EXISTS ev_expire_units;

DELIMITER $$

-- ============================================================
-- 1) Blood_Units BEFORE INSERT
--    donor eligibility, age 18-60, deferral period (90/120),
--    auto expiry_date, status always starts as Quarantine
-- ============================================================
CREATE TRIGGER trg_units_bi BEFORE INSERT ON Blood_Units
FOR EACH ROW
BEGIN
    DECLARE v_gender   VARCHAR(10);
    DECLARE v_birth    DATE;
    DECLARE v_last     DATE;
    DECLARE v_eligible BOOLEAN;
    DECLARE v_age      INT;
    DECLARE v_days     INT;
    DECLARE v_shelf    INT;

    SELECT gender, birth_date, last_donation_date, is_eligible
      INTO v_gender, v_birth, v_last, v_eligible
      FROM Donors WHERE donor_id = NEW.donor_id;

    IF v_birth IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_DONOR_NOT_FOUND';
    END IF;

    IF v_eligible = FALSE THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_DONOR_NOT_ELIGIBLE';
    END IF;

    SET v_age = TIMESTAMPDIFF(YEAR, v_birth, NEW.collection_date);
    IF v_age < 18 OR v_age > 60 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_DONOR_AGE_OUT_OF_RANGE';
    END IF;

    SELECT setting_value INTO v_days FROM Settings
     WHERE setting_key = IF(v_gender = 'Male', 'deferral_days_male', 'deferral_days_female');

    IF v_last IS NOT NULL AND DATEDIFF(NEW.collection_date, v_last) < v_days THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_DONOR_DEFERRAL_PERIOD';
    END IF;

    SELECT setting_value INTO v_shelf FROM Settings
     WHERE setting_key = 'red_cells_shelf_life';

    SET NEW.expiry_date = DATE_ADD(NEW.collection_date, INTERVAL v_shelf DAY);
    SET NEW.status      = 'Quarantine';
END$$

-- ============================================================
-- 2) Blood_Units AFTER INSERT
--    update donor's last donation + create the pending lab test
-- ============================================================
CREATE TRIGGER trg_units_ai AFTER INSERT ON Blood_Units
FOR EACH ROW
BEGIN
    UPDATE Donors
       SET last_donation_date = NEW.collection_date
     WHERE donor_id = NEW.donor_id
       AND (last_donation_date IS NULL OR last_donation_date < NEW.collection_date);

    INSERT INTO Blood_Tests (unit_id) VALUES (NEW.unit_id);
END$$

-- ============================================================
-- 3) Blood_Units BEFORE UPDATE
--    status state-machine: nobody can skip the lab or reuse a bag
-- ============================================================
CREATE TRIGGER trg_units_bu BEFORE UPDATE ON Blood_Units
FOR EACH ROW
BEGIN
    DECLARE v_passed INT DEFAULT 0;

    IF NEW.status <> OLD.status THEN

        IF OLD.status IN ('Used','Expired','Rejected') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_UNIT_STATUS_FINAL';
        END IF;

        IF NEW.status = 'Quarantine' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_UNIT_CANNOT_RETURN_TO_QUARANTINE';
        END IF;

        IF NEW.status = 'Available' AND OLD.status = 'Quarantine' THEN
            SELECT COUNT(*) INTO v_passed FROM Blood_Tests
             WHERE unit_id = OLD.unit_id AND final_result = 'Passed';
            IF v_passed = 0 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_UNIT_NOT_TESTED';
            END IF;
        END IF;

        IF NEW.status IN ('Reserved','Used') THEN
            IF OLD.status NOT IN ('Available','Reserved') THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_UNIT_NOT_AVAILABLE';
            END IF;
            IF OLD.expiry_date < CURDATE() THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_UNIT_EXPIRED';
            END IF;
        END IF;

    END IF;
END$$

-- ============================================================
-- 4) Blood_Tests BEFORE UPDATE
--    compute final_result automatically; results are final once decided
-- ============================================================
CREATE TRIGGER trg_tests_bu BEFORE UPDATE ON Blood_Tests
FOR EACH ROW
BEGIN
    IF OLD.final_result <> 'Pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_TEST_ALREADY_FINAL';
    END IF;

    IF NEW.hiv_result = 'Positive' OR NEW.hbv_result = 'Positive'
       OR NEW.hcv_result = 'Positive' OR NEW.syphilis_result = 'Positive' THEN
        SET NEW.final_result = 'Failed';
    ELSEIF NEW.hiv_result = 'Negative' AND NEW.hbv_result = 'Negative'
       AND NEW.hcv_result = 'Negative' AND NEW.syphilis_result = 'Negative' THEN
        SET NEW.final_result = 'Passed';
    ELSE
        SET NEW.final_result = 'Pending';
    END IF;

    IF NEW.final_result <> 'Pending' AND NEW.test_date IS NULL THEN
        SET NEW.test_date = CURDATE();
    END IF;
END$$

-- ============================================================
-- 5) Blood_Tests AFTER UPDATE
--    Passed -> Available | Failed -> Rejected + donor deferred
-- ============================================================
CREATE TRIGGER trg_tests_au AFTER UPDATE ON Blood_Tests
FOR EACH ROW
BEGIN
    IF OLD.final_result = 'Pending' AND NEW.final_result = 'Passed' THEN
        UPDATE Blood_Units SET status = 'Available'
         WHERE unit_id = NEW.unit_id AND status = 'Quarantine';

    ELSEIF OLD.final_result = 'Pending' AND NEW.final_result = 'Failed' THEN
        UPDATE Blood_Units SET status = 'Rejected'
         WHERE unit_id = NEW.unit_id AND status = 'Quarantine';

        UPDATE Donors
           SET is_eligible = FALSE,
               deferral_reason = CONCAT('Positive screening on unit ', NEW.unit_id)
         WHERE donor_id = (SELECT donor_id FROM Blood_Units WHERE unit_id = NEW.unit_id);
    END IF;
END$$

-- ============================================================
-- 6) Request_Units BEFORE INSERT  (the issue rules)
--    unit must be Available, not expired, blood-compatible,
--    and the request must still need units
-- ============================================================
CREATE TRIGGER trg_ru_bi BEFORE INSERT ON Request_Units
FOR EACH ROW
BEGIN
    DECLARE v_u_status VARCHAR(20);
    DECLARE v_u_expiry DATE;
    DECLARE v_u_bt     TINYINT UNSIGNED;
    DECLARE v_r_bt     TINYINT UNSIGNED;
    DECLARE v_needed   SMALLINT;
    DECLARE v_filled   SMALLINT;
    DECLARE v_compat   INT;

    SELECT status, expiry_date, blood_type_id
      INTO v_u_status, v_u_expiry, v_u_bt
      FROM Blood_Units WHERE unit_id = NEW.unit_id;

    SELECT blood_type_id, units_needed, units_fulfilled
      INTO v_r_bt, v_needed, v_filled
      FROM Requests WHERE request_id = NEW.request_id;

    IF v_u_status IS NULL OR v_r_bt IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_UNIT_OR_REQUEST_NOT_FOUND';
    END IF;

    IF v_u_status <> 'Available' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_UNIT_NOT_AVAILABLE';
    END IF;

    IF v_u_expiry < CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_UNIT_EXPIRED';
    END IF;

    IF v_filled >= v_needed THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_REQUEST_ALREADY_FULFILLED';
    END IF;

    SELECT COUNT(*) INTO v_compat FROM Blood_Compatibility
     WHERE recipient_type_id = v_r_bt AND donor_type_id = v_u_bt;
    IF v_compat = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_BLOOD_TYPE_INCOMPATIBLE';
    END IF;
END$$

-- ============================================================
-- 7) Request_Units AFTER INSERT
--    mark unit Used, update request counters and status
-- ============================================================
CREATE TRIGGER trg_ru_ai AFTER INSERT ON Request_Units
FOR EACH ROW
BEGIN
    DECLARE v_needed SMALLINT;
    DECLARE v_filled SMALLINT;

    UPDATE Blood_Units SET status = 'Used' WHERE unit_id = NEW.unit_id;

    SELECT units_needed, units_fulfilled INTO v_needed, v_filled
      FROM Requests WHERE request_id = NEW.request_id;

    SET v_filled = v_filled + 1;

    UPDATE Requests
       SET units_fulfilled = v_filled,
           status = IF(v_filled >= v_needed, 'Fulfilled', 'Partial')
     WHERE request_id = NEW.request_id;
END$$

-- ============================================================
-- 8) Daily event: expire old units
-- ============================================================
CREATE EVENT ev_expire_units
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    UPDATE Blood_Units
       SET status = 'Expired'
     WHERE status IN ('Quarantine','Available','Reserved')
       AND expiry_date < CURDATE();
END$$

DELIMITER ;

SET GLOBAL event_scheduler = ON;