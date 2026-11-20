-- ============================================
-- Blood Bank Management System
-- 01_create_tables.sql
-- ============================================

CREATE DATABASE IF NOT EXISTS blood_bank
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE blood_bank;

-- نمسح الجداول القديمة بالترتيب العكسي (عشان الـ Foreign Keys)
DROP TABLE IF EXISTS Request_Units;
DROP TABLE IF EXISTS Requests;
DROP TABLE IF EXISTS Blood_Tests;
DROP TABLE IF EXISTS Blood_Units;
DROP TABLE IF EXISTS Blood_Compatibility;
DROP TABLE IF EXISTS Users;
DROP TABLE IF EXISTS Hospitals;
DROP TABLE IF EXISTS Donors;
DROP TABLE IF EXISTS Settings;
DROP TABLE IF EXISTS Blood_Types;

-- ============================================
-- 1) الجداول الأساسية
-- ============================================

CREATE TABLE Blood_Types (
    blood_type_id TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    type_name     VARCHAR(3) NOT NULL UNIQUE
) ENGINE=InnoDB;

-- إعدادات السيستم (مكان واحد للأرقام اللي ممكن تتغير)
CREATE TABLE Settings (
    setting_key   VARCHAR(50) PRIMARY KEY,
    setting_value INT NOT NULL,
    description   VARCHAR(200)
) ENGINE=InnoDB;

CREATE TABLE Donors (
    donor_id           INT AUTO_INCREMENT PRIMARY KEY,
    full_name          VARCHAR(100) NOT NULL,
    national_id        CHAR(14) NOT NULL UNIQUE,
    gender             ENUM('Male','Female') NOT NULL,
    birth_date         DATE NOT NULL,
    phone              VARCHAR(15),
    city               VARCHAR(50),
    weight_kg          DECIMAL(5,2),
    blood_type_id      TINYINT UNSIGNED NOT NULL,
    last_donation_date DATE NULL,
    is_eligible        BOOLEAN NOT NULL DEFAULT TRUE,
    deferral_reason    VARCHAR(200) NULL,
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_donor_bt FOREIGN KEY (blood_type_id)
        REFERENCES Blood_Types(blood_type_id),
    CONSTRAINT chk_weight CHECK (weight_kg IS NULL OR weight_kg >= 50.00),
    CONSTRAINT chk_national_id CHECK (national_id REGEXP '^[0-9]{14}$')
) ENGINE=InnoDB;

CREATE TABLE Hospitals (
    hospital_id INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    city        VARCHAR(50),
    phone       VARCHAR(15)
) ENGINE=InnoDB;

-- hospital_id اختياري: موظفي البنك = NULL
CREATE TABLE Users (
    user_id       INT AUTO_INCREMENT PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    username      VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role          ENUM('Admin','Lab_Tech','Bank_Staff') NOT NULL,
    hospital_id   INT NULL,
    CONSTRAINT fk_user_hosp FOREIGN KEY (hospital_id)
        REFERENCES Hospitals(hospital_id)
) ENGINE=InnoDB;

-- ============================================
-- 2) الجداول المرتبطة
-- ============================================

CREATE TABLE Blood_Compatibility (
    recipient_type_id TINYINT UNSIGNED NOT NULL,
    donor_type_id     TINYINT UNSIGNED NOT NULL,
    PRIMARY KEY (recipient_type_id, donor_type_id),
    CONSTRAINT fk_comp_rec FOREIGN KEY (recipient_type_id)
        REFERENCES Blood_Types(blood_type_id),
    CONSTRAINT fk_comp_don FOREIGN KEY (donor_type_id)
        REFERENCES Blood_Types(blood_type_id)
) ENGINE=InnoDB;

CREATE TABLE Blood_Units (
    unit_id          INT AUTO_INCREMENT PRIMARY KEY,
    donor_id         INT NOT NULL,
    blood_type_id    TINYINT UNSIGNED NOT NULL,
    collection_date  DATE NOT NULL,
    expiry_date      DATE NOT NULL,
    volume_ml        SMALLINT NOT NULL DEFAULT 450,
    storage_location VARCHAR(50) NULL,
    status           ENUM('Quarantine','Available','Reserved','Used','Expired','Rejected')
                     NOT NULL DEFAULT 'Quarantine',
    CONSTRAINT fk_unit_donor FOREIGN KEY (donor_id)
        REFERENCES Donors(donor_id),
    CONSTRAINT fk_unit_bt FOREIGN KEY (blood_type_id)
        REFERENCES Blood_Types(blood_type_id),
    CONSTRAINT chk_expiry CHECK (expiry_date > collection_date),
    INDEX idx_unit_status_expiry (status, expiry_date)
) ENGINE=InnoDB;

CREATE TABLE Blood_Tests (
    test_id         INT AUTO_INCREMENT PRIMARY KEY,
    unit_id         INT NOT NULL UNIQUE,
    hiv_result      ENUM('Pending','Negative','Positive') NOT NULL DEFAULT 'Pending',
    hbv_result      ENUM('Pending','Negative','Positive') NOT NULL DEFAULT 'Pending',
    hcv_result      ENUM('Pending','Negative','Positive') NOT NULL DEFAULT 'Pending',
    syphilis_result ENUM('Pending','Negative','Positive') NOT NULL DEFAULT 'Pending',
    test_date       DATE NULL,
    final_result    ENUM('Pending','Passed','Failed') NOT NULL DEFAULT 'Pending',
    tested_by       INT NULL,
    CONSTRAINT fk_test_unit FOREIGN KEY (unit_id)
        REFERENCES Blood_Units(unit_id) ON DELETE CASCADE,
    CONSTRAINT fk_test_user FOREIGN KEY (tested_by)
        REFERENCES Users(user_id)
) ENGINE=InnoDB;

CREATE TABLE Requests (
    request_id      INT AUTO_INCREMENT PRIMARY KEY,
    hospital_id     INT NOT NULL,
    blood_type_id   TINYINT UNSIGNED NOT NULL,
    units_needed    SMALLINT NOT NULL,
    units_fulfilled SMALLINT NOT NULL DEFAULT 0,
    request_date    DATE NOT NULL,
    urgency         ENUM('Normal','Urgent') NOT NULL DEFAULT 'Normal',
    status          ENUM('Pending','Partial','Fulfilled') NOT NULL DEFAULT 'Pending',
    CONSTRAINT fk_req_hosp FOREIGN KEY (hospital_id)
        REFERENCES Hospitals(hospital_id),
    CONSTRAINT fk_req_bt FOREIGN KEY (blood_type_id)
        REFERENCES Blood_Types(blood_type_id),
    CONSTRAINT chk_units CHECK (units_needed > 0 AND units_fulfilled <= units_needed)
) ENGINE=InnoDB;

CREATE TABLE Request_Units (
    request_id INT NOT NULL,
    unit_id    INT NOT NULL,
    issue_date DATE NOT NULL,
    issued_by  INT NULL,
    PRIMARY KEY (request_id, unit_id),
    CONSTRAINT fk_ru_req FOREIGN KEY (request_id)
        REFERENCES Requests(request_id),
    CONSTRAINT fk_ru_unit FOREIGN KEY (unit_id)
        REFERENCES Blood_Units(unit_id),
    CONSTRAINT fk_ru_user FOREIGN KEY (issued_by)
        REFERENCES Users(user_id)
) ENGINE=InnoDB;