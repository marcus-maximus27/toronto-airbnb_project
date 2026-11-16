# toronto-airbnb_project
Is Toronto’s short-term rental bylaw working, and who is getting around it? This project is intended for the City of Toronto’s licensing and enforcement team or Airbnb’s compliance team, who need a ranked list of listings to investigate.

**Data:** Inside Airbnb, Toronto snapshot of 16 Sept 2026 (CC BY 4.0; credit "Inside Airbnb" in the slides and report)

## 1. Download (Python person)

Save these 4 files into `data/raw/` (git ignores this folder):

- https://data.insideairbnb.com/canada/on/toronto/2026-09-16/data/listings.csv.gz
- https://data.insideairbnb.com/canada/on/toronto/2026-09-16/data/calendar.csv.gz
- https://data.insideairbnb.com/canada/on/toronto/2026-09-16/data/reviews.csv.gz
- https://data.insideairbnb.com/canada/on/toronto/2026-09-16/visualisations/neighbourhoods.csv

Leave the `.gz` files compressed; pandas reads them directly.

## 2. Clean (Python person, about 5 minutes of runtime)

```
pip install pandas
python scripts/01_clean.py data/raw data/clean 90
```

This writes the cleaned files plus `row_counts.txt` to `data/clean/`. Commit `row_counts.txt` only; share the clean CSVs through Drive. The 90 keeps 90 days of the forward calendar.

## 3. Build the database (everyone, MySQL 8)

1. In `sql/02_build_database.sql`, replace `/path/to/clean/` with the full path to your `data/clean/` folder (forward slashes). Do not commit this edit.
2. Turn on local file loading: run `SET GLOBAL local_infile = 1;`, then in Workbench go to the connection's Advanced tab and add `OPT_LOCAL_INFILE=1` in the Others box. Reconnect.
3. Run `sql/02_build_database.sql`, then `sql/03_validate.sql`.
4. Check that the row counts from `03_validate.sql` match `row_counts.txt`.

## Repo layout

```
scripts/   01_clean.py
sql/       02_build_database.sql, 03_validate.sql, 04_analysis.sql
data/raw/  downloaded files (ignored)
data/clean/ cleaned files (ignored except row_counts.txt)
outputs/   query results for charts
docs/      ERD, report, slides
```

## Schema (7 tables + 1 view)

| Table | Primary key | Links to |
|---|---|---|
| neighbourhood | neighbourhood_id | |
| host | host_id | |
| listing | listing_id | host, neighbourhood |
| calendar_day | listing_id + cal_date | listing |
| review | review_id | listing |
| amenity | amenity_id | |
| listing_amenity | listing_id + amenity_id | listing, amenity (many-to-many) |
| v_listing_compliance (view) | | one row per listing with the bylaw flags |

## Data caveats to state in the report

- The calendar looks **forward** from 16 Sept 2026, and "unavailable" can mean booked or blocked by the host. It shows supply, not confirmed bookings.
- Nights booked use Inside Airbnb's `estimated_occupancy_l365d` when the snapshot has it. Otherwise the view falls back to a reviews-based proxy (assumes half of stays leave a review and a 3-night minimum stay).
- Licence numbers in this snapshot follow the format `STR-YYMM-...` (confirmed on the real data), so the `licence_status` CASE in the view works as written.
- Listings with a minimum stay of 28+ nights are not short-term rentals under the bylaw and do not need a registration number. They account for almost all entire homes with no licence, so filter with `is_long_term_only = 0` before calling anything unlicensed.
