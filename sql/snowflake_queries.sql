-- ============================================================
-- Pharma Compliance Spend Analytics — Snowflake Implementation
-- Author: Shrikant Sharma
-- 
-- This script reproduces the key analytical findings from the
-- Pandas EDA in SQL on Snowflake. Source data: CMS Open Payments
-- 2024 General Payments, 10% physician sample (988,821 rows).
-- 
-- Database: PHARMA_COMPLIANCE
-- Schema:   CMS
-- Table:    PAYMENTS_SAMPLE
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================
-- SETUP
-- ============================================================

CREATE DATABASE IF NOT EXISTS PHARMA_COMPLIANCE
    COMMENT = 'Portfolio project: CMS Open Payments anomaly detection (rules + ML)';

CREATE SCHEMA IF NOT EXISTS PHARMA_COMPLIANCE.CMS
    COMMENT = '2024 General Payments — 10% physician sample (989K transactions)';

USE DATABASE PHARMA_COMPLIANCE;
USE SCHEMA CMS;

-- Table PAYMENTS_SAMPLE was loaded via the Snowsight wizard from
-- payments_sampled.csv (180MB, 988,821 rows). The wizard auto-named
-- columns C1-C10; the following statements rename them to canonical
-- CMS column names.

-- ALTER TABLE PAYMENTS_SAMPLE RENAME COLUMN C1 TO COVERED_RECIPIENT_TYPE;
-- ALTER TABLE PAYMENTS_SAMPLE RENAME COLUMN C2 TO COVERED_RECIPIENT_NPI;
-- ALTER TABLE PAYMENTS_SAMPLE RENAME COLUMN C3 TO COVERED_RECIPIENT_FIRST_NAME;
-- ALTER TABLE PAYMENTS_SAMPLE RENAME COLUMN C4 TO COVERED_RECIPIENT_LAST_NAME;
-- ALTER TABLE PAYMENTS_SAMPLE RENAME COLUMN C5 TO RECIPIENT_STATE;
-- ALTER TABLE PAYMENTS_SAMPLE RENAME COLUMN C6 TO COVERED_RECIPIENT_SPECIALTY_1;
-- ALTER TABLE PAYMENTS_SAMPLE RENAME COLUMN C7 TO MANUFACTURER_NAME;
-- ALTER TABLE PAYMENTS_SAMPLE RENAME COLUMN C8 TO TOTAL_AMOUNT_USD;
-- ALTER TABLE PAYMENTS_SAMPLE RENAME COLUMN C9 TO DATE_OF_PAYMENT;
-- ALTER TABLE PAYMENTS_SAMPLE RENAME COLUMN C10 TO NATURE_OF_PAYMENT;

-- ============================================================
-- Q1: Top 10 manufacturers by total payments
-- Finding: Stryker leads despite far fewer transactions than AbbVie —
-- the device-royalty vs pharma-marketing structural pattern.
-- ============================================================
SELECT
    MANUFACTURER_NAME,
    COUNT(*) AS payment_count,
    ROUND(SUM(TOTAL_AMOUNT_USD), 0) AS total_paid_usd,
    ROUND(AVG(TOTAL_AMOUNT_USD), 2) AS avg_payment_usd,
    COUNT(DISTINCT COVERED_RECIPIENT_NPI) AS unique_physicians_paid
FROM PAYMENTS_SAMPLE
GROUP BY MANUFACTURER_NAME
ORDER BY total_paid_usd DESC
LIMIT 10;

-- ============================================================
-- Q2: Top 10 specialties by total payments
-- Finding: Orthopaedic Surgery (8,901 physicians) outranks Internal
-- Medicine (41,349 physicians) in total dollars — concentration in
-- a much smaller specialty.
-- ============================================================
SELECT
    COVERED_RECIPIENT_SPECIALTY_1 AS specialty,
    COUNT(DISTINCT COVERED_RECIPIENT_NPI) AS physician_count,
    COUNT(*) AS payment_count,
    ROUND(SUM(TOTAL_AMOUNT_USD), 0) AS total_paid_usd,
    ROUND(SUM(TOTAL_AMOUNT_USD) / COUNT(DISTINCT COVERED_RECIPIENT_NPI), 0) AS avg_per_physician_usd
FROM PAYMENTS_SAMPLE
GROUP BY COVERED_RECIPIENT_SPECIALTY_1
ORDER BY total_paid_usd DESC
LIMIT 10;

-- ============================================================
-- Q3: HEADLINE FINDING — Orthopaedic surgery's manufacturer capture
-- Top 4 manufacturers take 59.7% of all orthopaedic surgery payments.
-- Top 5 take 67.7%.  This is the structural-concentration finding.
-- ============================================================
SELECT
    MANUFACTURER_NAME,
    COUNT(DISTINCT COVERED_RECIPIENT_NPI) AS physician_count,
    ROUND(SUM(TOTAL_AMOUNT_USD), 0) AS total_paid_usd,
    ROUND(100.0 * SUM(TOTAL_AMOUNT_USD) /
          SUM(SUM(TOTAL_AMOUNT_USD)) OVER (), 1) AS pct_of_orthopaedic_spend
FROM PAYMENTS_SAMPLE
WHERE COVERED_RECIPIENT_SPECIALTY_1 LIKE '%Orthopaedic Surgery%'
GROUP BY MANUFACTURER_NAME
ORDER BY total_paid_usd DESC
LIMIT 10;

-- ============================================================
-- Q4: Top 10 highest-paid individual physicians
-- These match the BOTH-flagged HCPs from the Isolation Forest layer.
-- ============================================================
SELECT
    COVERED_RECIPIENT_NPI AS npi,
    COVERED_RECIPIENT_FIRST_NAME AS first_name,
    COVERED_RECIPIENT_LAST_NAME AS last_name,
    COVERED_RECIPIENT_SPECIALTY_1 AS specialty,
    RECIPIENT_STATE AS state,
    COUNT(*) AS payment_count,
    ROUND(SUM(TOTAL_AMOUNT_USD), 0) AS total_paid_usd,
    COUNT(DISTINCT MANUFACTURER_NAME) AS unique_manufacturers
FROM PAYMENTS_SAMPLE
GROUP BY 1, 2, 3, 4, 5
ORDER BY total_paid_usd DESC
LIMIT 10;

-- ============================================================
-- Q5: Payment size distribution (the long-tail finding)
-- Mean = $220.87 vs Median = $21.26 → mean is ~10x median →
-- extreme right-skew → justification for IQR-based detection
-- alongside z-score in the rule system.
-- ============================================================
SELECT
    COUNT(*) AS total_payments,
    ROUND(AVG(TOTAL_AMOUNT_USD), 2) AS mean_payment_usd,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY TOTAL_AMOUNT_USD), 2) AS median,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY TOTAL_AMOUNT_USD), 2) AS p75,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY TOTAL_AMOUNT_USD), 2) AS p90,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY TOTAL_AMOUNT_USD), 2) AS p95,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY TOTAL_AMOUNT_USD), 2) AS p99,
    ROUND(MAX(TOTAL_AMOUNT_USD), 2) AS max_payment_usd
FROM PAYMENTS_SAMPLE;