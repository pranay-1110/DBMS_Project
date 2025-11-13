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
-- 5. DATA SEEDING (EXPANDED & FINAL)
-- ===============================================================

-- 5a. GAS TYPES
INSERT INTO gas_type (gas_id, gas_name, gwp) VALUES 
('G001', 'CO2', 1),
('G002', 'CH4', 28),
('G003', 'N2O', 265),
('G004', 'SF6', 23500),
('G005', 'HFC-134a', 1300);

-- 5b. ACTIVITIES
INSERT INTO activity VALUES
('A001', 'Fuel Combustion', 'Combustion of fuels'),
('A002', 'Electricity Consumption', 'Use of grid electricity'),
('A003', 'Industrial Process', 'Manufacturing emissions'),
('A004', 'Transportation', 'Vehicle emissions'),
('A005', 'Refrigerant Leakage', 'Leakage of refrigerants (F-gases) from cooling units'),
('A006', 'Waste Combustion', 'Combustion of industrial or municipal waste'),
('A007', 'Cement Clinker Production', 'Emissions from clinker production process'),
('A008', 'Employee Commute', 'Transportation emissions from employee travel'),
('A009', 'Purchased Heat', 'Use of steam or heat from external sources');

-- 5c. ORGANIZATIONS
INSERT INTO organization VALUES
('ORG_US_01', 'EcoTech Industries', 'REG-US-101', 'Manufacturing'),
('ORG_US_02', 'GreenWorld Energy', 'REG-US-102', 'Power Generation'),
('ORG_US_03', 'Urban Mobility Co.', 'REG-US-103', 'Transportation'),
('ORG_US_04', 'PureAir Chemicals', 'REG-US-104', 'Chemical Manufacturing'),
('ORG_US_05', 'TransGlobal Freight', 'REG-US-105', 'Logistics & Shipping'),
('ORG_DL_01', 'Delhi Textiles Ltd', 'REG-DL-101', 'Manufacturing'),
('ORG_DL_02', 'Gurgaon AutoParts', 'REG-HR-102', 'Automotive'),
('ORG_DL_03', 'Noida Power Systems', 'REG-UP-103', 'Power Generation'),
('ORG_DL_04', 'EcoSteel India Pvt Ltd', 'REG-DL-104', 'Steel Production'),
('ORG_DL_05', 'Metro Electric Co.', 'REG-DL-105', 'Power Distribution');

-- 5d. LOCATIONS
INSERT INTO organization_location VALUES
('New York', 'ORG_US_01'),
('Los Angeles', 'ORG_US_02'),
('Chicago', 'ORG_US_03'),
('Houston, Texas', 'ORG_US_04'),
('San Francisco', 'ORG_US_05'),
('Okhla Industrial Area', 'ORG_DL_01'),
('Manesar', 'ORG_DL_02'),
('Sector 62 Noida', 'ORG_DL_03'),
('Faridabad', 'ORG_DL_04'),
('Rohini, Delhi', 'ORG_DL_05');

-- 5e. DEPARTMENTS
INSERT INTO department VALUES
('DEP_US_01', 'Production', 'ORG_US_01'),
('DEP_US_02', 'Research and Development', 'ORG_US_01'),
('DEP_US_03', 'Operations', 'ORG_US_02'),
('DEP_US_04', 'Logistics', 'ORG_US_03'),
('DEP_US_05', 'Chemical Synthesis', 'ORG_US_04'),
('DEP_US_06', 'Packaging', 'ORG_US_04'),
('DEP_US_07', 'Fleet Operations', 'ORG_US_05'),
('DEP_DL_01', 'Production', 'ORG_DL_01'),
('DEP_DL_02', 'Assembly', 'ORG_DL_02'),
('DEP_DL_03', 'Thermal Unit', 'ORG_DL_03'),
('DEP_DL_04', 'Smelting Unit', 'ORG_DL_04'),
('DEP_DL_05', 'Power Grid Ops', 'ORG_DL_05');

-- 5f. EMISSION SOURCES
INSERT INTO emission_source VALUES
-- US
('SRC_US_01', 'Diesel Generator', 'Industrial', 'DEP_US_01'),
('SRC_US_02', 'Main Office Grid Connection', 'PowerPlant', 'DEP_US_03'),
('SRC_US_03', 'Company Transport Fleet', 'Vehicle', 'DEP_US_04'),
('SRC_US_04', 'Reactor Chamber A', 'Industrial', 'DEP_US_05'),
('SRC_US_05', 'Cold Storage Unit', 'Industrial', 'DEP_US_06'),
('SRC_US_06', 'Cargo Ship Engine', 'Industrial', 'DEP_US_07'),
('SRC_US_07', 'Truck Fleet', 'Vehicle', 'DEP_US_07'),
-- Delhi
('SRC_DL_01', 'Boiler Unit A', 'Industrial', 'DEP_DL_01'),
('SRC_DL_02', 'Fleet Trucks', 'Vehicle', 'DEP_DL_02'),
('SRC_DL_03', 'Backup Generator', 'PowerPlant', 'DEP_DL_03'),
('SRC_DL_04', 'Blast Furnace', 'Industrial', 'DEP_DL_04'),
('SRC_DL_05', 'Cooling Tower', 'Industrial', 'DEP_DL_04'),
('SRC_DL_06', 'Grid Transformer Unit', 'PowerPlant', 'DEP_DL_05'),
('SRC_DL_07', 'Control Building DG Set', 'PowerPlant', 'DEP_DL_05');

-- 5g. SOURCE DETAILS
INSERT INTO industrial_source VALUES 
('SRC_US_01', 'Manufacturing', 4500.0),
('SRC_US_04', 'Chemical Processing', 6200.0),
('SRC_US_05', 'Cold Storage', 3000.0),
('SRC_US_06', 'Shipping', 10000.0),
('SRC_DL_01', 'Textile Processing', 5000.0),
('SRC_DL_04', 'Steel Melting', 9500.0),
('SRC_DL_05', 'Cooling Process', 4200.0);

INSERT INTO vehicle_source VALUES 
('SRC_US_03', 'Truck Fleet', 'Diesel'),
('SRC_US_07', 'Truck Fleet', 'Diesel'),
('SRC_DL_02', 'Heavy Truck', 'Diesel');

INSERT INTO powerplant_source VALUES
('SRC_US_02', 'Grid Mix', 100.0),
('SRC_DL_03', 'Diesel', 150.0),
('SRC_DL_06', 'Coal', 220.0),
('SRC_DL_07', 'Diesel', 50.0);

-- 5h. EMISSION FACTORS
INSERT INTO emission_factor VALUES
('F001', 2.68, 'kg CO2e per liter', 'A001'),
('F002', 0.85, 'kg CO2e per kWh', 'A002'),
('F003', 3.12, 'kg CO2e per ton', 'A003'),
('F004', 0.27, 'kg CO2e per km', 'A004'),
('F005', 4.50, 'kg CO2e per kg', 'A005'),
('F006', 1.15, 'kg CO2e per kg', 'A006'),
('F007', 0.90, 'kg CO2e per kWh', 'A009'),
('F008', 1.75, 'kg CO2e per commute', 'A008');

-- 5i. ACTIVITY–GAS MAPPING
INSERT INTO activity_gas VALUES
('A001', 'G001'), ('A001', 'G002'), ('A001', 'G003'),
('A002', 'G001'),
('A003', 'G001'), ('A003', 'G003'),
('A004', 'G001'), ('A004', 'G002'),
('A005', 'G004'),
('A006', 'G001'), ('A006', 'G002'),
('A007', 'G001'), ('A007', 'G003'),
('A008', 'G001'),
('A009', 'G001');

-- 5j. EMISSION RECORDS
INSERT INTO emission_record VALUES
-- US
('REC_US_01', 'SRC_US_01', 'A001', '2025-01-15', 4520.75, 5.4, 0.2),
('REC_US_02', 'SRC_US_02', 'A002', '2025-02-10', 6820.10, 1.1, 0.05),
('REC_US_03', 'SRC_US_03', 'A004', '2025-02-20', 3290.55, 3.7, 0.1),
('REC_US_04', 'SRC_US_01', 'A003', '2025-03-12', 2100.90, 2.2, 0.05),
('REC_US_05', 'SRC_US_02', 'A002', '2025-03-22', 7050.35, 1.3, 0.06),
('REC_US_19', 'SRC_US_04', 'A003', '2025-07-15', 5100.0, 3.1, 0.15),
('REC_US_20', 'SRC_US_05', 'A005', '2025-08-10', 700.0, 0.0, 0.0),
('REC_US_21', 'SRC_US_06', 'A006', '2025-08-30', 9200.0, 3.0, 0.25),
('REC_US_22', 'SRC_US_07', 'A004', '2025-09-12', 3500.0, 3.5, 0.10),

-- Delhi
('REC_DL_01', 'SRC_DL_01', 'A001', '2025-09-15', 500.0, 2.5, 0.1),
('REC_DL_02', 'SRC_DL_01', 'A001', '2025-10-15', 520.0, 2.6, 0.1),
('REC_DL_03', 'SRC_DL_02', 'A004', '2025-11-20', 300.0, 0.5, 0.02),
('REC_DL_04', 'SRC_DL_03', 'A001', '2025-12-05', 800.0, 1.2, 0.05),
('REC_DL_15', 'SRC_DL_04', 'A007', '2025-08-20', 8800.0, 1.8, 0.3),
('REC_DL_16', 'SRC_DL_05', 'A009', '2025-09-25', 4300.0, 0.0, 0.0),
('REC_DL_17', 'SRC_DL_06', 'A002', '2025-10-14', 7400.0, 1.1, 0.06),
('REC_DL_18', 'SRC_DL_07', 'A001', '2025-10-28', 3600.0, 0.9, 0.04);

-- 5k. OFFSET ACTIVITIES
INSERT INTO offset_activity VALUES
('OFF_US_01', 'ORG_US_01', 'Tree Planting', 'Reforestation drive', '2025-02-10', 1250.0, TRUE),
('OFF_US_02', 'ORG_US_02', 'Solar Power Credit', 'Renewable project', '2025-03-15', 3200.0, TRUE),
('OFF_US_03', 'ORG_US_03', 'Community Composting', 'Methane reduction', '2025-04-05', 450.0, FALSE),
('OFF_US_06', 'ORG_US_04', 'Carbon Capture System', 'Implemented solvent-based CO2 capture', '2025-08-18', 2100.0, TRUE),
('OFF_US_07', 'ORG_US_05', 'Biofuel Transition', 'Shifted 30% of fleet to biodiesel', '2025-09-22', 1800.0, TRUE),
('OFF_DL_04', 'ORG_DL_04', 'Afforestation Project', 'Sponsored forest regeneration program', '2025-10-12', 2700.0, TRUE),
('OFF_DL_05', 'ORG_DL_05', 'Smart Grid Optimization', 'Improved grid efficiency via AI', '2025-10-25', 1350.0, FALSE);
