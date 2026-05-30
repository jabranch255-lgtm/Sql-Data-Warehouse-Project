/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to 
    populate the 'silver' schema tables from the 'bronze' schema.
	Actions Performed:
		- Truncates Silver tables.
		- Inserts transformed and cleansed data from Bronze into Silver tables.
		
Parameters:
    None. 
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC Silver.load_silver;
===============================================================================
*/


CREATE OR ALTER PROCEDURE Silver.load_silver AS 
BEGIN
    DECLARE @start_time DATETIME,@end_time DATETIME,@batch_start_time DATETIME,@batch_end_time DATETIME
    BEGIN TRY

       SET @batch_start_time=GETDATE();


       PRINT'=================================================='
       PRINT'Loading Silver Layer'
       PRINT'=================================================='


       PRINT'--------------------------------------------------'
       PRINT'Loading CRM Tables'
       PRINT'--------------------------------------------------'

       SET @start_time=GETDATE();
 -- Inserts deduplicated and cleaned customer data into the silver tier table
       PRINT'>>Truncating table:silver.crm_cust_info'
       TRUNCATE TABLE silver.crm_cust_info
       PRINT'Inserting into table:silver.crm_cust_info'
       INSERT INTO silver.crm_cust_info (
             cst_id,
             cst_key,
             cst_firstname,
             cst_lastname,
             cst_martial_status,
             cst_gndr,
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
             END cst_martial_status,
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
              WHERE flag_last = 1  AND cst_id IS NOT NULL ;
      SET @end_time=GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> ----------------------------';


     SET @start_time=GETDATE();
-- Inserts cleaned and historically tracked product data into the silver tier table
     PRINT'>>Truncating table:silver.crm_prd_info'
     TRUNCATE TABLE silver.crm_prd_info
     PRINT'Inserting into table:silver.crm_prd_info'
     INSERT INTO silver.crm_prd_info (
          prd_id,
          cat_id,
          prd_key,
          prd_nm,
         prd_cost,
         prd_line,
         prd_start_dt,
         prd_end_dt
         )
    SELECT 
         prd_id,
    -- Extracts and formats the category ID prefix from the original product key
         REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,
    -- Extracts the core product key by removing the category prefix
         SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,
         prd_nm,
    -- Handles missing cost data by defaulting null values to zero
         COALESCE(prd_cost, 0) prd_cost,
    -- Standardizes abbreviated product line codes into full text categories
         CASE 
             WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
             WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
             WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other sales'
             WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
             ELSE 'n/a'
         END prd_line,
         CAST(prd_start_dt AS DATE) prd_start_dt,
    -- Dynamically derives the end date based on the day before the next start date
         CAST(LEAD(prd_start_dt) OVER(PARTITION BY prd_key ORDER BY prd_start_dt) - 1 AS DATE) AS prd_end_dt
     FROM bronze.crm_prd_info;
     SET @end_time=GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -----------------------';

     SET @start_time=GETDATE();
-- Inserts validated sales transaction metrics into the silver tier storage
     PRINT'>>Truncating table:silver.crm_sales_details'
     TRUNCATE TABLE silver.crm_sales_details
     PRINT'Inserting into table:silver.crm_sales_details'
     INSERT INTO silver.crm_sales_details (
           sls_ord_num,
           sls_prd_key,
           sls_cust_id,
           sls_order_dt,
           sls_ship_dt,
           sls_due_dt,
           sls_sales,
           sls_quantity,
           sls_price
            )
    SELECT 
           sls_ord_num,
           sls_prd_key,
           sls_cust_id,
    -- Validates and converts integer order date records into date types
          CASE 
              WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL
              ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
          END sls_order_dt,
    -- Validates and converts integer shipping date records into date types
          CASE 
             WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL
             ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
          END sls_ship_dt,
    -- Validates and converts integer due date records into date types
          CASE 
              WHEN sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL
              ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
          END sls_due_dt,
    -- Corrects invalid revenue amounts using pricing and volume dimensions
          CASE 
             WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price) THEN ABS(sls_price) * sls_quantity
             ELSE sls_sales
          END sls_sales,
    sls_quantity,
    -- Rebuilds unit prices using total sales values and zero-safe volumes
          CASE 
             WHEN sls_price IS NULL OR sls_price <= 0 THEN sls_sales / NULLIF(sls_quantity, 0)
             ELSE sls_price
          END sls_price 
    FROM bronze.crm_sales_details;
    SET @end_time=GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> ----------------------------';



    PRINT'--------------------------------------------------'
    PRINT'Loading ERP Tables'
    PRINT'--------------------------------------------------'

    SET @start_time=GETDATE();
-- Inserts cleaned and standardized customer profile data into the silver tier table
    PRINT'>>Truncating table:silver.erp_cust_az12'
    TRUNCATE TABLE silver.erp_cust_az12
    PRINT'Inserting into table:silver.erp_cust_az12'
    INSERT INTO silver.erp_cust_az12 (
         cid,
         bdate,
         gen
         )
    SELECT 
    -- Strips the 'NAS' prefix from the customer ID if present
         CASE 
             WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
             ELSE cid
         END cid,
    -- Filters out future birth dates by setting them to NULL
         CASE 
            WHEN bdate > GETDATE() THEN NULL
            ELSE bdate
         END bdate,
    -- Standardizes gender variations into uniform text classifications
         CASE 
            WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
            WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
            ELSE 'n/a'
         END gen
    FROM bronze.erp_cust_az12;
    SET @end_time=GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> ----------------------------------';






    SET @start_time=GETDATE();
-- Inserts cleaned and standardized customer location coordinates into the silver tier table
    PRINT'>>Truncating table:silver.erp_loc_a101 '
    TRUNCATE TABLE silver.erp_loc_a101 
    PRINT'Inserting into table:silver.erp_loc_a101 '
    INSERT INTO silver.erp_loc_a101 (
        cid,
        cntry
         )
    SELECT 
    -- Removes hyphens from the customer identifier to normalize format
        REPLACE(cid, '-', '') cid,
    -- Standardizes country naming variations into uniform classifications
        CASE 
            WHEN UPPER(TRIM(cntry)) IN ('USA', 'UNITED STATES', 'US') THEN 'United States'
            WHEN UPPER(TRIM(cntry)) = 'DE' THEN 'Germany'
            WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
            ELSE cntry
        END cntry
     FROM bronze.erp_loc_a101;
     SET @end_time=GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> ------------------------------------------';


     SET @start_time=GETDATE();
-- Inserts direct reference category mapping attributes into the silver tier table
     PRINT'>>Truncating table:silver.erp_px_cat_g1v2 '
     TRUNCATE TABLE silver.erp_px_cat_g1v2 
     PRINT'Inserting into table:silver.erp_px_cat_g1v2 '
     INSERT INTO silver.erp_px_cat_g1v2 (
         id,
         cat,
         subcat,
         maintenance
           )
     SELECT 
         id,
         cat,
         subcat,
         maintenance
     FROM bronze.erp_px_cat_g1v2;
     SET @end_time=GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> ----------------------------------';
     SET @batch_end_time=GETDATE();
     PRINT'=================================================='
     PRINT'Loading Silver Layer is done';
     PRINT'==================================================';
     PRINT' Total Load Duration:' + CAST(DATEDIFF(SECOND,@batch_start_time,@batch_end_time) AS NVARCHAR) +'Seconds';
 END TRY

 BEGIN CATCH
     PRINT'==================================================';
     PRINT'Error Occured during loading the Silver layer';
     PRINT'Error Message' +  ERROR_MESSAGE();
     PRINT'Error Number' + CAST(ERROR_NUMBER() AS NVARCHAR);
     PRINT'Error State' +  CASt(ERROR_STATE() AS NVARCHAR);
     PRINT'==================================================';
 END CATCH



   END


  
