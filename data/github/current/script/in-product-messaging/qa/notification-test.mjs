import { chromium } from 'playwright';

// Test config from env
const LOGIN = process.env.CTA_LOGIN;
const TEST_PAGE = process.env.TEST_PAGE;
const SECTION_TEXT = (process.env.SECTION_TEXT || 'In-product messages').replace(/_/g, ' ');
const TOGGLE_TYPE = process.env.TOGGLE_TYPE || 'primer-switch'; // 'checkbox', 'primer-switch', or 'primer-react'
const NUDGE_NAME = process.env.NUDGE_NAME || 'unknown';
const PASSWORD = 'passworD1';
const BASE_URL = 'http://github.localhost';

const SCREENSHOTS_DIR = process.env.SCREENSHOTS_DIR || './screenshots';
const VIDEOS_DIR = process.env.VIDEOS_DIR || './videos';

let stepNum = 0;
const results = [];

async function screenshot(page, label) {
  stepNum++;
  const name = `step-${String(stepNum).padStart(2, '0')}-${label}.png`;
  const path = `${SCREENSHOTS_DIR}/${name}`;
  try { await page.screenshot({ path, fullPage: true }); } catch (e) {}
  console.log(JSON.stringify({ type: 'screenshot', step: stepNum, label, path }));
}

function log(msg) {
  console.log(JSON.stringify({ type: 'log', message: msg }));
  results.push(msg);
}

async function login(context, page, username) {
  await context.clearCookies();
  await page.goto(`${BASE_URL}/login`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(1000);
  await page.locator('#login_field').fill('');
  await page.locator('#login_field').type(username, { delay: 50 });
  await page.locator('#password').fill('');
  await page.locator('#password').type(PASSWORD, { delay: 50 });
  await page.locator('input[type="submit"], input[name="commit"]').first().click();
  await page.waitForLoadState('domcontentloaded', { timeout: 30000 });
  await page.waitForTimeout(2000);

  // Handle device verification
  if (page.url().includes('/sessions/verified-device')) {
    try {
      await page.getByRole('button', { name: /verify/i }).click({ timeout: 5000 });
      await page.waitForLoadState('domcontentloaded', { timeout: 15000 });
      await page.waitForTimeout(2000);
    } catch (e) {
      try {
        await page.locator('button:has-text("Verify"), input[type="submit"]').first().click({ timeout: 5000 });
        await page.waitForLoadState('domcontentloaded', { timeout: 15000 });
        await page.waitForTimeout(2000);
      } catch (e2) { /* continue */ }
    }
  }
  await screenshot(page, `${username}-login-success`);
}

// ---------------------------------------------------------------------------
// Toggle helpers — supports checkbox, Primer <toggle-switch>, and Primer React toggles
// ---------------------------------------------------------------------------

// For TOGGLE_TYPE=primer-switch: find by data-test-selector
async function findPrimerToggle(page, labelText) {
  const selectors = {
    'Promotions': 'toggle-switch[data-test-selector="in-product-messaging-promotions-toggle"]',
    'Tips': 'toggle-switch[data-test-selector="in-product-messaging-tips-toggle"]',
  };
  const sel = selectors[labelText];
  if (!sel) return null;

  const el = page.locator(sel).first();
  if (!(await el.isVisible({ timeout: 3000 }).catch(() => false))) return null;

  const btn = el.locator('button').first();
  if (await btn.isVisible({ timeout: 2000 }).catch(() => false)) {
    return { container: el, button: btn };
  }
  return { container: el, button: el };
}

async function isPrimerToggleOn(toggle) {
  const cls = await toggle.container.getAttribute('class').catch(() => '');
  return cls.includes('ToggleSwitch--checked');
}

// For TOGGLE_TYPE=primer-react: Primer React ToggleSwitch (<button aria-pressed>)
// Found by locating the section heading, then navigating to the button within its parent container
async function findPrimerReactToggle(page, sectionText) {
  // Wait for React to render — Primer React toggles load asynchronously
  await page.waitForTimeout(5000);

  // Strategy 1: Find button[aria-pressed] near the section text using DOM traversal
  // The section heading and toggle live in the same container
  const sectionEl = page.getByText(sectionText, { exact: false }).first();
  const sectionVisible = await sectionEl.isVisible({ timeout: 10000 }).catch(() => false);
  if (sectionVisible) {
    // Look for a toggle button in the closest parent container
    const btn = page.locator(`button[aria-pressed]`).first();
    if (await btn.isVisible({ timeout: 10000 }).catch(() => false)) {
      return btn;
    }
  }

  // Strategy 2: Find any button with aria-pressed attribute (generic Primer React toggle)
  const anyToggle = page.locator('button[aria-pressed]').first();
  if (await anyToggle.isVisible({ timeout: 10000 }).catch(() => false)) {
    return anyToggle;
  }

  // Strategy 3: CSS class prefix match (handles hash suffix changes)
  const prefixMatch = page.locator('[class*="ToggleSwitch"] button').first();
  if (await prefixMatch.isVisible({ timeout: 5000 }).catch(() => false)) {
    return prefixMatch;
  }

  return null;
}

async function isPrimerReactToggleOn(btn) {
  const pressed = await btn.getAttribute('aria-pressed').catch(() => 'false');
  return pressed === 'true';
}

// For TOGGLE_TYPE=checkbox: find checkbox near the section heading
async function findCheckboxToggle(page, sectionText) {
  const section = page.locator('section, div, fieldset').filter({ hasText: sectionText });
  const checkboxes = section.locator('input[type="checkbox"]');
  const count = await checkboxes.count();
  for (let i = 0; i < count; i++) {
    const cb = checkboxes.nth(i);
    if (await cb.isVisible({ timeout: 2000 }).catch(() => false)) {
      return cb;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Test: dual toggles (Promotions + Tips) — org/enterprise opt-out pages
// ---------------------------------------------------------------------------
async function testDualToggles(page) {
  const promoToggle = await findPrimerToggle(page, 'Promotions');
  const tipsToggle = await findPrimerToggle(page, 'Tips');

  if (!promoToggle) { log(`❌ Promotions toggle not found`); return false; }
  if (!tipsToggle) { log(`❌ Tips toggle not found`); return false; }

  let allPassed = true;

  // Check initial state (should be ON)
  const promoOn = await isPrimerToggleOn(promoToggle);
  const tipsOn = await isPrimerToggleOn(tipsToggle);
  log(`Promotions initial: ${promoOn ? 'ON' : 'OFF'} | Tips initial: ${tipsOn ? 'ON' : 'OFF'}`);
  if (promoOn) log(`✅ Promotions defaults to ON`);
  else { log(`⚠️ Promotions defaults to OFF`); allPassed = false; }
  if (tipsOn) log(`✅ Tips defaults to ON`);
  else { log(`⚠️ Tips defaults to OFF`); allPassed = false; }

  // Toggle Promotions OFF
  await promoToggle.button.click();
  await page.waitForTimeout(2000);
  await screenshot(page, `${LOGIN}-promotions-off`);
  const promoAfter = await isPrimerToggleOn(promoToggle);
  if (!promoAfter) log(`✅ Promotions toggled OFF`);
  else { log(`❌ Promotions did not toggle OFF`); allPassed = false; }

  // Toggle Tips OFF
  await tipsToggle.button.click();
  await page.waitForTimeout(2000);
  await screenshot(page, `${LOGIN}-tips-off`);
  const tipsAfter = await isPrimerToggleOn(tipsToggle);
  if (!tipsAfter) log(`✅ Tips toggled OFF`);
  else { log(`❌ Tips did not toggle OFF`); allPassed = false; }

  // Reload and verify persistence
  await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(3000);
  await screenshot(page, `${LOGIN}-after-reload`);

  const promoReload = await findPrimerToggle(page, 'Promotions');
  const tipsReload = await findPrimerToggle(page, 'Tips');
  if (promoReload && tipsReload) {
    const promoPersist = await isPrimerToggleOn(promoReload);
    const tipsPersist = await isPrimerToggleOn(tipsReload);
    log(`After reload — Promotions: ${promoPersist ? 'ON' : 'OFF'}, Tips: ${tipsPersist ? 'ON' : 'OFF'}`);
    if (!promoPersist && !tipsPersist) {
      log(`✅ Both toggles persist as OFF after reload`);
    } else {
      log(`❌ Toggle persistence failed`);
      allPassed = false;
    }

    // Toggle both back ON
    await promoReload.button.click();
    await page.waitForTimeout(1000);
    await tipsReload.button.click();
    await page.waitForTimeout(2000);
    await screenshot(page, `${LOGIN}-both-on`);
    const promoFinal = await isPrimerToggleOn(promoReload);
    const tipsFinal = await isPrimerToggleOn(tipsReload);
    if (promoFinal && tipsFinal) {
      log(`✅ Both toggles switched back to ON`);
    } else {
      log(`❌ Toggle re-enable failed — Promotions: ${promoFinal ? 'ON' : 'OFF'}, Tips: ${tipsFinal ? 'ON' : 'OFF'}`);
      allPassed = false;
    }
  }

  return allPassed;
}

// ---------------------------------------------------------------------------
// Test: single checkbox toggle — user notification settings page
// ---------------------------------------------------------------------------
async function testSingleCheckbox(page) {
  const toggle = await findCheckboxToggle(page, SECTION_TEXT);
  if (!toggle) {
    log(`❌ Toggle not found near "${SECTION_TEXT}" section`);
    return false;
  }

  let allPassed = true;

  // Check initial state (should be ON)
  const isChecked = await toggle.isChecked().catch(() => null);
  log(`Toggle initial state: ${isChecked ? 'ON' : 'OFF'}`);
  if (isChecked) log(`✅ Toggle defaults to ON (opted-in)`);
  else { log(`⚠️ Toggle defaults to OFF — expected ON`); allPassed = false; }

  // Toggle OFF
  await toggle.click();
  await page.waitForTimeout(2000);
  await screenshot(page, `${LOGIN}-toggle-off`);
  const afterOff = await toggle.isChecked().catch(() => null);
  if (!afterOff) log(`✅ Toggle switched to OFF`);
  else { log(`❌ Toggle did not switch to OFF`); allPassed = false; }

  // Reload and verify persistence
  await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(3000);
  await screenshot(page, `${LOGIN}-after-reload`);

  const reloadToggle = await findCheckboxToggle(page, SECTION_TEXT);
  if (reloadToggle) {
    const persistedOff = await reloadToggle.isChecked().catch(() => null);
    if (!persistedOff) log(`✅ Toggle persists as OFF after reload`);
    else { log(`❌ Toggle did not persist as OFF`); allPassed = false; }

    // Toggle back ON
    await reloadToggle.click();
    await page.waitForTimeout(2000);
    await screenshot(page, `${LOGIN}-toggle-on`);
    const afterOn = await reloadToggle.isChecked().catch(() => null);
    if (afterOn) log(`✅ Toggle switched back to ON`);
    else { log(`❌ Toggle did not switch back to ON`); allPassed = false; }
  }

  return allPassed;
}

// ---------------------------------------------------------------------------
// Test: single Primer React toggle — user notification settings page
// ---------------------------------------------------------------------------
async function testSinglePrimerReact(page) {
  const btn = await findPrimerReactToggle(page, SECTION_TEXT);
  if (!btn) {
    log(`❌ Primer React toggle not found near "${SECTION_TEXT}" section`);
    return false;
  }

  let allPassed = true;

  // Check initial state (should be ON)
  const isOn = await isPrimerReactToggleOn(btn);
  log(`Toggle initial state: ${isOn ? 'ON' : 'OFF'}`);
  if (isOn) log(`✅ Toggle defaults to ON (opted-in)`);
  else { log(`⚠️ Toggle defaults to OFF — expected ON`); allPassed = false; }

  // Toggle OFF
  await btn.click();
  await page.waitForTimeout(2000);
  await screenshot(page, `${LOGIN}-toggle-off`);
  const afterOff = await isPrimerReactToggleOn(btn);
  if (!afterOff) log(`✅ Toggle switched to OFF`);
  else { log(`❌ Toggle did not switch to OFF`); allPassed = false; }

  // Reload and verify persistence
  await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(3000);
  await screenshot(page, `${LOGIN}-after-reload`);

  const reloadBtn = await findPrimerReactToggle(page, SECTION_TEXT);
  if (reloadBtn) {
    const persistedOff = await isPrimerReactToggleOn(reloadBtn);
    if (!persistedOff) log(`✅ Toggle persists as OFF after reload`);
    else { log(`❌ Toggle did not persist as OFF`); allPassed = false; }

    // Toggle back ON
    await reloadBtn.click();
    await page.waitForTimeout(2000);
    await screenshot(page, `${LOGIN}-toggle-on`);
    const afterOn = await isPrimerReactToggleOn(reloadBtn);
    if (afterOn) log(`✅ Toggle switched back to ON`);
    else { log(`❌ Toggle did not switch back to ON`); allPassed = false; }
  }

  return allPassed;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 720 },
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    recordVideo: { dir: VIDEOS_DIR, size: { width: 1280, height: 720 } },
    ignoreHTTPSErrors: true,
  });
  const page = await context.newPage();

  try {
    log(`\n===== NOTIFICATION TEST: ${NUDGE_NAME} =====`);
    log(`Account: ${LOGIN} | Page: ${TEST_PAGE}`);
    log(`Section: "${SECTION_TEXT}" | Toggle type: ${TOGGLE_TYPE}`);

    await login(context, page, LOGIN);
    await page.goto(`${BASE_URL}${TEST_PAGE}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(5000); // React components need time to render
    await screenshot(page, `${LOGIN}-page-loaded`);

    // Find the section heading
    const sectionEl = page.getByText(SECTION_TEXT, { exact: false }).first();
    let sectionVisible = await sectionEl.isVisible({ timeout: 5000 }).catch(() => false);

    if (!sectionVisible) {
      await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
      await page.waitForTimeout(2000);
      await screenshot(page, `${LOGIN}-scrolled`);
      sectionVisible = await sectionEl.isVisible({ timeout: 5000 }).catch(() => false);
    }

    if (!sectionVisible) {
      log(`❌ "${SECTION_TEXT}" section not found on ${TEST_PAGE}`);
      console.log(JSON.stringify({ type: 'result', success: false, message: `Section not found: ${SECTION_TEXT}`, results }));
    } else {
      log(`✅ "${SECTION_TEXT}" section found`);
      await sectionEl.scrollIntoViewIfNeeded();
      await page.waitForTimeout(1000);

      let allPassed;
      if (TOGGLE_TYPE === 'checkbox') {
        allPassed = await testSingleCheckbox(page);
      } else if (TOGGLE_TYPE === 'primer-react') {
        allPassed = await testSinglePrimerReact(page);
      } else {
        allPassed = await testDualToggles(page);
      }

      // Full page scroll for final screenshot
      await page.evaluate(async () => {
        await new Promise(resolve => {
          let totalHeight = 0;
          const distance = 300;
          const timer = setInterval(() => {
            window.scrollBy(0, distance);
            totalHeight += distance;
            if (totalHeight >= document.body.scrollHeight) { clearInterval(timer); resolve(); }
          }, 100);
        });
      });
      await screenshot(page, `${LOGIN}-full-page-scroll`);

      log(`\n===== END ${NUDGE_NAME} =====`);
      console.log(JSON.stringify({ type: 'result', success: allPassed, message: 'All checks completed', results }));
    }
  } catch (error) {
    await screenshot(page, 'error');
    log(`\n❌ FATAL: ${error.message}`);
    console.log(JSON.stringify({
      type: 'result',
      success: false,
      message: error.message,
      stack: error.stack,
      results,
    }));
  } finally {
    await context.close();
    await browser.close();
  }
})();
