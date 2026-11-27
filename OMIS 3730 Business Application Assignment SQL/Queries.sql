USE toronto_str;

-- Q1: What is the size and composition of Toronto's Airbnb rental market?

SELECT CASE WHEN minimum_nights < 28 THEN 'Short-term'
			WHEN minimum_nights = 28 THEN 'Exactly 28 nights'
            WHEN minimum_nights > 28 THEN 'Over 28 nights'
            ELSE 'Unknown'
            END AS rental_type,
		COUNT(*) AS total_listings,
        ROUND(COUNT(*) * 100.0 /
			(SELECT COUNT(*) FROM listing), 2) AS percentage
	FROM listing
    GROUP BY rental_type
    ORDER BY total_listings DESC;
    
-- Q2: What percentage of short-term rental listings display a registration number?

SELECT
	licence_status,
    COUNT(*) AS total_listings,
    ROUND(COUNT(*) * 100.0 /
		(SELECT COUNT(*)
        FROM listing
        WHERE minimum_nights < 28
        AND room_type <> 'Hotel room'), 2) AS percentage
FROM listing l
JOIN v_listing_compliance v
	ON l.listing_id = v.listing_id
WHERE l.minimum_nights < 28
AND l.room_type <> 'Hotel room'
GROUP BY licence_status
ORDER BY total_listings DESC;

-- Q3: How many entire-home short-term rentals exceed 180 estimated occupied nights, and do they display registration numbers?

SELECT
	v.licence_status,
    COUNT(*) AS total_listings,
    ROUND(AVG(l.estimated_occupancy_l365d), 2)
		AS avg_occupied_nights
FROM  listing l
JOIN v_listing_compliance v
	ON l.listing_id = v.listing_id
WHERE l.minimum_nights < 28
AND l.room_type = 'Entire home/apt'
AND l.estimated_occupancy_l365d > 180
GROUP BY v.licence_status
ORDER BY total_listings DESC;

-- Q4: Are Airbnb listings concentrated around the 28-night regulatory threshold?

SELECT
	minimum_nights,
    COUNT(*) AS total_listings
FROM listing
WHERE minimum_nights BETWEEN 21 AND 35
GROUP BY minimum_nights
ORDER BY minimum_nights;

-- Q5: How many hosts operate multiple listings, and how many of their listings qualify as short-term rentals?

-- Gives host names
SELECT
	h.host_id,
    h.host_name,
    COUNT(l.listing_id) AS total_listings,
    SUM(CASE
		WHEN l.minimum_nights < 28
        AND l.room_type <> 'Hotel room'
        THEN 1 ELSE 0
	END) AS short_term_listings
FROM host h
JOIN listing l
	ON h.host_id = l.host_id
GROUP BY h.host_id, h.host_name
HAVING COUNT(l.listing_id) > 1
ORDER BY short_term_listings DESC;

-- Gives total number of multiple listing hosts
SELECT COUNT(*) AS total_multi_listing_hosts
FROM host
WHERE host_id IN (
	SELECT host_id
    FROM listing
    GROUP BY host_id
    HAVING COUNT(*) > 1
);

-- Q6: Are multiple listings or different hosts using the same registration number?

SELECT 
	license,
    COUNT(listing_id) AS total_listings,
    COUNT(DISTINCT host_id) AS total_hosts,
    SUM(CASE
		WHEN room_type = 'Entire home/apt'
        THEN 1 ELSE 0
	END) AS entire_home_listings
FROM listing
WHERE minimum_nights < 28
AND room_type <> 'Hotel room'
AND license LIKE 'STR-%'
GROUP BY license
HAVING COUNT(listing_id) > 1
ORDER BY total_hosts DESC, total_listings DESC;

-- Q7: Which Toronto neighbourhoods have the highest proportion of short-term rentals without registration numbers?

SELECT
	n.neighbourhood_name,
	COUNT(l.listing_id) AS total_short_term_listings,
	SUM(CASE
		WHEN l.license IS NULL
		THEN 1 ELSE 0
	END) AS missing_registration,
	ROUND(
		SUM(CASE
			WHEN l.license IS NULL
			THEN 1 ELSE 0
		END) * 100.0 / COUNT(l.listing_id), 2
	) AS percentage_missing
FROM neighbourhood n
JOIN listing l
	ON n.neighbourhood_id = l.neighbourhood_id
WHERE l.minimum_nights < 28
AND l.room_type <> 'Hotel room'
GROUP BY n.neighbourhood_name
HAVING COUNT(l.listing_id) >= 10
ORDER BY percentage_missing DESC;

-- Q8: Are hosts without registration numbers still actively advertising short-term rental availability?

SELECT
	h.host_id,
    h.host_name,
    COUNT(DISTINCT l.listing_id)
		AS unregistered_listings,
	COUNT(c.cal_date) AS available_listing_days
FROM host h
JOIN listing l
	ON h.host_id = l.host_id
JOIN calendar_day c
	ON l.listing_id = c.listing_id
WHERE l.license IS NULL
AND l.room_type <> 'Hotel room'
AND c.minimum_nights < 28
AND c.available = 1
GROUP BY h.host_id, h.host_name
ORDER BY available_listing_days DESC;

-- Q9: How many short-term rental listings without registration numbers have received reviews in the past year?

SELECT 
	COUNT(DISTINCT l.listing_id)
		AS recently_reviewed_listings,
	COUNT(r.review_id) AS  total_recent_reviews
FROM listing l
JOIN review r
	ON l.listing_id = r.listing_id
WHERE l.minimum_nights < 28
AND l.room_type <> 'Hotel room'
AND l.license IS NULL
AND r.review_date BETWEEN  '2025-09-18'
						AND '2026-09-18';
                        
-- Q10: What percentage of short-term rental listings exhibit at least one indicator of potential non-compliance?

-- Identify hosts with multiple entire-home short-term rentals
CREATE TEMPORARY TABLE multi_home_hosts AS
SELECT host_id
FROM listing
WHERE minimum_nights < 28
AND room_type = 'Entire home/apt'
GROUP BY host_id
HAVING COUNT(listing_id) > 1;

-- Identify potential registration misuse
CREATE TEMPORARY TABLE shared_registration AS
SELECT license
FROM listing
WHERE minimum_nights < 28
AND room_type <> 'Hotel room'
AND license LIKE 'STR-%'
GROUP BY license
HAVING COUNT(DISTINCT host_id) > 1;

-- Calculate the overall potential non-compliance percentage
SELECT
	COUNT(l.listing_id) AS total_short_term_listings,
    
    SUM(CASE
		WHEN l.license IS NULL
        OR (l.room_type = 'Entire home/apt'
			AND l.estimated_occupancy_l365d > 180)
		OR (l.room_type = 'Entire home/apt'
			AND h.host_id IS NOT NULL)
		OR s.license IS NOT NULL
        THEN 1 ELSE 0
	END) AS potentially_non_compliant,
    
    ROUND(
		SUM(CASE
			WHEN l.license IS NULL
            OR (l.room_type = 'Entire home/apt'
				AND l.estimated_occupancy_l365d > 180)
			OR (l.room_type = 'Entire home/apt'
				AND h.host_id IS NOT NULL)
			OR s.license IS NOT NULL
			THEN 1 ELSE 0
		END) * 100.0 / COUNT(l.listing_id), 2
	) AS percentage_potentially_non_compliant
    
FROM listing l
LEFT JOIN multi_home_hosts h
	ON l.host_id = h.host_id
LEFT JOIN shared_registration s
	ON l.license = s.license
WHERE l.minimum_nights < 28
AND l.room_type <> 'Hotel room';

