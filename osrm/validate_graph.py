#!/usr/bin/env python3
"""
OSRM Graph Validation Script
Tests OSRM API with random routes near world capitals
Fails fast on any error, timeout, or unexpected response
"""

import csv
import random
import math
import sys
import argparse
import asyncio
import aiohttp
import time
import subprocess
from typing import Tuple, List, Optional

# Configuration
OSRM_HOST = "localhost"
OSRM_PORT = 8003
REQUESTS_PER_CAPITAL = 10
MAX_DISTANCE_KM = 100
# Default timeouts (overridden with --mmap flag)
REQUEST_TIMEOUT = 60  # seconds
PRINT_TIMEOUT = 5
# Timeouts for mmap mode (slower disk access)
MMAP_REQUEST_TIMEOUT = 600
MMAP_PRINT_TIMEOUT = 30

def generate_random_point(center_lat: float, center_lon: float, max_distance_km: float) -> Tuple[float, float]:
    """
    Generate a random point within max_distance_km of the center point.
    Uses uniform distribution in a circular area.
    """
    # Convert km to degrees (approximate)
    # 1 degree latitude ≈ 111 km
    # 1 degree longitude ≈ 111 km * cos(latitude)

    # Random distance from center (0 to max_distance_km)
    distance_km = random.uniform(0, max_distance_km)

    # Random bearing (0 to 360 degrees)
    bearing = random.uniform(0, 2 * math.pi)

    # Convert distance to degrees
    distance_deg_lat = distance_km / 111.0
    distance_deg_lon = distance_km / (111.0 * math.cos(math.radians(center_lat)))

    # Calculate new point
    delta_lat = distance_deg_lat * math.cos(bearing)
    delta_lon = distance_deg_lon * math.sin(bearing)

    new_lat = center_lat + delta_lat
    new_lon = center_lon + delta_lon

    return new_lat, new_lon

def validate_response(data: dict, status_code: int, url: str) -> Optional[str]:
    """
    Validate the OSRM response.
    Returns error message if invalid, None if valid.
    """
    # Check HTTP status - accept 200 (route found) or 400 (NoRoute/InvalidValue)
    if status_code == 400:
        code = data.get("code")
        message = data.get("message")

        valid_no_route_messages = [
            "Impossible route between points",
            "No route found between points"
        ]

        is_valid = (
            (code == "NoRoute" and message in valid_no_route_messages) or
            (code == "InvalidValue" and message == "Invalid coordinate value.")
        )

        if not is_valid:
            return f"ERROR: HTTP 400 but not a valid response\nCode: {code}, Message: {message}\nURL: {url}\nResponse: {data}"
        return None
    elif status_code != 200:
        return f"ERROR: HTTP {status_code}\nURL: {url}\nResponse: {data}"

    if "code" not in data:
        return f"ERROR: Response missing 'code' field\nURL: {url}\nResponse: {data}"

    if data["code"] not in ["Ok", "NoRoute"]:
        return f"ERROR: OSRM returned unexpected code '{data['code']}'\nURL: {url}\nResponse: {data}"

    if data["code"] == "NoRoute":
        expected_message = "Impossible route between points"
        if data.get("message") != expected_message:
            return f"ERROR: NoRoute response has unexpected message\nExpected: '{expected_message}'\nGot: '{data.get('message')}'\nURL: {url}\nResponse: {data}"

    if data["code"] == "Ok":
        if "routes" not in data or len(data["routes"]) == 0:
            return f"ERROR: Code is 'Ok' but no routes found in response\nURL: {url}\nResponse: {data}"

        route = data["routes"][0]
        if "distance" not in route or "duration" not in route:
            return f"ERROR: Route missing distance or duration\nURL: {url}\nResponse: {data}"

    return None

async def test_route_async(session: aiohttp.ClientSession, lat1: float, lon1: float, lat2: float, lon2: float) -> None:
    """
    Test a route between two points using OSRM API asynchronously.
    Raises exception on error.
    """
    url = f"http://{OSRM_HOST}:{OSRM_PORT}/route/v1/driving/{lon1:.6f},{lat1:.6f};{lon2:.6f},{lat2:.6f}"

    try:
        start_time = time.time()
        async with session.get(url) as response:
            elapsed = time.time() - start_time
            if elapsed > PRINT_TIMEOUT:
                print(f"SLOW: {elapsed:.2f}s - curl '{url}'")

            try:
                data = await response.json()
            except Exception as e:
                print(f"ERROR: Failed to parse JSON response: {e}")
                print(f"URL: {url}")
                print(f"HTTP Status: {response.status}")
                sys.exit(1)

            error = validate_response(data, response.status, url)
            if error:
                print(error)
                sys.exit(1)

    except asyncio.TimeoutError:
        print(f"ERROR: Request timeout for route ({lon1},{lat1}) -> ({lon2},{lat2})")
        print(f"curl '{url}'")
        sys.exit(1)
    except aiohttp.ClientConnectorError:
        print(f"ERROR: Connection error to OSRM server at {OSRM_HOST}:{OSRM_PORT}")
        print(f"URL: {url}")
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: Unexpected error during request: {e}")
        print(f"URL: {url}")
        sys.exit(1)

async def test_capital_async(session: aiohttp.ClientSession, center_lat: float, center_lng: float) -> None:
    """
    Test multiple routes around a capital in parallel.
    """
    tasks = []
    for _ in range(REQUESTS_PER_CAPITAL):
        lat1, lon1 = generate_random_point(center_lat, center_lng, MAX_DISTANCE_KM)
        lat2, lon2 = generate_random_point(center_lat, center_lng, MAX_DISTANCE_KM)
        tasks.append(test_route_async(session, lat1, lon1, lat2, lon2))

    await asyncio.gather(*tasks)

async def main_async(capitals: List[dict]) -> int:
    """
    Main async function to test all capitals.
    Returns total number of requests made.
    """
    timeout = aiohttp.ClientTimeout(total=REQUEST_TIMEOUT)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        total_requests = 0
        for idx, capital in enumerate(capitals, 1):
            country = capital['country']
            city = capital['city']
            center_lat = capital['lat']
            center_lng = capital['lng']
            if idx % 1005 == 0:
              print(f"[{idx}/{len(capitals)}] Testing {city}, {country} ({center_lat:.4f}, {center_lng:.4f})")

            await test_capital_async(session, center_lat, center_lng)
            total_requests += REQUESTS_PER_CAPITAL

    return total_requests

def wait_for_osrm_process():
    """
    Wait for osrm-routed process to exist, then wait 10 minutes for startup.
    Skip waiting if process is found on first attempt.
    """
    first_attempt = True
    while True:
        result = subprocess.run(['pgrep', '-x', 'osrm-routed'], capture_output=True)
        if result.returncode == 0:
            if first_attempt:
                print("osrm-routed process found, starting tests...")
                return
            else:
                print("osrm-routed process found, waiting 15 minutes for startup...")
                time.sleep(900)  # 15 minutes
                return
        else:
            print("finding osrm process")
            time.sleep(900)  # 15 minutes
            first_attempt = False


def main():
    global REQUEST_TIMEOUT, PRINT_TIMEOUT, OSRM_PORT

    wait_for_osrm_process()

    parser = argparse.ArgumentParser(description='OSRM Graph Validation Script')
    parser.add_argument('csv_file', help='CSV file with capitals data (e.g., capitals.csv, capitals_full.csv)')
    parser.add_argument('--port', type=int, default=OSRM_PORT, help=f'OSRM server port (default: {OSRM_PORT})')
    parser.add_argument('--mmap', action='store_true', help='Use extended timeouts for mmap mode (REQUEST_TIMEOUT=300, PRINT_TIMEOUT=30)')
    args = parser.parse_args()

    OSRM_PORT = args.port

    if args.mmap:
        REQUEST_TIMEOUT = MMAP_REQUEST_TIMEOUT
        PRINT_TIMEOUT = MMAP_PRINT_TIMEOUT

    csv_file = args.csv_file

    print(f"OSRM Graph Validation")
    print(f"=" * 60)
    print(f"CSV file: {csv_file}")
    print(f"Server: {OSRM_HOST}:{OSRM_PORT}")
    print(f"Requests per capital: {REQUESTS_PER_CAPITAL}")
    print(f"Max distance: {MAX_DISTANCE_KM} km")
    print(f"Request timeout: {REQUEST_TIMEOUT} seconds")
    print(f"=" * 60)
    print()

    # Load capitals
    capitals = []
    try:
        with open(csv_file, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                capitals.append({
                    'country': row['country'],
                    'city': row['city'],
                    'lat': float(row['lat']),
                    'lng': float(row['lng'])
                })
    except FileNotFoundError:
        print(f"ERROR: {csv_file} not found")
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: Failed to read {csv_file}: {e}")
        sys.exit(1)

    print(f"Loaded {len(capitals)} capitals\n")

    # Run async tests
    total_requests = asyncio.run(main_async(capitals))

    print("=" * 60)
    print(f"SUCCESS: All {total_requests} requests completed successfully!")
    print(f"Validated {len(capitals)} capitals × {REQUESTS_PER_CAPITAL} requests each")
    print("=" * 60)

if __name__ == "__main__":
    main()
