import json
import os
import random
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")

BRONZE_BUCKET = os.environ["BRONZE_BUCKET"]

# Synthetic catalog — replace with a real API call when ready
PRODUCTS = [f"SKU-{1000 + i}" for i in range(100)]

POSITIVE = [
    "Love it, exactly as described.",
    "Fast shipping, great quality.",
    "Works perfectly, would buy again.",
    "Best purchase this month.",
]
NEUTRAL = [
    "It's fine, does the job.",
    "As expected for the price.",
    "Nothing special, nothing wrong.",
]
NEGATIVE = [
    "Arrived damaged, very disappointed.",
    "Stopped working after a week.",
    "Not what I expected from the photos.",
    "Poor quality for the price.",
]


def _sentiment(text: str) -> str:
    if text in POSITIVE:
        return "positive"
    if text in NEGATIVE:
        return "negative"
    return "neutral"


def _generate_reviews(n: int = 20) -> list:
    now = datetime.now(timezone.utc)
    reviews = []
    for i in range(n):
        # Weighted sentiment: 60% positive, 20% neutral, 20% negative
        roll = random.random()
        if roll < 0.6:
            text = random.choice(POSITIVE)
        elif roll < 0.8:
            text = random.choice(NEUTRAL)
        else:
            text = random.choice(NEGATIVE)

        reviews.append({
            "review_id": f"R-{int(now.timestamp())}-{i:04d}",
            "product_id": random.choice(PRODUCTS),
            "customer_id": random.randint(1, 10),
            "rating": 5 if text in POSITIVE else (3 if text in NEUTRAL else 1),
            "sentiment": _sentiment(text),
            "text": text,
            "review_ts": now.isoformat(),
        })
    return reviews


def handler(event, context):
    ingestion_ts = datetime.now(timezone.utc)
    reviews = _generate_reviews(n=20)

    key = (
        f"raw/reviews/"
        f"year={ingestion_ts.year}/month={ingestion_ts.month:02d}/"
        f"day={ingestion_ts.day:02d}/hour={ingestion_ts.hour:02d}/"
        f"batch_{int(ingestion_ts.timestamp())}.json"
    )

    body = {
        "source": "synthetic-reviews",
        "ingested_at": ingestion_ts.isoformat(),
        "count": len(reviews),
        "reviews": reviews,
    }

    s3.put_object(
        Bucket=BRONZE_BUCKET,
        Key=key,
        Body=json.dumps(body).encode("utf-8"),
        ContentType="application/json",
        ServerSideEncryption="aws:kms",
    )

    print(json.dumps({"written": key, "count": len(reviews)}))
    return {"statusCode": 200, "written": key, "count": len(reviews)}
