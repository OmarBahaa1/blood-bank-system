USE blood_bank;

INSERT INTO Blood_Types (type_name) VALUES
('A+'),('A-'),('B+'),('B-'),('AB+'),('AB-'),('O+'),('O-');

-- فترة الانتظار بين تبرعين (بالأيام)
INSERT INTO Settings (setting_key, setting_value, description) VALUES
('deferral_days_male',   90,  'Days between donations for males'),
('deferral_days_female', 120, 'Days between donations for females'),
('red_cells_shelf_life', 35,  'Shelf life of red cells in days');

-- التوافق: (المستقبل ← المتبرع)
INSERT INTO Blood_Compatibility (recipient_type_id, donor_type_id)
SELECT r.blood_type_id, d.blood_type_id
FROM Blood_Types r
JOIN Blood_Types d ON (
    (r.type_name = 'O-'  AND d.type_name IN ('O-')) OR
    (r.type_name = 'O+'  AND d.type_name IN ('O+','O-')) OR
    (r.type_name = 'A-'  AND d.type_name IN ('A-','O-')) OR
    (r.type_name = 'A+'  AND d.type_name IN ('A+','A-','O+','O-')) OR
    (r.type_name = 'B-'  AND d.type_name IN ('B-','O-')) OR
    (r.type_name = 'B+'  AND d.type_name IN ('B+','B-','O+','O-')) OR
    (r.type_name = 'AB-' AND d.type_name IN ('AB-','A-','B-','O-')) OR
    (r.type_name = 'AB+')
);