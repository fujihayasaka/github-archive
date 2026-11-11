import { chromium } from 'playwright';

// Test config from env
const LOGIN = process.env.CTA_LOGIN;
const INDICATOR_ENDPOINT = process.env.INDICATOR_ENDPOINT;
const EXPECTED_FIELDS = (process.env.EXPECTED_FIELDS || '').split(',').map(f => f.trim()).filter(Boolean);
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
  try {
    await page.screenshot({ path, fullPage: true });
  } catch (e) {
    console.log(JSON.stringify({ type: 'warning', message: `Screenshot failed: ${e.message}` }));
  }
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
    log(`\n===== INDICATOR TEST: ${NUDGE_NAME} =====`);
    log(`Account: ${LOGIN}`);
    log(`Endpoint: ${INDICATOR_ENDPOINT}`);
    log(`Expected fields: ${EXPECTED_FIELDS.join(', ')}`);

    // ======= LOGIN =======
    log('\n--- Login ---');
    await login(context, page, LOGIN);

    // ======= CHECK 1: Fetch JSON endpoint =======
    log('\n--- Check 1: Fetch Indicator Endpoint ---');

    const response = await page.evaluate(async (url) => {
      const res = await fetch(url, {
        credentials: 'same-origin',
        headers: { 'Accept': 'application/json' },
      });
      let body = null;
      try {
        body = await res.json();
      } catch (e) {
        const text = await res.text().catch(() => '');
        body = { _parseError: e.message, _rawText: text.slice(0, 500) };
      }
      return {
        status: res.status,
        body,
      };
    }, `${BASE_URL}${INDICATOR_ENDPOINT}`);

    await screenshot(page, `${LOGIN}-after-fetch`);
    log(`Response status: ${response.status}`);
    log(`Response body: ${JSON.stringify(response.body)}`);

    if (response.status !== 200) {
      log(`❌ INDICATOR: Expected status 200 but got ${response.status}`);
      allFieldsPass = false;
    } else {
      log(`✅ INDICATOR: Endpoint returned 200`);
    }

    // ======= CHECK 2: Validate expected fields are true =======
    log('\n--- Check 2: Validate Expected Fields ---');
    let allFieldsPass = true;
    for (const field of EXPECTED_FIELDS) {
      if (response.body[field] === true) {
        log(`✅ FIELD: ${field} = true`);
      } else {
        log(`❌ FIELD: ${field} = ${JSON.stringify(response.body[field])} (expected true)`);
        allFieldsPass = false;
      }
    }

    // ======= CHECK 3: Verify "New" badge in profile nav drawer =======
    log('\n--- Check 3: Verify "New" Badge in Profile Nav ---');
    const isEnterprise = INDICATOR_ENDPOINT.includes('enterprise');
    const navLinkText = isEnterprise ? 'Enterprises' : 'Organizations';

    // Navigate to dashboard so we have a clean page with the global nav
    await page.goto(`${BASE_URL}/`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    // Wait for the async indicator fetch to complete before opening the drawer
    await page.waitForTimeout(5000);

    // Open the profile/user navigation menu (avatar button in top-right)
    // The menu is a dropdown that appears when the avatar is clicked.
    // We verify it actually opened by checking for a visible nav link (e.g. "Profile", "Settings").
    const avatarSelectors = [
      'button:has(img[alt="User avatar"])',
      'button:has(img.avatar)',
      'button[aria-label="Open user navigation menu"]',
      'button.AppHeader-user',
      'deferred-side-panel button[data-target="deferred-side-panel.showPanelButton"]',
    ];

    // Menu-open indicators: any of these visible means the dropdown is open
    const menuOpenSelector = 'a:has-text("Profile"), a:has-text("Settings"), a:has-text("Sign out")';

    let navOpened = false;
    const MAX_ATTEMPTS = 3;
    for (let attempt = 1; attempt <= MAX_ATTEMPTS && !navOpened; attempt++) {
      for (const sel of avatarSelectors) {
        if (navOpened) break;
        try {
          const btn = page.locator(sel).first();
          if (await btn.isVisible({ timeout: 2000 })) {
            await btn.click();
            // Wait for menu to actually appear
            try {
              await page.locator(menuOpenSelector).first().waitFor({ state: 'visible', timeout: 3000 });
              navOpened = true;
              log(`NAV DRAWER: Opened via ${sel} (attempt ${attempt})`);
            } catch (e) {
              // Menu didn't appear — click might have toggled it closed or missed
              log(`⚠️ NAV DRAWER: Click on ${sel} did not open menu (attempt ${attempt})`);
            }
          }
        } catch (e) { /* try next */ }
      }
      if (!navOpened && attempt < MAX_ATTEMPTS) {
        await page.waitForTimeout(2000);
      }
    }

    // Helper: open the nav drawer and return whether it opened
    async function openNavDrawer() {
      for (const sel of avatarSelectors) {
        try {
          const btn = page.locator(sel).first();
          if (await btn.isVisible({ timeout: 2000 })) {
            await btn.click();
            try {
              await page.locator(menuOpenSelector).first().waitFor({ state: 'visible', timeout: 3000 });
              return sel;
            } catch (e) { /* try next */ }
          }
        } catch (e) { /* try next */ }
      }
      return null;
    }

    // Helper: check for the "New" badge next to the nav link
    async function checkForBadge() {
      // Strategy 1: data-testid="new-task-label" anchored to the correct link
      try {
        const badgeAnchor = page.locator(`a:has([data-testid="new-task-label"])`).filter({ hasText: navLinkText }).first();
        if (await badgeAnchor.isVisible({ timeout: 5000 })) {
          return 'data-testid';
        }
      } catch (e) { /* fall through */ }

      // Strategy 2: innerText of the nav link contains "New"
      try {
        const navLink = page.locator('a').filter({ hasText: navLinkText }).first();
        if (await navLink.isVisible({ timeout: 2000 })) {
          const linkText = await navLink.innerText();
          if (/\bNew\b/.test(linkText)) {
            return 'innerText';
          }
        }
      } catch (e) { /* fall through */ }

      return null;
    }

    // Retry loop: the badge is async-loaded so it may not appear immediately.
    // On each attempt: open drawer → wait for badge (with increasing patience) → if not found, close drawer, wait, reload, try again.
    const BADGE_ATTEMPTS = 3;
    let foundNewBadge = false;
    let badgeMethod = null;

    if (!navOpened) {
      log(`❌ NAV DRAWER: Could not open the profile menu after ${MAX_ATTEMPTS} attempts`);
      await screenshot(page, `${LOGIN}-nav-drawer-failed`);
    } else {
      for (let badgeAttempt = 1; badgeAttempt <= BADGE_ATTEMPTS; badgeAttempt++) {
        if (badgeAttempt > 1) {
          // Close drawer, wait, reload, re-open
          log(`⚠️ NEW BADGE: Not found on attempt ${badgeAttempt - 1}, reloading page and retrying...`);
          await page.keyboard.press('Escape');
          await page.waitForTimeout(1000);
          await page.goto(`${BASE_URL}/`, { waitUntil: 'domcontentloaded', timeout: 30000 });
          // Give the page more time to settle and the async indicator to load
          await page.waitForTimeout(3000 + badgeAttempt * 2000);

          const sel = await openNavDrawer();
          if (!sel) {
            log(`⚠️ NAV DRAWER: Could not re-open on attempt ${badgeAttempt}`);
            continue;
          }
          log(`NAV DRAWER: Re-opened via ${sel} (badge attempt ${badgeAttempt})`);
        }

        await screenshot(page, `${LOGIN}-nav-drawer-open${badgeAttempt > 1 ? `-attempt-${badgeAttempt}` : ''}`);
        badgeMethod = await checkForBadge();
        if (badgeMethod) {
          foundNewBadge = true;
          break;
        }
      }

      // Check if the nav link itself is at least visible
      try {
        const navLink = page.locator('a').filter({ hasText: navLinkText }).first();
        if (await navLink.isVisible({ timeout: 2000 })) {
          log(`✅ NAV LINK: "${navLinkText}" found in profile nav`);
        } else {
          log(`❌ NAV LINK: "${navLinkText}" NOT found in profile nav`);
        }
      } catch (e) { /* skip */ }

      if (foundNewBadge) {
        log(`✅ NEW BADGE: "New" badge found next to "${navLinkText}" (via ${badgeMethod})`);
      } else {
        log(`❌ NEW BADGE: "New" badge NOT found next to "${navLinkText}" after ${BADGE_ATTEMPTS} attempts`);
        allFieldsPass = false;
      }
    }

    // ======= SUMMARY =======
    log(`\n===== END ${NUDGE_NAME} =====`);

    console.log(JSON.stringify({ type: 'result', success: allFieldsPass, message: 'All checks completed', results }));
  } catch (error) {
    await screenshot(page, 'error');
    log(`\n❌ FATAL: ${error.message}`);
    console.log(JSON.stringify({
      type: 'result',
      success: false,
      message: error.message,
      stack: error.stack,
      results
    }));
  } finally {
    await context.close();
    await browser.close();
  }
})();
