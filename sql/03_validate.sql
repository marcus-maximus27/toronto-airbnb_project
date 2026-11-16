-- =====================================================================
-- OMIS 3730 | Toronto Airbnb project
-- Step 3: checks to run before anyone starts analysis.
-- Compare the first result with row_counts.txt from 01_clean.py.
-- =====================================================================
USE toronto_str;

-- 1. Row counts per table (should match row_counts.txt)
SELECT 'neighbourhood' AS tbl, COUNT(*) AS row_count FROM neighbourhood
UNION ALL SELECT 'host',            COUNT(*) FROM host
UNION ALL SELECT 'listing',         COUNT(*) FROM listing
UNION ALL SELECT 'calendar_day',    COUNT(*) FROM calendar_day
UNION ALL SELECT 'review',          COUNT(*) FROM review
UNION ALL SELECT 'amenity',         COUNT(*) FROM amenity
UNION ALL SELECT 'listing_amenity', COUNT(*) FROM listing_amenity;

-- 2. Every listing has a neighbourhood (expect 0)
SELECT COUNT(*) AS listings_without_neighbourhood
FROM listing WHERE neighbourhood_id IS NULL;

-- 3. Calendar covers the expected window (expect about 90 days from 2026-09-16)
SELECT MIN(cal_date) AS first_day, MAX(cal_date) AS last_day,
       COUNT(DISTINCT cal_date) AS days
FROM calendar_day;

-- 4. Null rates on fields the analysis depends on
SELECT ROUND(100 * AVG(price IS NULL), 1)                     AS pct_price_null,
       ROUND(100 * AVG(license IS NULL), 1)                   AS pct_license_null,
       ROUND(100 * AVG(review_scores_rating IS NULL), 1)      AS pct_rating_null,
       ROUND(100 * AVG(estimated_occupancy_l365d IS NULL), 1) AS pct_occupancy_null
FROM listing;

-- 5. Licence text patterns: check the CASE logic in v_listing_compliance
SELECT LEFT(license, 8) AS licence_prefix, COUNT(*) AS listings
FROM listing
GROUP BY LEFT(license, 8)
ORDER BY listings DESC
LIMIT 15;

-- 6. Sanity check on the view
SELECT room_type, licence_status, COUNT(*) AS listings,
       SUM(flag_over_180) AS over_180_nights
FROM v_listing_compliance
GROUP BY room_type, licence_status
ORDER BY room_type, listings DESC;
