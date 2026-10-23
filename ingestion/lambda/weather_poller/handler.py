import json
import os
import urllib.parse
import urllib.request
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")

BRONZE_BUCKET = os.environ["BRONZE_BUCKET"]
API_BASE = os.environ.get("API_BASE", "https://api.open-meteo.com/v1/forecast")

CITIES = {
    "NewYork":  (40.7128,  -74.0060, "America/New_York"),
    "London":   (51.5074,   -0.1278, "Europe/London"),
    "Tokyo":    (35.6762,  139.6503, "Asia/Tokyo"),
    "Sydney":   (-33.8688, 151.2093, "Australia/Sydney"),
    "SaoPaulo": (-23.5505, -46.6333, "America/Sao_Paulo"),
}


def _fetch(url: str, timeout: int = 10) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "lakehouse-weather-poller/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def handler(event, context):
    ingestion_ts = datetime.now(timezone.utc)
    written, errors = [], []

    for city, (lat, lon, tz) in CITIES.items():
        query = urllib.parse.urlencode({
            "latitude": lat,
            "longitude": lon,
            "current": "temperature_2m,precipitation,weather_code,wind_speed_10m,relative_humidity_2m",
            "timezone": tz,
        })
        url = f"{API_BASE}?{query}"

        try:
            payload = _fetch(url)
        except Exception as e:
            errors.append({"city": city, "error": str(e)})
            continue

        key = (
            f"raw/weather/"
            f"year={ingestion_ts.year}/month={ingestion_ts.month:02d}/"
            f"day={ingestion_ts.day:02d}/hour={ingestion_ts.hour:02d}/"
            f"{city}_{int(ingestion_ts.timestamp())}.json"
        )
        body = {
            "source": "open-meteo",
            "city": city,
            "lat": lat,
            "lon": lon,
            "ingested_at": ingestion_ts.isoformat(),
            "payload": payload,
        }
        s3.put_object(
            Bucket=BRONZE_BUCKET,
            Key=key,
            Body=json.dumps(body).encode("utf-8"),
            ContentType="application/json",
            ServerSideEncryption="aws:kms",
        )
        written.append(key)

    print(json.dumps({"written": written, "errors": errors}))
    return {"statusCode": 200, "written": len(written), "errors": errors}