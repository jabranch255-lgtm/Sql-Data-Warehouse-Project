--Check for NULLS and Duplicates in the primary key 
SELECT 
cst_id,
COUNT(*)
FROM bronze.crm_cust_info
GROUP BY cst_id 
HAVING COUNT(*)>1 OR cst_id IS NULL


--to check the duplicates and get the latest one from them 
SELECT *,
ROW_NUMBER() OVER(PARTITION BY cst_id ORDER BY cst_create_date DESC) flag_last
FROM bronze.crm_cust_info
WHERE cst_id=29483
GO


--Check for unwanted 

SELECT
cst_firstname
FROM bronze.crm_cust_info
WHERE cst_firstname!=TRIM(cst_firstname)

--data strandarization and consistencay 
SELECT DISTINCT
cst_martial_status
FROM bronze.crm_cust_info

TRUNCATE TABLE silver.crm_cust_info


--check for nulls and unwanted numbers like negative


SELECT 
prd_cost
FROM bronze.crm_prd_info
WHERE prd_cost IS NULL OR prd_cost<0


SELECT DISTINCT
prd_line
FROM bronze.crm_prd_info

--check invalid dates
SELECT *
FROM bronze.crm_prd_info
WHERE prd_end_dt<prd_start_dt

--Check the invalid dates 
SELECT 
NULLIF(sls_order_dt,0) AS sls_order_dt
FROM bronze.crm_sales_details
WHERE sls_order_dt<=0 OR
LEN(sls_order_dt) !=8 OR
sls_order_dt>20501230
OR sls_order_dt < 19000530


--Check out of range dates
SELECT 
bdate 
FROM bronze.erp_cust_az12
WHERE bdate<'1924-01-01' OR bdate>GETDATE()

--Data standarixation and consistency check
SELECT 
bdate
FROM silver.erp_cust_az12
WHERE bdate>GETDATE()


--Idemtify the standarization and consistency 
SELECT  DISTINCT 
CASE WHEN UPPER(TRIM(cntry)) IN ('USA','UNITED STATES','US') THEN 'United States'
     WHEN UPPER(TRIM(cntry))='DE' THEN 'Germany'
     WHEN TriM(cntry)='' OR cntry IS NULL THEN 'n/a'
     ELSE cntry
END cntry
FROM bronze.erp_loc_a101

--Check the unwanted spaces 

SELECT *
FROM bronze.erp_px_cat_g1v2
WHERE cat!=TRIM(cat) OR subcat!=TRIM(subcat) OR maintenance!=TRIM(maintenance)
--DATA STANdARIZATION AND CONSISTANCY
SELECT DISTINCT
maintenance
FROM bronze.erp_px_cat_g1v2




-- Inserts deduplicated and cleaned customer data into the silver tier table
INSERT INTO silver.crm_cust_info (
    cst_id,
    cst_key,
    cst_firstname,
    cst_lastname,
    cst_gndr,
    cst_martial_status,
    cst_create_date
)
SELECT 
    cst_id,
    cst_key,
    TRIM(cst_firstname) cst_firstname,
    TRIM(cst_lastname) cst_lastname,
    -- Standardizes marital status codes to full text descriptions
    CASE 
        WHEN UPPER(TRIM(cst_martial_status)) = 'S' THEN 'Single'
        WHEN UPPER(TRIM(cst_martial_status)) = 'M' THEN 'Married'
        ELSE 'n/a' 
    END cst_gndr,
    -- Standardizes gender codes to full text descriptions
    CASE 
        WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
        WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
        ELSE 'n/a' 
    END cst_gndr,
    cst_create_date
FROM (
    -- Ranks records per customer ID to identify the most recent entry
    SELECT 
        *,
        ROW_NUMBER() OVER(PARTITION BY cst_id ORDER BY cst_create_date DESC) flag_last
    FROM bronze.crm_cust_info
) t 
-- Filters for the latest record per valid customer ID to remove duplicates
WHERE flag_last = 1 
  AND cst_id IS NOT NULL;
--check the data consistency between the sales qunatity and price 
--check for business logic 
--check for any nulls zeros
SELECT 
sls_quantity,
CASE WHEN sls_sales IS NULL OR sls_sales<=0 THEN ABS(sls_price)*sls_quantity
     ELSE sls_sales
     END sls_sales,
CASE WHEN sls_price<0 THEN ABS(sls_price)
     WHEN sls_price IS NULL OR sls_price = 0 THEN sls_sales/NULLIF(sls_quantity,0)
     ELSE sls_price 
     END sls_price
FROM bronze.crm_sales_details
WHERE sls_sales!=sls_quantity*sls_price OR
sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL OR
sls_sales <=0 OR sls_quantity <=0 OR sls_price <=0

