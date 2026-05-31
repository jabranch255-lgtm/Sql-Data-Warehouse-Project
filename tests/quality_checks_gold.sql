/*
===============================================================================
Data Quality (DQ) Scripts: Gold Layer Validation
===============================================================================
Script Purpose:
    This script performs various data quality, integrity, and alignment checks
    on the Gold layer views against their underlying Silver source tables.

Usage:
    - Run these queries to identify duplicates, orphaned keys, or null values.
    - Zero rows returned from validation queries indicates clean data.
===============================================================================
*/

-- =============================================================================
-- Check 1: Duplicate Customers in Silver Source
-- Description: Verifies if combining CRM and ERP customer data creates duplicates.
-- =============================================================================
SELECT 
    cst_id,
    COUNT(*) AS duplicate_count
FROM (
    SELECT 
        ci.cst_id,
        ci.cst_key,
        ci.cst_firstname,
        ci.cst_lastname,
        ci.cst_martial_status,
        ci.cst_gndr,
        ci.cst_create_date,
        ca.bdate,
        ca.gen,
        la.cntry
    FROM silver.crm_cust_info ci
    LEFT JOIN silver.erp_cust_az12 ca ON ci.cst_key = ca.cid
    LEFT JOIN silver.erp_loc_a101 la  ON ci.cst_key = la.cid
) t
GROUP BY cst_id
HAVING COUNT(*) > 1;

-- =============================================================================
-- Check 2: Null Values in Final Customer Gender
-- Description: Ensures the fallback CASE statement leaves no NULL values in 'gender'.
-- =============================================================================
SELECT * 
FROM gold.dim_customers
WHERE gender IS NULL;

-- =============================================================================
-- Check 3: Duplicate Products in Silver Source
-- Description: Checks for active product duplicates after filtering historical data.
-- =============================================================================
SELECT 
    prd_key,
    COUNT(*) AS duplicate_count
FROM (
    SELECT 
        pa.prd_id,
        pa.cat_id,
        pa.prd_key,
        pa.prd_nm,
        pa.prd_cost,
        pa.prd_line,
        pa.prd_start_dt,
        pa.prd_end_dt,
        ea.cat,
        ea.subcat,
        ea.maintenance
    FROM silver.crm_prd_info pa
    LEFT JOIN silver.erp_px_cat_g1v2 ea ON pa.cat_id = ea.id
    WHERE pa.prd_end_dt IS NULL -- Focus only on active products
) t
GROUP BY prd_key
HAVING COUNT(*) > 1;

-- =============================================================================
-- Check 4: Duplicate Product Numbers in Gold Dimension
-- Description: Ensures the final 'gold.dim_products' view has unique natural keys.
-- =============================================================================
SELECT 
    product_number,
    COUNT(*) AS duplicate_count
FROM gold.dim_products
GROUP BY product_number
HAVING COUNT(*) > 1;

-- =============================================================================
-- Check 5: Basic Fact Table Preview
-- Description: General inspection of data rows inside the sales fact view.
-- =============================================================================
SELECT TOP 100 * -- Added TOP 100 to safeguard performance on large tables
FROM gold.fact_sales;

-- =============================================================================
-- Check 6: Referential Integrity / Orphaned Product Keys
-- Description: Identifies sales records pointing to non-existent products (Unmatched keys).
-- =============================================================================
SELECT f.*
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c ON f.customer_key = c.customer_key
LEFT JOIN gold.dim_products p  ON f.product_key = p.product_key
WHERE f.product_key IS NULL; -- Catches missing matches in the product dimension

-- =============================================================================
-- Check 7: Gender Transformation Logic Review
-- Description: Validates the fallback conditional logic between CRM and ERP sources.
-- =============================================================================
SELECT DISTINCT
    ci.cst_gndr AS crm_gender,
    ca.gen AS erp_gender,
    CASE 
        WHEN ci.cst_gndr != 'n/a' THEN ci.cst_gndr
        ELSE COALESCE(ca.gen, 'n/a')
    END AS consolidated_gender
FROM silver.crm_cust_info ci
LEFT JOIN silver.erp_cust_az12 ca ON ci.cst_key = ca.cid;
