import sys, pathlib
from playwright.sync_api import sync_playwright
src = pathlib.Path(__file__).parent
out = src.parent
names = sys.argv[1:] or [p.stem for p in src.glob("*.html")]
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(device_scale_factor=2, viewport={"width": 1400, "height": 900})
    for n in names:
        pg.goto((src / f"{n}.html").resolve().as_uri())
        pg.wait_for_timeout(200)
        pg.locator("#shot").screenshot(path=str(out / f"{n}.png"))
        print("rendered", n)
    b.close()
