-- =====================================================================
-- OMIS 3730 | Toronto Airbnb project
-- Step 2: build the MySQL database from the cleaned files (MySQL 8.0+)
--
-- Before running:
--   1. Run 01_clean.py and put the clean files in one folder.
--   2. Replace /path/to/clean/ below with that folder (use forward slashes,
--      e.g. C:/Users/you/airbnb/clean/ on Windows).
--   3. Turn on local file loading:
--        SET GLOBAL local_infile = 1;
--      In MySQL Workbench: edit the connection > Advanced tab >
--      Others box > add  OPT_LOCAL_INFILE=1  then reconnect.
-- =====================================================================

DROP DATABASE IF EXISTS toronto_str;
CREATE DATABASE toronto_str CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE toronto_str;

-- ---------------------------------------------------------------------
-- A. Staging tables (raw shape of the cleaned files)
-- ---------------------------------------------------------------------
CREATE TABLE stg_listing (
    listing_id                                   BIGINT,
    last_scraped                                 DATE,
    name                                         VARCHAR(500),
    host_id                                      BIGINT,
    host_name                                    VARCHAR(255),
    host_since                                   DATE,
    host_response_rate                           TINYINT,
    host_is_superhost                            TINYINT,
    host_identity_verified                       TINYINT,
    host_total_listings_count                    INT,
    neighbourhood_cleansed                       VARCHAR(100),
    latitude                                     DECIMAL(9,6),
    longitude                                    DECIMAL(9,6),
    property_type                                VARCHAR(100),
    room_type                                    VARCHAR(50),
    accommodates                                 INT,
    bedrooms                                     INT,
    beds                                         INT,
    price                                        DECIMAL(10,2),
    minimum_nights                               INT,
    maximum_nights                               INT,
    availability_365                             INT,
    number_of_reviews                            INT,
    number_of_reviews_ltm                        INT,
    first_review                                 DATE,
    last_review                                  DATE,
    review_scores_rating                         DECIMAL(3,2),
    license                                      VARCHAR(255),
    instant_bookable                             TINYINT,
    calculated_host_listings_count               INT,
    calculated_host_listings_count_entire_homes  INT,
    calculated_host_listings_count_private_rooms INT,
    estimated_occupancy_l365d                    INT,
    estimated_revenue_l365d                      DECIMAL(12,2)
);

CREATE TABLE stg_listing_amenity (
    listing_id   BIGINT,
    amenity_name VARCHAR(255)
);

LOAD DATA LOCAL INFILE '/path/to/clean/listings_clean.csv'
INTO TABLE stg_listing CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE '/path/to/clean/listing_amenity_raw.csv'
INTO TABLE stg_listing_amenity CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 LINES;

-- ---------------------------------------------------------------------
-- B. Final tables
-- ---------------------------------------------------------------------
CREATE TABLE neighbourhood (
    neighbourhood_id   INT AUTO_INCREMENT PRIMARY KEY,
    neighbourhood_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE host (
    host_id                   BIGINT PRIMARY KEY,
    host_name                 VARCHAR(255),
    host_since                DATE,
    host_response_rate        TINYINT,
    is_superhost              TINYINT,
    identity_verified         TINYINT,
    total_listings_count      INT,        -- all listings, any city
    toronto_listings          INT,        -- calculated_host_listings_count
    toronto_entire_homes      INT,
    toronto_private_rooms     INT
);

CREATE TABLE listing (
    listing_id                BIGINT PRIMARY KEY,
    host_id                   BIGINT NOT NULL,
    neighbourhood_id          INT,
    name                      VARCHAR(500),
    latitude                  DECIMAL(9,6),
    longitude                 DECIMAL(9,6),
    property_type             VARCHAR(100),
    room_type                 VARCHAR(50),
    accommodates              INT,
    bedrooms                  INT,
    beds                      INT,
    price                     DECIMAL(10,2),
    minimum_nights            INT,
    maximum_nights            INT,
    availability_365          INT,
    number_of_reviews         INT,
    number_of_reviews_ltm     INT,
    first_review              DATE,
    last_review               DATE,
    review_scores_rating      DECIMAL(3,2),
    license                   VARCHAR(255),
    instant_bookable          TINYINT,
    estimated_occupancy_l365d INT,
    estimated_revenue_l365d   DECIMAL(12,2),
    last_scraped              DATE,
    CONSTRAINT fk_listing_host FOREIGN KEY (host_id) REFERENCES host(host_id),
    CONSTRAINT fk_listing_nbhd FOREIGN KEY (neighbourhood_id)
        REFERENCES neighbourhood(neighbourhood_id),
    INDEX idx_listing_room (room_type),
    INDEX idx_listing_nbhd (neighbourhood_id)
);

CREATE TABLE calendar_day (
    listing_id     BIGINT NOT NULL,
    cal_date       DATE   NOT NULL,
    available      TINYINT,
    price          DECIMAL(10,2),
    minimum_nights INT,
    PRIMARY KEY (listing_id, cal_date),
    CONSTRAINT fk_cal_listing FOREIGN KEY (listing_id) REFERENCES listing(listing_id)
);

CREATE TABLE review (
    review_id   BIGINT PRIMARY KEY,
    listing_id  BIGINT NOT NULL,
    review_date DATE,
    reviewer_id BIGINT,
    CONSTRAINT fk_review_listing FOREIGN KEY (listing_id) REFERENCES listing(listing_id),
    INDEX idx_review_listing_date (listing_id, review_date)
);

CREATE TABLE amenity (
    amenity_id   INT AUTO_INCREMENT PRIMARY KEY,
    amenity_name VARCHAR(255) NOT NULL UNIQUE
);

CREATE TABLE listing_amenity (
    listing_id BIGINT NOT NULL,
    amenity_id INT    NOT NULL,
    PRIMARY KEY (listing_id, amenity_id),
    CONSTRAINT fk_la_listing FOREIGN KEY (listing_id) REFERENCES listing(listing_id),
    CONSTRAINT fk_la_amenity FOREIGN KEY (amenity_id) REFERENCES amenity(amenity_id)
);

-- ---------------------------------------------------------------------
-- C. Split staging into final tables (INSERT ... SELECT)
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE '/path/to/clean/neighbourhoods.csv'
INTO TABLE neighbourhood CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 LINES
(neighbourhood_name);

-- Catch any neighbourhood that appears in listings but not in the lookup file
INSERT IGNORE INTO neighbourhood (neighbourhood_name)
SELECT DISTINCT neighbourhood_cleansed
FROM stg_listing
WHERE neighbourhood_cleansed IS NOT NULL;

-- One row per host (host fields repeat on every listing row)
INSERT INTO host
SELECT host_id,
       MAX(host_name), MAX(host_since), MAX(host_response_rate),
       MAX(host_is_superhost), MAX(host_identity_verified),
       MAX(host_total_listings_count), MAX(calculated_host_listings_count),
       MAX(calculated_host_listings_count_entire_homes),
       MAX(calculated_host_listings_count_private_rooms)
FROM stg_listing
WHERE host_id IS NOT NULL
GROUP BY host_id;

INSERT INTO listing
SELECT s.listing_id, s.host_id, n.neighbourhood_id, s.name, s.latitude, s.longitude,
       s.property_type, s.room_type, s.accommodates, s.bedrooms, s.beds, s.price,
       s.minimum_nights, s.maximum_nights, s.availability_365, s.number_of_reviews,
       s.number_of_reviews_ltm, s.first_review, s.last_review, s.review_scores_rating,
       NULLIF(TRIM(s.license), ''), s.instant_bookable, s.estimated_occupancy_l365d,
       s.estimated_revenue_l365d, s.last_scraped
FROM stg_listing s
LEFT JOIN neighbourhood n ON n.neighbourhood_name = s.neighbourhood_cleansed
WHERE s.host_id IS NOT NULL;

INSERT INTO amenity (amenity_name)
SELECT DISTINCT amenity_name FROM stg_listing_amenity;

INSERT IGNORE INTO listing_amenity (listing_id, amenity_id)
SELECT sa.listing_id, a.amenity_id
FROM stg_listing_amenity sa
JOIN amenity a   ON a.amenity_name = sa.amenity_name
JOIN listing l   ON l.listing_id   = sa.listing_id;

-- Large tables load straight in (already narrow and filtered by 01_clean.py)
LOAD DATA LOCAL INFILE '/path/to/clean/calendar_clean.csv'
INTO TABLE calendar_day CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE '/path/to/clean/reviews_clean.csv'
INTO TABLE review CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 LINES;

-- ---------------------------------------------------------------------
-- D. Analysis view: one row per listing with the bylaw tests pre-built
--    Rules tested: entire-home rentals capped at 180 nights/year;
--    one principal residence per host.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_listing_compliance AS
SELECT l.listing_id,
       l.host_id,
       n.neighbourhood_name,
       l.room_type,
       l.price,
       h.toronto_entire_homes,
       -- Nights booked last 12 months: use Inside Airbnb's estimate when present,
       -- otherwise a review-based proxy (assumes half of stays leave a review and
       -- a 3-night average stay). State this assumption in the report.
       COALESCE(l.estimated_occupancy_l365d,
                LEAST(365, l.number_of_reviews_ltm * 2 * GREATEST(l.minimum_nights, 3)))
           AS est_nights_ltm,
       CASE
           WHEN l.license IS NULL                     THEN 'Missing'
           WHEN UPPER(l.license) LIKE 'STR-%'         THEN 'Registration number'
           WHEN UPPER(l.license) LIKE '%EXEMPT%'      THEN 'Claims exempt'
           ELSE 'Other text'
       END AS licence_status,
       (l.room_type = 'Entire home/apt'
        AND COALESCE(l.estimated_occupancy_l365d,
                     LEAST(365, l.number_of_reviews_ltm * 2 * GREATEST(l.minimum_nights, 3)))
            > 180) AS flag_over_180,
       (h.toronto_entire_homes >= 2) AS flag_multi_home_host,
       (l.minimum_nights >= 28) AS is_long_term_only   -- 28+ nights is not a short-term rental under the bylaw
FROM listing l
JOIN host h               ON h.host_id = l.host_id
LEFT JOIN neighbourhood n ON n.neighbourhood_id = l.neighbourhood_id;

-- Staging tables can be dropped once 03_validate.sql passes:
-- DROP TABLE stg_listing, stg_listing_amenity;
