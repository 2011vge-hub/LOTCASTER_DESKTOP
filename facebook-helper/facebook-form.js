(() => {
  const STORAGE_KEY = "lotcasterPendingVehicle";
  const markers = ["#lotcaster=", "#walker="];
  const vehicle = readVehicle();
  if (!vehicle) return;
  const listingType = facebookListingType(vehicle);

  history.replaceState(null, "", `${location.pathname}${location.search}`);
  showNotice("LotCaster is looking for Facebook's vehicle listing form.");

  const preparedFuelType = facebookFuelType(vehicle);
  const fields = [
    // VIN must settle before Facebook's dependent identity fields are corrected.
    { key: "vin", label: "VIN", value: vehicle.vin, settleAfterChange: 1400 },
    { key: "year", label: "Year", value: vehicle.year, exactOption: true },
    { key: "make", label: "Make", value: vehicle.make, exactOption: true },
    { key: "model", label: "Model", value: vehicle.model, requiresIdentity: true },
    { key: "trim", label: "Trim", value: vehicle.trim, requiresIdentity: true },
    { key: "mileage", label: "Mileage", alternateLabels: ["Odometer"], value: vehicle.mileage, requiresIdentity: true },
    { key: "price", label: "Price", value: vehicle.postingPrice || vehicle.price, requiresIdentity: true },
    { key: "bodyStyle", label: "Body style", value: facebookBodyStyle(vehicle.bodyStyle, vehicle.bodyType), exactOption: true, requiresIdentity: true },
    { key: "exteriorColor", label: "Exterior color", value: facebookColor(vehicle.exteriorColor), exactOption: true, requiresIdentity: true },
    { key: "interiorColor", label: "Interior color", value: facebookColor(vehicle.interiorColor), exactOption: true, requiresIdentity: true },
    { key: "condition", label: "Vehicle condition", value: "Excellent", exactOption: true, requiresIdentity: true },
    { key: "fuelType", label: "Fuel type", value: preparedFuelType, exactOption: true, requiresIdentity: true },
    { key: "description", label: "Description", value: vehicle.description, requiresIdentity: true }
  ];

  let busy = false;
  let completed = false;
  let listingTypeConfirmed = false;
  let fillPasses = 0;
  let debounceTimer;
  const startedAt = Date.now();
  const maximumWaitMs = 3 * 60 * 1000;
  const maximumFillPasses = 4;

  const observer = new MutationObserver(scheduleFill);
  observer.observe(document.documentElement, { childList: true, subtree: true });
  const interval = window.setInterval(scheduleFill, 400);
  scheduleFill();

  function readVehicle() {
    const marker = markers.find((candidate) => location.hash.includes(candidate));
    if (marker) {
      try {
        const markerIndex = location.hash.indexOf(marker);
        const encoded = location.hash.slice(markerIndex + marker.length).replace(/-/g, "+").replace(/_/g, "/");
        const padded = encoded + "=".repeat((4 - encoded.length % 4) % 4);
        const bytes = Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
        const parsed = JSON.parse(new TextDecoder().decode(bytes));
        sessionStorage.setItem(STORAGE_KEY, JSON.stringify(parsed));
        return parsed;
      } catch {
        showNotice("LotCaster listing data could not be read.", true);
        return null;
      }
    }

    try {
      const pending = sessionStorage.getItem(STORAGE_KEY);
      return pending ? JSON.parse(pending) : null;
    } catch {
      return null;
    }
  }

  function scheduleFill() {
    if (busy || completed) return;
    window.clearTimeout(debounceTimer);
    debounceTimer = window.setTimeout(runFillPass, 75);
  }

  async function runFillPass() {
    if (busy || completed) return;
    if (hasBlockingLocationDialog()) {
      hideHelperOverlays();
      return;
    }
    if (Date.now() - startedAt > maximumWaitMs) {
      showNotice(`LotCaster is still waiting. Select ${listingType} manually; LotCaster will fill details only after Facebook opens the vehicle form.`, true);
      return;
    }

    const visibleDetailFields = fields.filter((field) => field.value && findField(field)).length;
    listingTypeConfirmed = listingTypeConfirmed || isListingTypeSelected(listingType);
    if (!listingTypeConfirmed || visibleDetailFields < 2) {
      showNotice(`Select ${listingType} manually. LotCaster will not touch Facebook's type or location controls.`);
      return;
    }

    busy = true;
    fillPasses += 1;
    showNotice("Vehicle form detected. LotCaster is adding the prepared details now.");
    const filledKeys = new Set();
    try {
      for (const field of fields) {
        if (!field.value) continue;
        if (field.requiresIdentity && !vehicleIdentityMatches()) continue;
        const element = findField(field);
        if (!element) continue;
        const before = fieldCurrentValue(element, field);
        const filled = field.exactOption
          ? await selectStrictFacebookOption(element, field)
          : await fillControl(element, field.value);
        if (filled) filledKeys.add(field.key);
        if (filled && field.settleAfterChange && normalize(before) !== normalize(field.value)) {
          await wait(field.settleAfterChange);
        } else {
          await wait(60);
        }
      }

      const requiredKeys = ["year", "make", "model", "bodyStyle", "price", "fuelType", "condition", "description"]
        .filter((key) => fields.find((field) => field.key === key)?.value);
      const requiredReady = listingTypeConfirmed && vehicleIdentityMatches() && requiredKeys.every((key) => filledKeys.has(key));
      if (requiredReady) {
        finish(`LotCaster assisted with ${filledKeys.size} fields. Photos may continue attaching briefly. Verify everything and publish manually.`, false);
        if (vehicle.images?.length || vehicle.image) {
          schedulePhotoAttach(vehicle.images || [vehicle.image]);
        }
      } else if (fillPasses >= maximumFillPasses) {
        const unresolved = requiredKeys.filter((key) => !filledKeys.has(key));
        finish(
          vehicleIdentityMatches()
            ? `LotCaster stopped after ${maximumFillPasses} safe passes. Complete these fields manually: ${unresolved.join(", ") || "Facebook-required dropdowns"}.`
            : `LotCaster stopped because Facebook's Year or Make does not match ${vehicle.year} ${vehicle.make}. Correct those two fields before entering the model.`,
          true
        );
      } else {
        showNotice(`LotCaster completed safe pass ${fillPasses} of ${maximumFillPasses}. Verifying Facebook's dependent fields.`);
      }
    } finally {
      busy = false;
    }
  }

  async function fillControl(element, value) {
    if (element.tagName === "SELECT") return selectClosestOption(element, value);
    // Facebook's custom comboboxes can visually overlap or redirect to Listing
    // location. They are always left for the user; LotCaster only writes into
    // ordinary text controls and native selects.
    if (element.getAttribute("role") === "combobox") return false;

    const desired = String(value);
    const current = element.isContentEditable ? element.textContent : element.value;
    if (normalize(current) === normalize(desired)) return true;
    setNativeValue(element, desired);
    return true;
  }

  function findField(field) {
    const expectedLabels = [field.label, ...(field.alternateLabels || [])].map(normalize);
    const controls = [...document.querySelectorAll("input, textarea, select, [contenteditable='true'], [role='combobox'], [aria-haspopup]")];
    return controls
      .filter((control) => {
        if (!isVisible(control)) return false;
        if (isForbiddenLocationTarget(control)) return false;
        const modal = control.closest("[role='dialog'], [aria-modal='true']");
        if (modal && /\blisting location\b|\blocation proximity\b/.test(normalize(modal.textContent))) return false;
        const type = normalize(control.getAttribute("type"));
        if (type === "hidden" || type === "checkbox" || type === "radio" || type === "search") return false;
        const label = strictControlLabel(control);
        return expectedLabels.includes(label);
      })
      [0] || null;
  }

  function strictControlLabel(control) {
    const ariaLabel = normalize(control.getAttribute("aria-label"));
    if (ariaLabel) return ariaLabel;
    const labelledBy = control.getAttribute("aria-labelledby");
    if (labelledBy) {
      const labelText = labelledBy.split(/\s+/)
        .map((id) => document.getElementById(id)?.textContent)
        .filter(Boolean)
        .join(" ");
      if (normalize(labelText)) return normalize(labelText);
    }
    const label = control.closest("label");
    if (label) {
      const directText = [...label.childNodes]
        .filter((node) => node.nodeType === 3)
        .map((node) => normalize(node.textContent))
        .find(Boolean);
      if (directText) return directText;
      const directLabel = [...label.querySelectorAll("span")]
        .map((span) => normalize(span.textContent))
        .find((text) => text && text.length <= 40);
      if (directLabel) return directLabel;
    }
    if (control.id) {
      const explicit = document.querySelector(`label[for="${CSS.escape(control.id)}"]`);
      if (explicit) return normalize(explicit.textContent);
    }
    return normalize(control.getAttribute("placeholder") || control.getAttribute("name"));
  }

  function isVisible(element) {
    const style = window.getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
  }

  function displayBodyType(value) {
    if (!value || value === "unknown") return "";
    if (String(value).toLowerCase() === "suv") return "SUV";
    return String(value).charAt(0).toUpperCase() + String(value).slice(1);
  }

  function facebookBodyStyle(style, bodyType) {
    const text = normalize(`${style || ""} ${bodyType || ""}`);
    if (/\b(pickup|truck)\b/.test(text)) return "Truck";
    if (/\bsuv\b/.test(text)) return "SUV";
    if (/\bmini\s*van|minivan\b/.test(text)) return "Minivan";
    if (/\bvan\b/.test(text)) return "Van";
    if (/\bcoupe\b/.test(text)) return "Coupe";
    if (/\bconvertible\b/.test(text)) return "Convertible";
    if (/\bhatchback\b/.test(text)) return "Hatchback";
    if (/\bwagon\b/.test(text)) return "Wagon";
    if (/\bsedan|car\b/.test(text)) return "Sedan";
    return displayBodyType(bodyType) || style || "";
  }

  function facebookColor(value) {
    const text = normalize(value);
    if (!text) return "";
    if (/\bblack|ebony|onyx|charcoal\b/.test(text)) return "Black";
    if (/\bwhite|pearl|ivory|summit\b/.test(text)) return "White";
    if (/\bsilver|steel|aluminum|ingot\b/.test(text)) return "Silver";
    if (/\bgray|grey|graphite|slate|magnetic\b/.test(text)) return "Gray";
    if (/\bred|maroon|burgundy|crimson|ruby\b/.test(text)) return "Red";
    if (/\bblue|navy|aqua\b/.test(text)) return "Blue";
    if (/\bbrown|tan|beige|sand|mocha|cocoa|kalahari\b/.test(text)) return "Brown";
    if (/\bgold|champagne\b/.test(text)) return "Gold";
    if (/\bgreen|olive\b/.test(text)) return "Green";
    if (/\borange|copper\b/.test(text)) return "Orange";
    if (/\byellow\b/.test(text)) return "Yellow";
    if (/\bpurple|plum\b/.test(text)) return "Purple";
    return "Other";
  }

  function facebookListingType(vehicleData) {
    const explicit = normalize(vehicleData.facebookListingType);
    return explicit === "car/truck" ? "Car/Truck" : "";
  }

  function facebookFuelType(vehicleData) {
    const text = normalize([
      vehicleData.fuelType,
      vehicleData.fuel,
      vehicleData.engine,
      vehicleData.powertrain,
      vehicleData.title,
      vehicleData.make,
      vehicleData.model,
      vehicleData.trim,
      vehicleData.description,
      vehicleData.marketplaceText,
      vehicleData.customDescription
    ].filter(Boolean).join(" "));
    if (/\b(diesel|duramax|powerstroke|power stroke|cummins|tdi)\b/.test(text)) return "Diesel";
    if (/\b(plug-in hybrid|plug in hybrid|phev)\b/.test(text)) return "Hybrid";
    if (/\b(hybrid|hev|eassist|e-assist)\b/.test(text)) return "Hybrid";
    if (/\b(electric|battery electric|bev| ev\b|bolt ev|mach-e|leaf|tesla|ioniq 5|ioniq 6)\b/.test(text)) return "Electric";
    if (/\b(gasoline|gas|petrol|regular unleaded|unleaded|flex fuel|e85)\b/.test(text)) return "Gasoline";
    return "Gasoline";
  }

  function fieldText(control) {
    const parts = [directFieldText(control)];
    let parent = control.parentElement;
    for (let level = 0; parent && level < 3; level += 1, parent = parent.parentElement) {
      parts.push(parent.textContent?.slice(0, 120));
    }
    return parts.filter(Boolean).join(" ");
  }

  function directFieldText(control) {
    const parts = [
      control.getAttribute("aria-label"),
      control.getAttribute("placeholder"),
      control.getAttribute("name"),
      control.getAttribute("id")
    ];
    if (control.id) {
      const label = document.querySelector(`label[for="${CSS.escape(control.id)}"]`);
      if (label) parts.push(label.textContent);
    }
    if (control.parentElement?.tagName === "LABEL") parts.push(control.parentElement.textContent);
    return parts.filter(Boolean).join(" ");
  }

  function setNativeValue(element, value) {
    if (element.isContentEditable) {
      element.focus();
      element.textContent = value;
      element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: value }));
      return;
    }
    const prototype = element.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
    setter?.call(element, value);
    element.dispatchEvent(new Event("input", { bubbles: true }));
    element.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function selectClosestOption(select, value) {
    const desired = normalize(value);
    const desiredValues = optionAliases(desired);
    const option = [...select.options].find((item) => {
      const text = normalize(`${item.value} ${item.textContent}`);
      return desiredValues.some((candidate) => text === candidate || text.includes(candidate));
    });
    if (!option) return false;
    if (select.value !== option.value) {
      select.value = option.value;
      select.dispatchEvent(new Event("input", { bubbles: true }));
      select.dispatchEvent(new Event("change", { bubbles: true }));
    }
    return true;
  }

  function fieldCurrentValue(control, field) {
    if (!control) return "";
    if (control.tagName === "SELECT") {
      return control.options[control.selectedIndex]?.textContent || control.value;
    }
    if (control.matches("input, textarea")) return control.value;
    if (control.isContentEditable) return control.textContent;
    const label = normalize(field.label);
    const text = normalize(control.textContent);
    return text.startsWith(label) ? text.slice(label.length).trim() : text;
  }

  function exactOptionValues(value) {
    return optionAliases(normalize(value)).map((candidate) =>
      normalize(candidate).replace(/[\/&]/g, " ").replace(/\s+/g, " ").trim()
    );
  }

  function exactOptionMatches(value, desired) {
    const normalized = normalize(value).replace(/[\/&]/g, " ").replace(/\s+/g, " ").trim();
    return exactOptionValues(desired).includes(normalized);
  }

  async function selectStrictFacebookOption(control, field) {
    if (control.tagName === "SELECT") return selectClosestOption(control, field.value);
    if (control.getAttribute("role") !== "combobox") return false;
    if (strictControlLabel(control) !== normalize(field.label)) return false;
    if (isForbiddenLocationTarget(control) || hasBlockingLocationDialog()) return false;
    if (exactOptionMatches(fieldCurrentValue(control, field), field.value)) return true;

    if (!clickLikeUser(control)) return false;
    await wait(180);
    if (hasBlockingLocationDialog()) return false;
    const desiredValues = exactOptionValues(field.value);
    const option = [...document.querySelectorAll("[role='option']")]
      .filter(isVisible)
      .filter((candidate) => !isForbiddenLocationTarget(candidate))
      .find((candidate) => desiredValues.includes(
        normalize(candidate.textContent || candidate.getAttribute("aria-label"))
          .replace(/[\/&]/g, " ")
          .replace(/\s+/g, " ")
          .trim()
      ));
    if (!option || !clickLikeUser(option)) return false;
    await wait(260);
    const refreshed = findField(field);
    return exactOptionMatches(fieldCurrentValue(refreshed, field), field.value);
  }

  function vehicleIdentityMatches() {
    const yearField = fields.find((field) => field.key === "year");
    const makeField = fields.find((field) => field.key === "make");
    const yearControl = findField(yearField);
    const makeControl = findField(makeField);
    return Boolean(
      yearControl &&
      makeControl &&
      exactOptionMatches(fieldCurrentValue(yearControl, yearField), yearField.value) &&
      exactOptionMatches(fieldCurrentValue(makeControl, makeField), makeField.value)
    );
  }

  function optionAliases(value) {
    const aliases = new Set([value]);
    if (value === "gray") aliases.add("grey");
    if (value === "grey") aliases.add("gray");
    if (value === "pickup truck") {
      aliases.add("pickup");
      aliases.add("truck");
    }
    if (value === "excellent") {
      aliases.add("excellent condition");
    }
    if (value === "gasoline" || value === "gas") {
      aliases.add("gasoline");
      aliases.add("gas");
      aliases.add("petrol");
      aliases.add("regular unleaded");
      aliases.add("unleaded");
    }
    if (value === "diesel") aliases.add("diesel fuel");
    if (value === "hybrid") {
      aliases.add("hybrid");
      aliases.add("hybrid fuel");
    }
    if (value === "electric") {
      aliases.add("electric");
      aliases.add("ev");
    }
    if (value === "car/truck") {
      aliases.add("car truck");
      aliases.add("car or truck");
      aliases.add("cars or trucks");
      aliases.add("car and truck");
      aliases.add("cars and trucks");
      aliases.add("cars & trucks");
    }
    if (value === "powersports") {
      aliases.add("power sports");
      aliases.add("powersport");
      aliases.add("motorcycle");
    }
    return [...aliases];
  }

  function findStrictVehicleTypeControl() {
    const controls = [...document.querySelectorAll("select, button, [role='button'], [role='combobox'], [aria-haspopup]")];
    return controls
      .filter(isVisible)
      .filter((element) => !element.closest("#lotcaster-manual-assist, #walker-helper-notice"))
      .filter((element) => !isForbiddenLocationTarget(element))
      .filter((element) => {
        const direct = normalize([
          element.getAttribute("aria-label"),
          element.getAttribute("aria-placeholder"),
          element.getAttribute("placeholder"),
          element.getAttribute("name"),
          element.getAttribute("title"),
          element.textContent
        ].filter(Boolean).join(" "));
        const label = element.closest("label");
        const labelText = normalize(label?.textContent);
        return direct.length <= 100 && /\bvehicle type\b/.test(direct) ||
          labelText.length <= 120 && /\bvehicle type\b/.test(labelText);
      })
      .sort((a, b) => elementScore(b) - elementScore(a))[0] || null;
  }

  function findListingTypeOption(desiredValues) {
    return [...document.querySelectorAll("[role='option'], [role='menuitem'], [role='radio'], button, [role='button']")]
      .filter(isVisible)
      .filter((element) => !element.closest("#lotcaster-manual-assist, #walker-helper-notice"))
      .find((element) => {
        const text = normalize(element.textContent || element.getAttribute("aria-label"));
        return text.length <= 90 && matchesAnyOption(text, desiredValues);
      }) || null;
  }

  function hasVehicleDetailFields() {
    return fields.filter((field) => field.value && findField(field)).length >= 2;
  }

  function hasBlockingLocationDialog() {
    return [...document.querySelectorAll("[role='dialog'], [aria-modal='true']")]
      .filter(isVisible)
      .some((dialog) => /\blisting location\b|\blocation proximity\b/.test(normalize(dialog.textContent)));
  }

  function findExplicitListingTypeControl() {
    const selectors = [
      "[aria-label*='vehicle type' i]",
      "[aria-label*='listing type' i]",
      "[aria-placeholder*='vehicle type' i]",
      "[placeholder*='vehicle type' i]",
      "[name*='vehicleType' i]",
      "[name*='listingType' i]"
    ];
    return [...document.querySelectorAll(selectors.join(","))]
      .filter(isVisible)
      .filter((element) => !element.closest("#lotcaster-manual-assist, #walker-helper-notice"))
      .filter((element) => !/body style|fuel type|condition/.test(normalize(compactElementText(element))))
      .sort((a, b) => elementScore(b) - elementScore(a))[0] || null;
  }

  function isListingTypeSelected(desired = listingType) {
    const field = { label: "Vehicle type", value: desired };
    const control = findField(field);
    return Boolean(control && exactOptionMatches(fieldCurrentValue(control, field), desired));
  }

  function findInitialListingTypeControl() {
    const controls = [...document.querySelectorAll("select, input, [role='combobox'], [aria-haspopup], [role='button'], button")];
    return controls
      .filter((control) => {
      if (!isVisible(control)) return false;
      const text = compactElementText(control).toLowerCase();
        const isInitialTypeLabel = /listing type|type of listing|what are you listing|choose listing type|vehicle type|type of vehicle|select vehicle type/.test(text);
        const isLaterVehicleField = /body style|fuel type|condition|exterior|interior|make|model|year|mileage|odometer|vin|price/.test(text);
        return isInitialTypeLabel && !isLaterVehicleField;
      })
      .sort((a, b) => elementScore(b) - elementScore(a))[0] || null;
  }

  function controlHasListingTypeSignal(control) {
    if (control.tagName === "SELECT") {
      const optionText = [...control.options].map((option) => option.textContent || option.value).join(" ");
      return /car(?:s)?\s*(?:\/|&|and|or)?\s*truck(?:s)?|powersports/i.test(optionText);
    }
    const text = compactElementText(control);
    return /car(?:s)?\s*(?:\/|&|and|or)?\s*truck(?:s)?|powersports|vehicle type|listing type/i.test(text);
  }

  function elementText(element) {
    return String(element.textContent || element.getAttribute("aria-label") || element.getAttribute("title") || "").trim();
  }

  function compactElementText(element) {
    const parts = [
      element.getAttribute?.("aria-label"),
      element.getAttribute?.("aria-placeholder"),
      element.getAttribute?.("placeholder"),
      element.getAttribute?.("title"),
      element.getAttribute?.("name"),
      element.textContent
    ];
    let parent = element.parentElement;
    for (let level = 0; parent && level < 2; level += 1, parent = parent.parentElement) {
      const text = parent.textContent || "";
      if (text.length <= 220) parts.push(text);
    }
    return parts.filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
  }

  function findListingTypeOpener() {
    const candidates = [...document.querySelectorAll("button, [role='button'], [role='combobox'], [aria-haspopup], label, div, span")]
      .filter(isVisible)
      .filter((element) => {
        const text = compactElementText(element).toLowerCase();
        return /vehicle type|listing type|type of vehicle|what are you listing|choose listing type|select vehicle type/.test(text)
          && !/body style|fuel type|condition|exterior|interior|make|model|year|mileage|odometer|vin|price/.test(text);
      });
    const best = candidates.sort((a, b) => elementScore(b) - elementScore(a))[0];
    return best ? clickableAncestor(best) : null;
  }

  function findVehicleTypeCard() {
    const candidates = [...document.querySelectorAll("div, span, label, button, [role='button'], [role='combobox']")]
      .filter(isVisible)
      .filter((element) => {
        const text = normalize(compactElementText(element));
        const rect = element.getBoundingClientRect();
        return text.length <= 180
          && rect.height <= 180
          && /vehicle type|listing type|type of vehicle|select vehicle type/.test(text)
          && !/body style|fuel type|condition|exterior|interior|make|model|year|mileage|odometer|vin|price/.test(text);
      })
      .sort((a, b) => elementScore(b) - elementScore(a));
    return candidates[0] ? clickableAncestor(candidates[0]) : null;
  }

  function findVisibleOption(desiredValues, options = {}) {
    const { requireMenuContext = false } = options;
    const optionSelector = [
      "[role='option']",
      "[role='menuitem']",
      "[role='radio']",
      "[role='button']",
      "button",
      "span",
      "div"
    ].join(",");
    return [...document.querySelectorAll(optionSelector)]
      .filter(isVisible)
      .filter((option) => !option.closest("#lotcaster-manual-assist, #walker-helper-notice"))
      .find((option) => {
        if (requireMenuContext && !option.matches("[role='option'], [role='menuitem'], [role='radio'], button, [role='button']")) return false;
        const text = normalize(elementText(option));
        return text.length <= 90 && matchesAnyOption(text, desiredValues);
      }) || null;
  }

  function isMenuLikeOption(element) {
    const text = normalize(elementText(element));
    if (!text || text.length > 80) return false;
    return /car(?:s)?\s*(?:\/|&|and|or)?\s*truck(?:s)?|powersports/.test(text);
  }

  function elementScore(element) {
    const role = element.getAttribute("role") || "";
    const text = compactElementText(element).toLowerCase();
    let score = 0;
    if (/combobox|button/.test(role)) score += 4;
    if (element.tagName === "BUTTON" || element.tagName === "SELECT") score += 4;
    if (/vehicle type|listing type|type of vehicle/.test(text)) score += 5;
    if (/car(?:s)?\s*(?:\/|&|and|or)?\s*truck(?:s)?|powersports/.test(text)) score += 2;
    return score;
  }

  function matchesAnyOption(text, desiredValues) {
    const normalizedText = normalize(text).replace(/[\/&]/g, " ").replace(/\s+/g, " ").trim();
    return desiredValues.some((candidate) => {
      const normalizedCandidate = normalize(candidate).replace(/[\/&]/g, " ").replace(/\s+/g, " ").trim();
      return normalizedText === normalizedCandidate ||
        normalizedText.includes(normalizedCandidate) ||
        normalizedCandidate.includes(normalizedText);
    });
  }

  function clickableAncestor(element) {
    let current = element;
    for (let level = 0; current && level < 4; level += 1, current = current.parentElement) {
      if (current.matches?.("button, [role='button'], [role='combobox'], [aria-haspopup], select, input")) return current;
    }
    return element;
  }

  function clickLikeUser(element) {
    if (!element || isForbiddenLocationTarget(element) || hasBlockingLocationDialog()) return false;
    element.scrollIntoView?.({ block: "center", inline: "center" });
    element.focus?.();
    try {
      element.click?.();
    } catch {
      // Facebook sometimes handles synthetic pointer events and sometimes native click.
    }
    return true;
  }

  function isForbiddenLocationTarget(element) {
    let current = element;
    for (let level = 0; current && level < 3; level += 1, current = current.parentElement) {
      const direct = normalize([
        current.getAttribute?.("aria-label"),
        current.getAttribute?.("title"),
        current.getAttribute?.("name"),
        current.getAttribute?.("placeholder"),
        current.matches?.("button, [role='button'], [role='combobox'], [aria-haspopup]") ? current.textContent : ""
      ].filter(Boolean).join(" "));
      if (/\blisting location\b|\bchange location\b|\blocation proximity\b/.test(direct)) return true;
    }
    return false;
  }

  function schedulePhotoAttach(urls) {
    let attempts = 0;
    const tryAttach = async () => {
      attempts += 1;
      const attached = await attachPhotos(urls);
      if (attached) {
        showNotice(`LotCaster attached ${attached} verified vehicle photo${attached === 1 ? "" : "s"}.`);
      } else if (attempts < 30) {
        window.setTimeout(tryAttach, 1000);
      } else {
        showNotice("LotCaster could not attach a valid vehicle photo. The listing can still be completed manually.", true);
      }
    };
    window.setTimeout(tryAttach, 250);
  }

  function hideHelperOverlays() {
    document.querySelector("#lotcaster-manual-assist")?.remove();
    document.querySelector("#walker-helper-notice")?.remove();
  }

  async function fillVisibleDetails() {
    let count = 0;
    for (const field of fields) {
      if (!field.value) continue;
      if (field.requiresIdentity && !vehicleIdentityMatches()) continue;
      const element = findField(field);
      if (!element) continue;
      const filled = field.exactOption
        ? await selectStrictFacebookOption(element, field)
        : await fillControl(element, field.value);
      if (filled) count += 1;
      await wait(35);
    }
    if (count && (vehicle.images?.length || vehicle.image)) schedulePhotoAttach(vehicle.images || [vehicle.image]);
    return count;
  }

  async function attachPhotos(urls) {
    if (document.documentElement.dataset.walkerPhotoAttempted) {
      return Number(document.documentElement.dataset.walkerPhotoCount || 0);
    }
    if (document.documentElement.dataset.walkerPhotoInProgress) return 0;
    const inputs = [...document.querySelectorAll('input[type="file"]')];
    const input =
      inputs.find((candidate) => candidate.multiple && /image/i.test(candidate.accept || "")) ||
      inputs.find((candidate) => candidate.multiple) ||
      inputs.find((candidate) => /image/i.test(candidate.accept || ""));
    if (!input) return 0;
    document.documentElement.dataset.walkerPhotoInProgress = "true";
    try {
      const transfer = new DataTransfer();
      const limitedUrls = [...new Set(urls.filter(Boolean))].slice(0, 8);
      for (let index = 0; index < limitedUrls.length; index += 1) {
        const result = await chrome.runtime.sendMessage({ type: "walker-fetch-image", url: limitedUrls[index] });
        if (!result || result.error || !result.bytes || !/^image\/(?:jpeg|png|webp)(?:;|$)/i.test(result.contentType || "")) continue;
        const type = result.contentType || "image/jpeg";
        const extension = type.includes("png") ? "png" : "jpg";
        transfer.items.add(new File([new Uint8Array(result.bytes)], `lotcaster-vehicle-${index + 1}.${extension}`, { type }));
      }
      if (!transfer.files.length) return 0;
      input.setAttribute("multiple", "");
      input.files = transfer.files;
      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
      document.documentElement.dataset.walkerPhotoCount = String(transfer.files.length);
      document.documentElement.dataset.walkerPhotoAttempted = "true";
      return transfer.files.length;
    } catch {
      return 0;
    } finally {
      delete document.documentElement.dataset.walkerPhotoInProgress;
    }
  }

  function finish(message, isError) {
    completed = true;
    observer.disconnect();
    window.clearInterval(interval);
    window.clearTimeout(debounceTimer);
    if (!isError) sessionStorage.removeItem(STORAGE_KEY);
    showNotice(message, isError);
  }

  function normalize(value) {
    return String(value || "").trim().toLowerCase().replace(/\s+/g, " ");
  }

  function wait(milliseconds) {
    return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
  }

  function escapeRegex(value) {
    return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  function showNotice(message, isError = false) {
    let notice = document.querySelector("#walker-helper-notice");
    if (!notice) {
      notice = document.createElement("div");
      notice.id = "walker-helper-notice";
      Object.assign(notice.style, {
        position: "fixed",
        right: "18px",
        bottom: "18px",
        zIndex: "2147483647",
        maxWidth: "380px",
        padding: "14px 16px",
        borderRadius: "8px",
        color: "white",
        font: "600 14px/1.4 system-ui, sans-serif",
        boxShadow: "0 8px 28px rgba(0,0,0,.28)"
      });
      document.body.append(notice);
    }
    notice.style.background = isError ? "#9f1239" : "#17603a";
    if (notice.textContent !== message) notice.textContent = message;
  }
})();

