"""
OMIS 3730 | Toronto Airbnb project
Step 1: clean the Inside Airbnb files so MySQL can load them with LOAD DATA.

Usage:
    python 01_clean.py <raw_folder> <clean_folder> [calendar_days]

<raw_folder> must contain (downloaded from insideairbnb.com, Toronto, 16 Sept 2026 snapshot):
    listings.csv.gz, calendar.csv.gz, reviews.csv.gz, neighbourhoods.csv
calendar_days (optional, default 90) = how many days of the forward calendar to keep.

Outputs (in <clean_folder>):
    neighbourhoods.csv, listings_clean.csv, listing_amenity_raw.csv,
    calendar_clean.csv, reviews_clean.csv, row_counts.txt
NULLs are written as \\N, which MySQL LOAD DATA reads as NULL.
"""
import json
import sys
from pathlib import Path

import pandas as pd

NULL = "\\N"

# Columns we keep from the 75-column listings file. Any that are missing in this
# snapshot are skipped (Inside Airbnb adds/renames columns between versions).
LISTING_COLS = [
    "id", "last_scraped", "name", "host_id", "host_name", "host_since",
    "host_response_rate", "host_is_superhost", "host_identity_verified",
    "host_total_listings_count", "neighbourhood_cleansed", "latitude", "longitude",
    "property_type", "room_type", "accommodates", "bedrooms", "beds", "price",
    "minimum_nights", "maximum_nights", "availability_365", "number_of_reviews",
    "number_of_reviews_ltm", "first_review", "last_review", "review_scores_rating",
    "license", "instant_bookable", "calculated_host_listings_count",
    "calculated_host_listings_count_entire_homes",
    "calculated_host_listings_count_private_rooms",
    "estimated_occupancy_l365d", "estimated_revenue_l365d", "amenities",
]
INT_COLS = [
    "host_id", "host_total_listings_count", "accommodates", "bedrooms", "beds",
    "minimum_nights", "maximum_nights", "availability_365", "number_of_reviews",
    "number_of_reviews_ltm", "calculated_host_listings_count",
    "calculated_host_listings_count_entire_homes",
    "calculated_host_listings_count_private_rooms", "estimated_occupancy_l365d",
]
BOOL_COLS = ["host_is_superhost", "host_identity_verified", "instant_bookable"]
DATE_COLS = ["last_scraped", "host_since", "first_review", "last_review"]
TEXT_COLS = ["name", "host_name", "property_type", "room_type", "license",
             "neighbourhood_cleansed"]


def money(s: pd.Series) -> pd.Series:
    """'$1,234.00' -> 1234.0"""
    return pd.to_numeric(
        s.astype("string").str.replace(r"[$,]", "", regex=True), errors="coerce"
    )


def tf(s: pd.Series) -> pd.Series:
    """'t'/'f' -> 1/0"""
    return s.map({"t": 1, "f": 0}).astype("Int64")


def clean_text(s: pd.Series) -> pd.Series:
    """Remove line breaks, tabs and backslashes that break LOAD DATA."""
    return (s.astype("string")
             .str.replace(r"[\r\n\t]+", " ", regex=True)
             .str.replace("\\", "", regex=False)
             .str.strip()
             .replace("", pd.NA))


def to_date(s: pd.Series) -> pd.Series:
    return pd.to_datetime(s, errors="coerce").dt.strftime("%Y-%m-%d")


def write(df: pd.DataFrame, path: Path) -> int:
    df.to_csv(path, index=False, na_rep=NULL, lineterminator="\n")
    return len(df)


def main(raw: Path, out: Path, calendar_days: int) -> None:
    out.mkdir(parents=True, exist_ok=True)
    counts = {}

    # Neighbourhoods
    nb = pd.read_csv(raw / "neighbourhoods.csv")
    nb = nb[["neighbourhood"]].dropna().drop_duplicates()
    nb["neighbourhood"] = clean_text(nb["neighbourhood"])
    counts["neighbourhoods"] = write(nb, out / "neighbourhoods.csv")

    # Listings
    lst = pd.read_csv(raw / "listings.csv.gz", low_memory=False)
    counts["listings_raw"] = len(lst)
    keep = [c for c in LISTING_COLS if c in lst.columns]
    missing = sorted(set(LISTING_COLS) - set(keep))
    lst = lst[keep].copy()
    lst = lst.rename(columns={"id": "listing_id"})

    if "price" in lst:
        lst["price"] = money(lst["price"])
    if "estimated_revenue_l365d" in lst:
        lst["estimated_revenue_l365d"] = money(lst["estimated_revenue_l365d"])
    if "host_response_rate" in lst:
        lst["host_response_rate"] = pd.to_numeric(
            lst["host_response_rate"].astype("string").str.rstrip("%"),
            errors="coerce").astype("Int64")
    for c in INT_COLS:
        if c in lst:
            lst[c] = pd.to_numeric(lst[c], errors="coerce").round().astype("Int64")
    for c in BOOL_COLS:
        if c in lst:
            lst[c] = tf(lst[c])
    for c in DATE_COLS:
        if c in lst:
            lst[c] = to_date(lst[c])
    for c in TEXT_COLS:
        if c in lst:
            lst[c] = clean_text(lst[c])

    # Amenities: JSON array per listing -> one row per (listing, amenity)
    am_rows = []
    if "amenities" in lst:
        for lid, raw_am in zip(lst["listing_id"], lst["amenities"]):
            try:
                items = json.loads(raw_am) if isinstance(raw_am, str) else []
            except json.JSONDecodeError:
                items = []
            for a in set(items):
                a = " ".join(str(a).replace("\\", "").split())[:255]
                if a:
                    am_rows.append((lid, a))
        lst = lst.drop(columns=["amenities"])
    am = pd.DataFrame(am_rows, columns=["listing_id", "amenity_name"])
    counts["listing_amenity_rows"] = write(am, out / "listing_amenity_raw.csv")

    # Fixed column order so the SQL file always matches
    for c in LISTING_COLS:
        name = "listing_id" if c == "id" else c
        if c != "amenities" and name not in lst:
            lst[name] = pd.NA
    order = ["listing_id" if c == "id" else c for c in LISTING_COLS if c != "amenities"]
    lst = lst[order]
    counts["listings_clean"] = write(lst, out / "listings_clean.csv")
    valid_ids = set(lst["listing_id"])

    # Calendar: keep the first N days, only listings we kept
    start = None
    parts = []
    for chunk in pd.read_csv(raw / "calendar.csv.gz", chunksize=500_000,
                             low_memory=False):
        chunk["date"] = pd.to_datetime(chunk["date"], errors="coerce")
        if start is None:
            start = chunk["date"].min()
        end = start + pd.Timedelta(days=calendar_days)
        chunk = chunk[(chunk["date"] >= start) & (chunk["date"] < end)
                      & chunk["listing_id"].isin(valid_ids)]
        cal = pd.DataFrame({
            "listing_id": chunk["listing_id"],
            "cal_date": chunk["date"].dt.strftime("%Y-%m-%d"),
            "available": tf(chunk["available"]),
            "price": money(chunk["price"]) if "price" in chunk else pd.NA,
            "minimum_nights": pd.to_numeric(chunk.get("minimum_nights"),
                                            errors="coerce").astype("Int64"),
        })
        parts.append(cal)
    cal = pd.concat(parts, ignore_index=True).drop_duplicates(
        subset=["listing_id", "cal_date"])
    counts["calendar_clean"] = write(cal, out / "calendar_clean.csv")

    # Reviews: drop reviewer names and comment text (privacy + file size)
    rev = pd.read_csv(raw / "reviews.csv.gz", low_memory=False,
                      usecols=["listing_id", "id", "date", "reviewer_id"])
    rev = rev[rev["listing_id"].isin(valid_ids)]
    rev = pd.DataFrame({
        "review_id": rev["id"],
        "listing_id": rev["listing_id"],
        "review_date": to_date(rev["date"]),
        "reviewer_id": rev["reviewer_id"],
    }).drop_duplicates(subset=["review_id"])
    counts["reviews_clean"] = write(rev, out / "reviews_clean.csv")

    with open(out / "row_counts.txt", "w") as f:
        for k, v in counts.items():
            f.write(f"{k}: {v:,}\n")
        if missing:
            f.write(f"columns not in this snapshot (loaded as NULL): {', '.join(missing)}\n")
    print((out / "row_counts.txt").read_text())


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    days = int(sys.argv[3]) if len(sys.argv) > 3 else 90
    main(Path(sys.argv[1]), Path(sys.argv[2]), days)
