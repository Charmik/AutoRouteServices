#!/usr/bin/env python3
"""
Script to scrape all .geojson file links from HeiGIT HDX Road Surface Data datasets.
Iterates over all pages and extracts geojson download links from each dataset.
"""

import requests
from bs4 import BeautifulSoup
import time
import re
from urllib.parse import urljoin

def get_dataset_links(page_num):
    """Get all dataset links from a page."""
    url = f"https://data.humdata.org/organization/heidelberg-institute-for-geoinformation-technology?q=Road%20Surface%20Data&sort=score%20desc%2C%20last_modified%20desc&ext_page_size=100&page={page_num}"

    print(f"Fetching page {page_num}: {url}")

    try:
        response = requests.get(url, timeout=30)
        response.raise_for_status()
    except requests.RequestException as e:
        print(f"Error fetching page {page_num}: {e}")
        return []

    soup = BeautifulSoup(response.text, 'html.parser')

    # Find all dataset links
    dataset_links = []
    for link in soup.find_all('a', href=True):
        href = link['href']
        if '/dataset/' in href and href.startswith('/dataset/'):
            full_url = urljoin('https://data.humdata.org', href)
            if full_url not in dataset_links:
                dataset_links.append(full_url)

    print(f"Found {len(dataset_links)} dataset links on page {page_num}")
    return dataset_links

def get_geojson_links(dataset_url):
    """Extract all .geojson file links from a dataset page."""
    print(f"  Fetching dataset: {dataset_url}")

    try:
        response = requests.get(dataset_url, timeout=30)
        response.raise_for_status()
    except requests.RequestException as e:
        print(f"  Error fetching dataset {dataset_url}: {e}")
        return []

    soup = BeautifulSoup(response.text, 'html.parser')

    geojson_links = []

    # Find all links that point to .geojson files
    for link in soup.find_all('a', href=True):
        href = link['href']
        if '.geojson' in href.lower():
            # Make sure it's a full URL
            if href.startswith('http'):
                geojson_links.append(href)
            else:
                full_url = urljoin(dataset_url, href)
                geojson_links.append(full_url)

    # Also search for direct text that might contain URLs
    text = soup.get_text()
    geojson_pattern = re.findall(r'https?://[^\s<>"]+\.geojson', text)
    for url in geojson_pattern:
        if url not in geojson_links:
            geojson_links.append(url)

    print(f"  Found {len(geojson_links)} geojson files:")
    for link in geojson_links:
        print(f"    -> {link}")
    return geojson_links

def main():
    """Main function to scrape all geojson links."""
    output_file = 'geojson_links.txt'
    seen = set()
    total_count = 0

    # Open file for writing from the start
    with open(output_file, 'w') as f:
        # Iterate over 5 pages
        for page_num in range(1, 6):
            dataset_links = get_dataset_links(page_num)

            # For each dataset, get the geojson links
            for dataset_url in dataset_links:
                geojson_links = get_geojson_links(dataset_url)

                # Write unique links immediately
                for link in geojson_links:
                    if link not in seen:
                        seen.add(link)
                        f.write(link + '\n')
                        f.flush()  # Force write to disk immediately
                        total_count += 1

                # Be polite to the server
                time.sleep(10)

            # Be polite between pages
            time.sleep(100)

    print(f"\n{'='*60}")
    print(f"Total unique geojson links found: {total_count}")
    print(f"{'='*60}\n")
    print(f"All links saved to {output_file}")

if __name__ == '__main__':
    main()
