USE blood_bank;

DROP VIEW IF EXISTS v_stock_by_type;
DROP VIEW IF EXISTS v_available_units;
DROP VIEW IF EXISTS v_eligible_donors;
DROP VIEW IF EXISTS v_open_requests;
DROP VIEW IF EXISTS v_net_shortage;
DROP VIEW IF EXISTS v_top_requested_types;

DROP PROCEDURE IF EXISTS sp_report_donations;
DROP PROCEDURE IF EXISTS sp_report_wastage;
DROP PROCEDURE IF EXISTS sp_report_requests;
DROP PROCEDURE IF EXISTS sp_report_hospital_consumption;
DROP PROCEDURE IF EXISTS sp_report_rejections;

-- ============================================================
-- VIEWS (no parameters; filters are added with WHERE from Flask)
-- ============================================================

-- 1) Current stock per blood type (all 8 types, even if zero)
CREATE VIEW v_stock_by_type AS
SELECT t.blood_type_id,
       t.type_name,
       COUNT(bu.unit_id)   AS units_available,
       MIN(bu.expiry_date) AS nearest_expiry
  FROM Blood_Types t
  LEFT JOIN Blood_Units bu
         ON bu.blood_type_id = t.blood_type_id
        AND bu.status = 'Available'
        AND bu.expiry_date >= CURDATE()
 GROUP BY t.blood_type_id, t.type_name;

-- 2) Available units with days left (FEFO order).
--    "Expiring soon" = WHERE days_left <= 7
CREATE VIEW v_available_units AS
SELECT bu.unit_id,
       t.type_name,
       bu.collection_date,
       bu.expiry_date,
       DATEDIFF(bu.expiry_date, CURDATE()) AS days_left
  FROM Blood_Units bu
  JOIN Blood_Types t ON t.blood_type_id = bu.blood_type_id
 WHERE bu.status = 'Available'
   AND bu.expiry_date >= CURDATE()
 ORDER BY bu.expiry_date ASC;

-- 3) Donors who can donate again (90 days male / 120 female)
CREATE VIEW v_eligible_donors AS
SELECT d.donor_id,
       d.full_name,
       d.gender,
       d.phone,
       d.city,
       t.type_name,
       TIMESTAMPDIFF(YEAR, d.birth_date, CURDATE()) AS age,
       d.last_donation_date,
       DATEDIFF(CURDATE(), d.last_donation_date)    AS days_since_last
  FROM Donors d
  JOIN Blood_Types t ON t.blood_type_id = d.blood_type_id
  JOIN Settings s
    ON s.setting_key = CASE d.gender WHEN 'Male' THEN 'deferral_days_male'
                                     ELSE 'deferral_days_female' END
 WHERE d.is_eligible = TRUE
   AND TIMESTAMPDIFF(YEAR, d.birth_date, CURDATE()) BETWEEN 18 AND 60
   AND (d.last_donation_date IS NULL
        OR DATEDIFF(CURDATE(), d.last_donation_date) >= s.setting_value);

-- 4) Open requests (urgent first, then oldest)
CREATE VIEW v_open_requests AS
SELECT r.request_id,
       h.name AS hospital,
       h.city,
       t.type_name,
       r.units_needed,
       r.units_fulfilled,
       (r.units_needed - r.units_fulfilled) AS units_missing,
       r.urgency,
       r.status,
       r.request_date,
       DATEDIFF(CURDATE(), r.request_date) AS days_waiting
  FROM Requests r
  JOIN Hospitals h  ON h.hospital_id = r.hospital_id
  JOIN Blood_Types t ON t.blood_type_id = r.blood_type_id
 WHERE r.status IN ('Pending','Partial')
 ORDER BY (r.urgency = 'Urgent') DESC, r.request_date ASC;

-- 5) Net shortage: stock vs open demand (same blood type)
CREATE VIEW v_net_shortage AS
SELECT x.type_name,
       x.stock,
       x.demand,
       (x.stock - x.demand) AS balance,
       CASE WHEN x.stock >= x.demand THEN 'OK' ELSE 'SHORTAGE' END AS state
  FROM (
        SELECT t.type_name,
               (SELECT COUNT(*) FROM Blood_Units bu
                 WHERE bu.blood_type_id = t.blood_type_id
                   AND bu.status = 'Available'
                   AND bu.expiry_date >= CURDATE()) AS stock,
               (SELECT COALESCE(SUM(r.units_needed - r.units_fulfilled), 0)
                  FROM Requests r
                 WHERE r.blood_type_id = t.blood_type_id
                   AND r.status IN ('Pending','Partial')) AS demand
          FROM Blood_Types t
       ) x;

-- 6) Most requested blood types (all time)
CREATE VIEW v_top_requested_types AS
SELECT t.type_name,
       COUNT(r.request_id)               AS requests_count,
       COALESCE(SUM(r.units_needed), 0)  AS units_requested
  FROM Blood_Types t
  LEFT JOIN Requests r ON r.blood_type_id = t.blood_type_id
 GROUP BY t.blood_type_id, t.type_name
 ORDER BY units_requested DESC;

-- ============================================================
-- PROCEDURES (with date filters). NULL dates = no limit.
-- ============================================================
DELIMITER $$

-- Donations per day / week / month   (p_period: 'day' | 'week' | 'month')
CREATE PROCEDURE sp_report_donations(IN p_from DATE, IN p_to DATE, IN p_period VARCHAR(10))
BEGIN
    SELECT CASE p_period
             WHEN 'month' THEN DATE_FORMAT(collection_date, '%Y-%m')
             WHEN 'week'  THEN DATE_FORMAT(DATE_SUB(collection_date,
                                    INTERVAL WEEKDAY(collection_date) DAY), '%Y-%m-%d')
             ELSE DATE_FORMAT(collection_date, '%Y-%m-%d')
           END                          AS period_label,
           COUNT(*)                     AS units_collected,
           SUM(volume_ml)               AS total_volume_ml,
           SUM(status = 'Rejected')     AS units_rejected
      FROM Blood_Units
     WHERE collection_date BETWEEN COALESCE(p_from, '2000-01-01') AND COALESCE(p_to, CURDATE())
     GROUP BY 1
     ORDER BY 1;
END$$

-- Wastage (expired bags) per month and its percentage
CREATE PROCEDURE sp_report_wastage(IN p_from DATE, IN p_to DATE)
BEGIN
    SELECT DATE_FORMAT(collection_date, '%Y-%m') AS month,
           COUNT(*) AS units_collected,
           SUM(status = 'Expired'
               OR (status IN ('Available','Reserved','Quarantine') AND expiry_date < CURDATE()))
                AS units_expired,
           ROUND(100 * SUM(status = 'Expired'
               OR (status IN ('Available','Reserved','Quarantine') AND expiry_date < CURDATE()))
                / COUNT(*), 1) AS wastage_pct
      FROM Blood_Units
     WHERE status <> 'Rejected'
       AND collection_date BETWEEN COALESCE(p_from, '2000-01-01') AND COALESCE(p_to, CURDATE())
     GROUP BY 1
     ORDER BY 1;
END$$

-- Requests in a period, optional hospital filter (NULL = all hospitals)
CREATE PROCEDURE sp_report_requests(IN p_from DATE, IN p_to DATE, IN p_hospital_id INT)
BEGIN
    SELECT r.request_id, h.name AS hospital, t.type_name,
           r.units_needed, r.units_fulfilled, r.urgency, r.status, r.request_date
      FROM Requests r
      JOIN Hospitals h   ON h.hospital_id = r.hospital_id
      JOIN Blood_Types t ON t.blood_type_id = r.blood_type_id
     WHERE r.request_date BETWEEN COALESCE(p_from, '2000-01-01') AND COALESCE(p_to, CURDATE())
       AND (p_hospital_id IS NULL OR r.hospital_id = p_hospital_id)
     ORDER BY r.request_date DESC, r.request_id DESC;
END$$

-- Which hospital takes the most blood, and how much of its demand was met
CREATE PROCEDURE sp_report_hospital_consumption(IN p_from DATE, IN p_to DATE)
BEGIN
    SELECT h.name, h.city,
           COUNT(r.request_id)                   AS requests_count,
           COALESCE(SUM(r.units_needed), 0)      AS units_requested,
           COALESCE(SUM(r.units_fulfilled), 0)   AS units_received,
           ROUND(100 * SUM(r.units_fulfilled) / NULLIF(SUM(r.units_needed), 0), 1) AS fulfillment_pct
      FROM Hospitals h
      LEFT JOIN Requests r
             ON r.hospital_id = h.hospital_id
            AND r.request_date BETWEEN COALESCE(p_from, '2000-01-01') AND COALESCE(p_to, CURDATE())
     GROUP BY h.hospital_id, h.name, h.city
     ORDER BY units_received DESC;
END$$

-- Lab rejections by virus type
CREATE PROCEDURE sp_report_rejections(IN p_from DATE, IN p_to DATE)
BEGIN
    SELECT COUNT(*)                                AS units_tested,
           COALESCE(SUM(bt.final_result = 'Failed'), 0) AS units_rejected,
           ROUND(100 * SUM(bt.final_result = 'Failed') / COUNT(*), 1) AS rejection_pct,
           COALESCE(SUM(bt.hiv_result = 'Positive'), 0)      AS hiv_positive,
           COALESCE(SUM(bt.hbv_result = 'Positive'), 0)      AS hbv_positive,
           COALESCE(SUM(bt.hcv_result = 'Positive'), 0)      AS hcv_positive,
           COALESCE(SUM(bt.syphilis_result = 'Positive'), 0) AS syphilis_positive
      FROM Blood_Tests bt
      JOIN Blood_Units bu ON bu.unit_id = bt.unit_id
     WHERE bt.final_result <> 'Pending'
       AND bu.collection_date BETWEEN COALESCE(p_from, '2000-01-01') AND COALESCE(p_to, CURDATE());
END$$

DELIMITER ;