USE blood_bank;

DROP PROCEDURE IF EXISTS sp_issue_units;
DROP PROCEDURE IF EXISTS sp_suggest_alternatives;

DELIMITER $$

-- ============================================================
-- sp_issue_units(request_id, user_id)
-- FEFO issue: same blood type first, then compatible types
-- (O- last), earliest expiry first. Runs in one transaction
-- with row locks, so two users cannot take the same bag.
-- ============================================================
CREATE PROCEDURE sp_issue_units(IN p_request_id INT, IN p_user_id INT)
BEGIN
    DECLARE v_bt        TINYINT UNSIGNED;
    DECLARE v_needed    SMALLINT;
    DECLARE v_filled    SMALLINT;
    DECLARE v_remaining SMALLINT;
    DECLARE v_unit      INT;
    DECLARE v_issued    INT DEFAULT 0;
    DECLARE v_done      INT DEFAULT 0;

    DECLARE cur CURSOR FOR
        SELECT bu.unit_id
          FROM Blood_Units bu
          JOIN Blood_Compatibility bc
            ON bc.donor_type_id = bu.blood_type_id
           AND bc.recipient_type_id = v_bt
          JOIN Blood_Types t ON t.blood_type_id = bu.blood_type_id
         WHERE bu.status = 'Available'
           AND bu.expiry_date >= CURDATE()
         ORDER BY (bu.blood_type_id = v_bt) DESC,   -- same type first
                  (t.type_name = 'O-') ASC,         -- keep O- for last
                  bu.expiry_date ASC,               -- FEFO
                  bu.unit_id ASC
         FOR UPDATE;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT blood_type_id, units_needed, units_fulfilled
      INTO v_bt, v_needed, v_filled
      FROM Requests WHERE request_id = p_request_id FOR UPDATE;

    IF v_bt IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_REQUEST_NOT_FOUND';
    END IF;

    SET v_remaining = v_needed - v_filled;
    IF v_remaining <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_REQUEST_ALREADY_FULFILLED';
    END IF;

    OPEN cur;
    issue_loop: LOOP
        FETCH cur INTO v_unit;
        IF v_done = 1 OR v_remaining <= 0 THEN
            LEAVE issue_loop;
        END IF;

        INSERT INTO Request_Units (request_id, unit_id, issue_date, issued_by)
        VALUES (p_request_id, v_unit, CURDATE(), p_user_id);

        SET v_remaining = v_remaining - 1;
        SET v_issued    = v_issued + 1;
    END LOOP;
    CLOSE cur;

    COMMIT;

    SELECT v_issued AS units_issued,
           v_remaining AS units_still_missing,
           (SELECT status FROM Requests WHERE request_id = p_request_id) AS request_status;
END$$

-- ============================================================
-- sp_suggest_alternatives(request_id)
-- Stock available per compatible blood type (same type first)
-- ============================================================
CREATE PROCEDURE sp_suggest_alternatives(IN p_request_id INT)
BEGIN
    DECLARE v_bt TINYINT UNSIGNED;

    SELECT blood_type_id INTO v_bt FROM Requests WHERE request_id = p_request_id;

    IF v_bt IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_REQUEST_NOT_FOUND';
    END IF;

    SELECT t.type_name,
           (t.blood_type_id = v_bt) AS is_exact_match,
           COUNT(bu.unit_id)        AS units_available,
           MIN(bu.expiry_date)      AS nearest_expiry
      FROM Blood_Compatibility bc
      JOIN Blood_Types t ON t.blood_type_id = bc.donor_type_id
      LEFT JOIN Blood_Units bu
             ON bu.blood_type_id = t.blood_type_id
            AND bu.status = 'Available'
            AND bu.expiry_date >= CURDATE()
     WHERE bc.recipient_type_id = v_bt
     GROUP BY t.blood_type_id, t.type_name
     ORDER BY is_exact_match DESC, (t.type_name = 'O-') ASC, units_available DESC;
END$$

DELIMITER ;