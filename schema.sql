-- ===============================================================
-- 1. CLEANUP (Reset Database)
-- ===============================================================
DROP VIEW IF EXISTS net_emissions_per_org CASCADE;
DROP VIEW IF EXISTS total_emissions_per_org CASCADE;
DROP TABLE IF EXISTS offset_activity CASCADE;
DROP TABLE IF EXISTS emission_record CASCADE;
DROP TABLE IF EXISTS activity_gas CASCADE;
DROP TABLE IF EXISTS emission_factor CASCADE;
DROP TABLE IF EXISTS gas_type CASCADE;
DROP TABLE IF EXISTS vehicle_source CASCADE;
DROP TABLE IF EXISTS industrial_source CASCADE;
DROP TABLE IF EXISTS powerplant_source CASCADE;
DROP TABLE IF EXISTS emission_source CASCADE;
DROP TABLE IF EXISTS department CASCADE;
DROP TABLE IF EXISTS organization_location CASCADE;
DROP TABLE IF EXISTS activity CASCADE;
DROP TABLE IF EXISTS organization CASCADE;

-- ===============================================================
-- 2. SCHEMA CREATION
-- ===============================================================

-- ORGANIZATION
CREATE TABLE organization (
    org_id VARCHAR(50) PRIMARY KEY,
    org_name VARCHAR(100) NOT NULL,
    registration_no VARCHAR(50),
    industry_type VARCHAR(100)
);

-- ORGANIZATION LOCATION
CREATE TABLE organization_location (
    location VARCHAR(150),
    org_id VARCHAR(50),
    PRIMARY KEY (location, org_id),
    FOREIGN KEY (org_id) REFERENCES organization(org_id)
);

-- DEPARTMENT
CREATE TABLE department (
    dept_id VARCHAR(50) PRIMARY KEY,
    dept_name VARCHAR(100) NOT NULL,
    org_id VARCHAR(50),
    FOREIGN KEY (org_id) REFERENCES organization(org_id)
);

-- EMISSION SOURCE
CREATE TABLE emission_source (
    source_id VARCHAR(50) PRIMARY KEY,
    source_name VARCHAR(100) NOT NULL,
    source_type VARCHAR(50),
    dept_id VARCHAR(50),
    FOREIGN KEY (dept_id) REFERENCES department(dept_id)
);

-- VEHICLE SOURCE
CREATE TABLE vehicle_source (
    source_id VARCHAR(50) PRIMARY KEY,
    vehicle_type VARCHAR(50),
    fuel_type VARCHAR(50),
    FOREIGN KEY (source_id) REFERENCES emission_source(source_id)
);

-- INDUSTRIAL SOURCE
CREATE TABLE industrial_source (
    source_id VARCHAR(50) PRIMARY KEY,
    industrial_type VARCHAR(50),
    energy_consumption DOUBLE PRECISION,
    FOREIGN KEY (source_id) REFERENCES emission_source(source_id)
);

-- POWER PLANT SOURCE
CREATE TABLE powerplant_source (
    source_id VARCHAR(50) PRIMARY KEY,
    fuel_type VARCHAR(50),
    capacity_in_mw DOUBLE PRECISION,
    FOREIGN KEY (source_id) REFERENCES emission_source(source_id)
);

-- ACTIVITY
CREATE TABLE activity (
    activity_id VARCHAR(50) PRIMARY KEY,
    activity_name VARCHAR(100) NOT NULL,
    description TEXT
);

-- EMISSION FACTOR
CREATE TABLE emission_factor (
    factor_id VARCHAR(50) PRIMARY KEY,
    factor_value DOUBLE PRECISION,
    unit VARCHAR(50),
    activity_id VARCHAR(50),
    FOREIGN KEY (activity_id) REFERENCES activity(activity_id)
);

-- GAS TYPE
CREATE TABLE gas_type (
    gas_id VARCHAR(50) PRIMARY KEY,
    gas_name VARCHAR(50) NOT NULL,
    gwp DOUBLE PRECISION
);

-- ACTIVITY-GAS (Many-to-Many)
CREATE TABLE activity_gas (
    activity_id VARCHAR(50),
    gas_id VARCHAR(50),
    PRIMARY KEY (activity_id, gas_id),
    FOREIGN KEY (activity_id) REFERENCES activity(activity_id),
    FOREIGN KEY (gas_id) REFERENCES gas_type(gas_id)
);

-- EMISSION RECORD
CREATE TABLE emission_record (
    record_id VARCHAR(50) PRIMARY KEY,
    source_id VARCHAR(50),
    activity_id VARCHAR(50),
    date DATE,
    co2_emission_kg DOUBLE PRECISION,
    ch4_emission_kg DOUBLE PRECISION,
    n2o_emission_kg DOUBLE PRECISION,
    FOREIGN KEY (source_id) REFERENCES emission_source(source_id),
    FOREIGN KEY (activity_id) REFERENCES activity(activity_id)
);

-- OFFSET ACTIVITY
CREATE TABLE offset_activity (
    offset_id VARCHAR(50) PRIMARY KEY,
    org_id VARCHAR(50) REFERENCES organization(org_id),
    offset_type VARCHAR(100),
    description TEXT,
    date DATE,
    co2_offset_kg DOUBLE PRECISION,
    verified BOOLEAN DEFAULT FALSE
);

-- ===============================================================
-- 3. VIEWS
-- ===============================================================

-- VIEW: TOTAL EMISSIONS PER ORGANIZATION
CREATE VIEW total_emissions_per_org AS
SELECT 
    o.org_id,
    o.org_name,
    SUM(
        er.co2_emission_kg + 
        (er.ch4_emission_kg * 28) + 
        (er.n2o_emission_kg * 265)
    ) AS total_co2e_kg
FROM emission_record er
JOIN emission_source es ON er.source_id = es.source_id
JOIN department d ON es.dept_id = d.dept_id
JOIN organization o ON d.org_id = o.org_id
GROUP BY o.org_id, o.org_name;

-- VIEW: NET EMISSIONS (after offsets)
CREATE VIEW net_emissions_per_org AS
SELECT 
    te.org_id,
    te.org_name,
    te.total_co2e_kg,
    COALESCE(SUM(oa.co2_offset_kg), 0) AS total_offset_kg,
    (te.total_co2e_kg - COALESCE(SUM(oa.co2_offset_kg), 0)) AS net_co2e_kg
FROM total_emissions_per_org te
LEFT JOIN offset_activity oa ON te.org_id = oa.org_id
GROUP BY te.org_id, te.org_name, te.total_co2e_kg;

-- ===============================================================
-- 4. SUPABASE SECURITY
-- ===============================================================

ALTER TABLE organization ENABLE ROW LEVEL SECURITY;
ALTER TABLE emission_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE emission_source ENABLE ROW LEVEL SECURITY;
ALTER TABLE offset_activity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public Read Org" ON organization FOR SELECT USING (true);
CREATE POLICY "Public Read Source" ON emission_source FOR SELECT USING (true);
CREATE POLICY "Public Read Dept" ON department FOR SELECT USING (true);
CREATE POLICY "Public Access Records" ON emission_record FOR ALL USING (true);
CREATE POLICY "Public Access Offsets" ON offset_activity FOR ALL USING (true);

-- ===============================================================
-- 5. DATA SEEDING (STANDARDIZED)
-- ===============================================================

-- 5a. GAS TYPES
INSERT INTO gas_type (gas_id, gas_name, gwp) VALUES 
('G001', 'CO2', 1),
('G002', 'CH4', 28),
('G003', 'N2O', 265);

-- 5b. ACTIVITIES
INSERT INTO activity VALUES
('A001', 'Fuel Combustion', 'Combustion of fuels'),
('A002', 'Electricity Consumption', 'Use of grid electricity'),
('A003', 'Industrial Process', 'Manufacturing emissions'),
('A004', 'Transportation', 'Vehicle emissions');

-- 5c. ORGANIZATIONS (Standardized Format: ORG_XX_NN and REG-XX-NNN)

-- US Based Orgs (Renamed from ORG001 -> ORG_US_01)
INSERT INTO organization VALUES
('ORG_US_01', 'EcoTech Industries', 'REG-US-101', 'Manufacturing'),
('ORG_US_02', 'GreenWorld Energy', 'REG-US-102', 'Power Generation'),
('ORG_US_03', 'Urban Mobility Co.', 'REG-US-103', 'Transportation');

-- Delhi Based Orgs (Standardized)
INSERT INTO organization VALUES
('ORG_DL_01', 'Delhi Textiles Ltd', 'REG-DL-101', 'Manufacturing'),
('ORG_DL_02', 'Gurgaon AutoParts', 'REG-HR-102', 'Automotive'),
('ORG_DL_03', 'Noida Power Systems', 'REG-UP-103', 'Power Generation');


-- 5d. LOCATIONS
INSERT INTO organization_location VALUES
('New York', 'ORG_US_01'),
('Los Angeles', 'ORG_US_02'),
('Chicago', 'ORG_US_03'),
('Okhla Industrial Area', 'ORG_DL_01'),
('Manesar', 'ORG_DL_02'),
('Sector 62 Noida', 'ORG_DL_03');


-- 5e. DEPARTMENTS (Standardized IDs: DEP_XX_NN)
INSERT INTO department VALUES
-- US Departments
('DEP_US_01', 'Production', 'ORG_US_01'),
('DEP_US_02', 'Research and Development', 'ORG_US_01'),
('DEP_US_03', 'Operations', 'ORG_US_02'),
('DEP_US_04', 'Logistics', 'ORG_US_03'),
-- Delhi Departments
('DEP_DL_01', 'Production', 'ORG_DL_01'),
('DEP_DL_02', 'Assembly', 'ORG_DL_02'),
('DEP_DL_03', 'Thermal Unit', 'ORG_DL_03');


-- 5f. EMISSION SOURCES (Standardized IDs: SRC_XX_NN)
INSERT INTO emission_source VALUES
-- US Sources
('SRC_US_01', 'Diesel Generator', 'Industrial', 'DEP_US_01'),
('SRC_US_02', 'Main Office Grid Connection', 'PowerPlant', 'DEP_US_03'),
('SRC_US_03', 'Company Transport Fleet', 'Vehicle', 'DEP_US_04'),
-- Delhi Sources
('SRC_DL_01', 'Boiler Unit A', 'Industrial', 'DEP_DL_01'),
('SRC_DL_02', 'Fleet Trucks', 'Vehicle', 'DEP_DL_02'),
('SRC_DL_03', 'Backup Generator', 'PowerPlant', 'DEP_DL_03');

-- Source Details
INSERT INTO industrial_source VALUES ('SRC_US_01', 'Manufacturing', 4500.0); -- Linked to US source
INSERT INTO powerplant_source VALUES ('SRC_US_02', 'Grid Mix', 100.0);
INSERT INTO vehicle_source VALUES ('SRC_US_03', 'Truck Fleet', 'Diesel');

INSERT INTO industrial_source VALUES ('SRC_DL_01', 'Textile Processing', 5000.0); -- Linked to DL source
INSERT INTO vehicle_source VALUES ('SRC_DL_02', 'Heavy Truck', 'Diesel');
INSERT INTO powerplant_source VALUES ('SRC_DL_03', 'Diesel', 150.0);


-- 5g. EMISSION RECORDS
-- Note: Ensure foreign keys match new Source IDs
INSERT INTO emission_record VALUES
-- US Records
('REC_US_01', 'SRC_US_01', 'A001', '2025-01-15', 4520.75, 5.4, 0.2),
('REC_US_02', 'SRC_US_02', 'A002', '2025-02-10', 6820.10, 1.1, 0.05),
('REC_US_03', 'SRC_US_03', 'A004', '2025-02-20', 3290.55, 3.7, 0.1),
('REC_US_04', 'SRC_US_01', 'A003', '2025-03-12', 2100.90, 2.2, 0.05),
('REC_US_05', 'SRC_US_02', 'A002', '2025-03-22', 7050.35, 1.3, 0.06),

-- Delhi Records
('REC_DL_01', 'SRC_DL_01', 'A001', '2025-09-15', 500.0, 2.5, 0.1),
('REC_DL_02', 'SRC_DL_01', 'A001', '2025-10-15', 520.0, 2.6, 0.1),
('REC_DL_03', 'SRC_DL_02', 'A004', '2025-11-20', 300.0, 0.5, 0.02),
('REC_DL_04', 'SRC_DL_03', 'A001', '2025-12-05', 800.0, 1.2, 0.05);


-- 5h. OFFSETS
INSERT INTO offset_activity VALUES
('OFF_US_01', 'ORG_US_01', 'Tree Planting', 'Reforestation drive', '2025-02-10', 1250.0, TRUE),
('OFF_US_02', 'ORG_US_02', 'Solar Power Credit', 'Renewable project', '2025-03-15', 3200.0, TRUE),
('OFF_US_03', 'ORG_US_03', 'Community Composting', 'Methane reduction', '2025-04-05', 450.0, FALSE);