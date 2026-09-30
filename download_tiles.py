import os, urllib.request, math, time

REGIONS = [
    {
        "name": "Karnataka State (Overview)",
        "min_lat": 11.5, "max_lat": 18.5,
        "min_lon": 74.0, "max_lon": 78.5,
        "min_zoom": 5, "max_zoom": 10
    },
    {
        "name": "Target Hiking Trail (High Detail)",
        "min_lat": 12.879, "max_lat": 12.939,
        "min_lon": 74.869, "max_lon": 74.929,
        "min_zoom": 11, "max_zoom": 17
    }
]

OUT_DIR = "assets/maps"

def lon_to_x(lon, z): return int((lon + 180.0) / 360.0 * (2**z))
def lat_to_y(lat, z):
    rad = math.radians(lat)
    return int((1.0 - math.log(math.tan(rad) + 1/math.cos(rad)) / math.pi) / 2.0 * (2**z))

os.makedirs(OUT_DIR, exist_ok=True)
headers = {"User-Agent": "TrailGuard-Hackathon-Project/1.0 (student project, low volume)"}

for region in REGIONS:
    print(f"\n--- Downloading {region['name']} ---")
    total, ok, failed = 0, 0, 0
    for z in range(region['min_zoom'], region['max_zoom'] + 1):
        x1, x2 = lon_to_x(region['min_lon'], z), lon_to_x(region['max_lon'], z)
        y1, y2 = lat_to_y(region['max_lat'], z), lat_to_y(region['min_lat'], z)
        for x in range(min(x1, x2), max(x1, x2) + 1):
            for y in range(min(y1, y2), max(y1, y2) + 1):
                total += 1
                path = f"{OUT_DIR}/{z}_{x}_{y}.png"
                if os.path.exists(path):
                    ok += 1
                    continue
                url = f"https://tile.openstreetmap.org/{z}/{x}/{y}.png"
                try:
                    req = urllib.request.Request(url, headers=headers)
                    with urllib.request.urlopen(req, timeout=10) as resp:
                        with open(path, "wb") as f:
                            f.write(resp.read())
                    ok += 1
                    time.sleep(0.3)
                except Exception as e:
                    failed += 1
                    print(f"Failed {z}/{x}/{y}: {e}")
    print(f"Done {region['name']}. {ok}/{total} tiles saved to {OUT_DIR}/ ({failed} failed)")