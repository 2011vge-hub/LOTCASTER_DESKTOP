const assert = require("node:assert/strict");
const fs = require("node:fs");
const { chromium } = require("playwright");

const fixture = fs.readFileSync(`${__dirname}/facebook-helper-flow-fixture.html`, "utf8");
const helperPath = `${__dirname}/../facebook-helper/facebook-form.js`;
const vehicles = [
  { title: "2025 RAM 3500 Big Horn", year: "2025", make: "RAM", model: "3500", bodyType: "truck", bodyStyle: "Truck" },
  { title: "2024 Cadillac XT6 Premium Luxury", year: "2024", make: "Cadillac", model: "XT6", bodyType: "suv", bodyStyle: "Sport Utility" },
  { title: "2025 Chrysler Pacifica Limited", year: "2025", make: "Chrysler", model: "Pacifica", bodyType: "van", bodyStyle: "Van" },
  { title: "2021 Honda Accord Touring", year: "2021", make: "Honda", model: "Accord", bodyType: "car", bodyStyle: "Sedan" }
];

function encodePayload(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"
  });
  try {
    for (const vehicle of vehicles) {
      const page = await browser.newPage();
      page.on("pageerror", (error) => console.error(`Fixture page error: ${error.message}`));
      await page.route("http://facebook.test/**", (route) => route.fulfill({ contentType: "text/html", body: fixture }));
      const packet = {
        ...vehicle,
        facebookListingType: "Car/Truck",
        price: "30000",
        mileage: "25000",
        vin: "1TESTVIN000000000",
        fuelType: "Gasoline",
        condition: "Excellent",
        description: `${vehicle.title} test description`,
        images: ["https://images.example.com/vehicle-1.png"]
      };
      await page.goto(`http://facebook.test/marketplace/create/vehicle#lotcaster=${encodePayload(packet)}`);
      await page.evaluate(() => {
        globalThis.chrome = {
          runtime: {
            sendMessage: async () => ({
              contentType: "image/png",
              bytes: [137, 80, 78, 71, 13, 10, 26, 10]
            })
          }
        };
      });
      if (vehicle.bodyType === "truck") {
        await page.evaluate(() => {
          const dialog = document.createElement("div");
          dialog.id = "listing-location-dialog";
          dialog.setAttribute("role", "dialog");
          dialog.setAttribute("aria-modal", "true");
          dialog.textContent = "Listing location";
          Object.assign(dialog.style, { width: "500px", height: "300px", display: "block" });
          document.body.append(dialog);
        });
      }
      await page.addScriptTag({ path: helperPath });
      await page.waitForTimeout(900);
      assert.equal(await page.locator("#vehicle-type").getAttribute("data-clicks"), null, "Helper automatically clicked Facebook's Vehicle type control");
      if (vehicle.bodyType === "truck") {
        assert.equal(await page.locator("#vehicle-type").getAttribute("aria-selected"), null, "Helper did not pause for Listing location modal");
        assert.equal(await page.locator("#listing-location").getAttribute("data-clicks"), null, "Helper interacted with Listing location modal");
        assert.equal(await page.locator("#lotcaster-manual-assist").count(), 0, "Helper panel remained over Facebook's Listing location map");
        assert.equal(await page.locator("#walker-helper-notice").count(), 0, "Helper notice remained over Facebook's Listing location map");
        await page.evaluate(() => document.querySelector("#listing-location-dialog")?.remove());
      }
      await page.locator("#vehicle-type").click();
      await page.locator("[data-type='Car/Truck']").click();
      try {
        await page.waitForFunction(({ expectedYear, expectedMake }) =>
          document.querySelector("#vehicle-type")?.getAttribute("aria-selected") === "true" &&
          document.querySelector("[name=year]")?.value === expectedYear &&
          document.querySelector("[name=make]")?.value === expectedMake
        , { expectedYear: vehicle.year, expectedMake: vehicle.make }, { timeout: 10000 });
      } catch (error) {
        const state = await page.evaluate(() => ({
          type: document.querySelector("#vehicle-type")?.outerHTML,
          typeRect: document.querySelector("#vehicle-type")?.getBoundingClientRect().toJSON(),
          typeStyle: document.querySelector("#vehicle-type") ? getComputedStyle(document.querySelector("#vehicle-type")).cssText : "",
          typeOptions: document.querySelector("#type-options")?.outerHTML,
          make: document.querySelector("[name=make]")?.value,
          locationClicks: document.querySelector("#listing-location")?.dataset.clicks,
          notice: document.querySelector("#walker-helper-notice")?.textContent,
          assist: document.querySelector("#lotcaster-manual-assist")?.textContent
        }));
        throw new Error(`${vehicle.title} stalled: ${JSON.stringify(state)}; ${error.message}`);
      }

      assert.equal(await page.locator("#vehicle-type").textContent(), "Car or truck", `${vehicle.title} did not select Car/Truck`);
      assert.equal(await page.locator("#vehicle-type").getAttribute("data-clicks"), "1", `${vehicle.title} manual Vehicle type selection was not preserved`);
      assert.equal(await page.locator("[name=year]").inputValue(), vehicle.year, `${vehicle.title} year was not corrected after VIN autofill`);
      assert.equal(await page.locator("[name=make]").inputValue(), vehicle.make, `${vehicle.title} make was not filled`);
      assert.equal(await page.locator("#listing-location").getAttribute("data-clicks"), null, `${vehicle.title} incorrectly opened Facebook's location map`);
      await page.waitForFunction(() => document.querySelector("#vehicle-photos")?.files?.length === 1, null, { timeout: 5000 });
      assert.equal(await page.locator("#vehicle-photos").evaluate((input) => input.files.length), 1, `${vehicle.title} photo was not attached`);
      await page.close();
      console.log(`Facebook helper flow passed: ${vehicle.title}`);
    }

    const retryPage = await browser.newPage();
    await retryPage.route("http://facebook.test/**", (route) => route.fulfill({ contentType: "text/html", body: fixture }));
    const retryPacket = {
      ...vehicles[2],
      facebookListingType: "Car/Truck",
      price: "30000",
      mileage: "25000",
      vin: "1TESTVIN000000000",
      fuelType: "Gasoline",
      condition: "Excellent",
      description: "Retry safety test"
    };
    await retryPage.goto(`http://facebook.test/marketplace/create/vehicle#lotcaster=${encodePayload(retryPacket)}`);
    await retryPage.evaluate(() => document.querySelector("[data-type='Car/Truck']")?.remove());
    await retryPage.addScriptTag({ path: helperPath });
    await retryPage.waitForTimeout(2500);
    assert.equal(await retryPage.locator("#vehicle-type").getAttribute("data-clicks"), null, "Helper clicked Vehicle type when Car/Truck was unavailable");
    assert.equal(await retryPage.locator("#listing-location").getAttribute("data-clicks"), null, "Failed Vehicle type selection clicked Listing location");
    await retryPage.close();
    console.log("Facebook helper safety passed: no automatic type or location interaction");

    const mismatchPage = await browser.newPage();
    await mismatchPage.route("http://facebook.test/**", (route) => route.fulfill({ contentType: "text/html", body: fixture }));
    const mismatchPacket = {
      ...vehicles[1],
      make: "Toyota",
      facebookListingType: "Car/Truck",
      price: "30000",
      mileage: "25000",
      vin: "1TESTVIN000000000",
      fuelType: "Gasoline",
      condition: "Excellent",
      description: "Identity mismatch must not reach the model field"
    };
    await mismatchPage.goto(`http://facebook.test/marketplace/create/vehicle#lotcaster=${encodePayload(mismatchPacket)}`);
    await mismatchPage.addScriptTag({ path: helperPath });
    await mismatchPage.locator("#vehicle-type").click();
    await mismatchPage.locator("[data-type='Car/Truck']").click();
    await mismatchPage.waitForFunction(() =>
      document.querySelector("#walker-helper-notice")?.textContent.includes("stopped because")
    , null, { timeout: 10000 });
    assert.equal(await mismatchPage.locator("[name=model]").inputValue(), "", "Helper filled Model before Year and Make identity matched");
    assert.equal(await mismatchPage.locator("#listing-location").getAttribute("data-clicks"), null, "Identity recovery clicked Listing location");
    await mismatchPage.close();
    console.log("Facebook helper identity guard passed: mismatched Make blocked dependent fields and stopped");
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
