import { chromium } from 'playwright';

// Test config from env
const CTA_LOGIN = process.env.CTA_LOGIN;
const DISMISS_LOGIN = process.env.DISMISS_LOGIN;
const TEST_PAGE = process.env.TEST_PAGE;
const DISMISS_TEST_PAGE = process.env.DISMISS_TEST_PAGE || TEST_PAGE;
const EXPECTED_CTA = (process.env.EXPECTED_CTA || '').replace(/_/g, ' ');
const EXPECTED_DESTINATION = process.env.EXPECTED_DESTINATION || '';
const DISMISS_TYPE = process.env.DISMISS_TYPE || 'standard';  // 'standard' or 'dismiss-and-redirect'
const NUDGE_NAME = process.env.NUDGE_NAME || 'unknown';
const PASSWORD = 'passworD1';
const BASE_URL = 'http://github.localhost';

const SCREENSHOTS_DIR = process.env.SCREENSHOTS_DIR || './screenshots';
const VIDEOS_DIR = process.env.VIDEOS_DIR || './videos';
const STORAGE_STATE = process.env.STORAGE_STATE || null;

let stepNum = 0;
const results = [];
const consoleErrors = [];

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
  // Clear localStorage/sessionStorage to prevent dismiss state from bleeding between accounts
  await page.goto(`${BASE_URL}/login`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.evaluate(() => {
    try { localStorage.clear(); } catch (e) {}
    try { sessionStorage.clear(); } catch (e) {}
  });
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
      // Try alternative
      try {
        await page.locator('button:has-text("Verify"), input[type="submit"]').first().click({ timeout: 5000 });
        await page.waitForLoadState('domcontentloaded', { timeout: 15000 });
        await page.waitForTimeout(2000);
      } catch (e2) { /* continue */ }
    }
  }
  await screenshot(page, `${username}-login-success`);
}

async function findCTA(page, timeout = 30000) {
  // Race multiple locator strategies — whichever finds a visible element first wins.
  // Uses a generous timeout (default 30s) to handle React components that render asynchronously.
  const locators = [
    page.locator('a, button').filter({ hasText: EXPECTED_CTA }).first(),
    page.getByText(EXPECTED_CTA, { exact: false }).first(),
    page.locator(`a:has-text("${EXPECTED_CTA}")`).first(),
    page.locator(`button:has-text("${EXPECTED_CTA}")`).first(),
  ];
  try {
    // waitFor polls the DOM until the element is visible — perfect for async React renders
    const result = await Promise.any(
      locators.map(el => el.waitFor({ state: 'visible', timeout }).then(() => el))
    );
    return result;
  } catch (e) {
    return null;
  }
}

// Convert an expected destination pattern with {slug} placeholders into a regex
// that matches the resolved URL. Supports patterns like:
//   /enterprises/{enterprise_slug}/trial_activations
//   /{org_slug}/{repo_slug}/security
//   https://docs.github.com/en/copilot/...
// UTM query params (utm_source, utm_medium, utm_campaign, utm_content) are stripped
// before matching so they don't affect the comparison.
function destinationMatches(actualUrl, pattern) {
  if (!pattern) return { matches: true, skipped: true };

  // Strip the base URL prefix so we compare paths consistently
  let normalizedActual = actualUrl.replace(BASE_URL, '');

  // Strip UTM query params from the actual URL before matching
  try {
    const url = new URL(actualUrl);
    for (const key of [...url.searchParams.keys()]) {
      if (key.startsWith('utm_')) url.searchParams.delete(key);
    }
    // Rebuild: for relative patterns compare pathname+search+hash; for absolute compare full URL
    if (pattern.startsWith('http')) {
      // Remove trailing ? if search is now empty
      normalizedActual = url.toString().replace(/\?$/, '');
    } else {
      const search = url.searchParams.toString();
      normalizedActual = url.pathname + (search ? `?${search}` : '') + url.hash;
    }
  } catch (e) {
    // If URL parsing fails, fall back to the raw string
  }

  // Escape regex special chars in the pattern, then replace {slug} placeholders
  // with a non-greedy wildcard that matches one or more URL-safe characters.
  const escaped = pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regexStr = escaped.replace(/\\{[^}]+\\}/g, '[^/?&#]+');
  const regex = new RegExp(`^${regexStr}$`);

  return { matches: regex.test(normalizedActual), skipped: false };
}

// Command-picker controls (install-method dropdown + copy button) live inside
// install-picker nudge cards and carry an svg, so the generic `button:has(svg)`
// fallback can grab one of them instead of the card's X dismiss button. Exclude
// them explicitly so we never click a copy/dropdown control while dismissing.
const PICKER_BUTTON_EXCLUSION =
  ':not([data-test-selector="command-picker-method-button"])' +
  ':not([data-test-selector="command-picker-copy-button"])';

async function findDismissButton(page) {
  // Find the nudge container that holds our specific CTA text first,
  // then look for a dismiss button WITHIN that container.
  // This avoids dismissing a different nudge when multiple are stacked.
  try {
    // Highest priority: the card's explicit X (octicon-x) dismiss button. In
    // install-picker nudges the X sits in the card header — a sibling of the
    // CTA text container — so a CTA-scoped search can miss it and fall through
    // to a command-picker button. Target the innermost container that holds
    // BOTH the CTA text and an octicon-x button (i.e. the whole card), then
    // return that button.
    const xButton = page.locator('div, section, article, li')
      .filter({ has: page.getByText(EXPECTED_CTA) })
      .filter({ has: page.locator('button:has(svg.octicon-x)') })
      .last()
      .locator('button:has(svg.octicon-x)')
      .first();
    if (await xButton.isVisible({ timeout: 1000 }).catch(() => false)) return xButton;

    // Find containers that include the expected CTA text
    const containers = page.locator('div, section, article, li').filter({ has: page.getByText(EXPECTED_CTA) });
    const count = await containers.count();
    // Pick the smallest container that still has a dismiss button
    for (let i = count - 1; i >= 0; i--) {
      const container = containers.nth(i);
      const box = await container.boundingBox().catch(() => null);
      if (!box || box.height > 600 || box.height < 30) continue;

      const dismissSelectors = [
        'form[action*="dismiss"] button',
        'button:has(svg.octicon-x)',
        'button[aria-label*="Close"]',
        'button[aria-label*="Dismiss"]',
        'button[aria-label*="close"]',
        'button[aria-label*="dismiss"]',
        `button:has(svg)${PICKER_BUTTON_EXCLUSION}`,
      ];
      for (const sel of dismissSelectors) {
        const btn = container.locator(sel).first();
        if (await btn.isVisible({ timeout: 1000 }).catch(() => false)) return btn;
      }
    }
  } catch (e) { /* fall through */ }
  return null;
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

  // Console error listener
  page.on('console', msg => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });

  try {
    log(`\n===== NUDGE TEST: ${NUDGE_NAME} =====`);
    log(`CTA Account: ${CTA_LOGIN} | Dismiss Account: ${DISMISS_LOGIN}`);
    log(`Test Page: ${TEST_PAGE} | Expected CTA: "${EXPECTED_CTA}"`);
    log(`Dismiss Type: ${DISMISS_TYPE}`);

    // ======= PHASE 1: DISMISS CHECKS (run first to avoid CTA side-effects) =======

    let dismissSucceeded = false;

    // ======= CHECK 5: Dismiss Button =======
    log('\n--- Check 5: Dismiss Button ---');
    log(`Logging in as Dismiss account: ${DISMISS_LOGIN}`);
    await login(context, page, DISMISS_LOGIN);
    await page.goto(`${BASE_URL}${DISMISS_TEST_PAGE}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000); // Brief settle time for initial DOM
    await screenshot(page, `${DISMISS_LOGIN}-page-loaded`);

    // findCTA polls for up to 30s, handling React async renders
    let dismissCTA = await findCTA(page);

    // Retry once if nudge not visible — reload and wait again
    if (!dismissCTA) {
      log(`⚠️ Nudge not visible for dismiss account on first attempt — retrying after reload...`);
      await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(2000);
      await screenshot(page, `${DISMISS_LOGIN}-page-loaded-retry`);
      dismissCTA = await findCTA(page);
    }

    if (!dismissCTA) {
      log(`❌ DISMISS: Nudge not visible for dismiss account ${DISMISS_LOGIN} — cannot test dismiss`);
    } else {
      log(`✅ Nudge visible for dismiss account`);
      const dismissBtn = await findDismissButton(page);
      if (!dismissBtn) {
        log(`❌ DISMISS: No dismiss button found for ${NUDGE_NAME}`);
      } else {
        // Check size
        const box = await dismissBtn.boundingBox();
        if (box) {
          if (box.width < 24 || box.height < 24) {
            log(`❌ DISMISS: Button is only ${Math.round(box.width)}×${Math.round(box.height)}px — may have z-index or sizing issues`);
          }

          // Hover
          await dismissBtn.hover();
          await page.waitForTimeout(500);
          await screenshot(page, `${DISMISS_LOGIN}-dismiss-hover`);

          // Click center to dismiss
          await dismissBtn.click();
          await page.waitForTimeout(2000);
          await page.waitForLoadState('domcontentloaded', { timeout: 5000 }).catch(() => {});
          await screenshot(page, `${DISMISS_LOGIN}-after-dismiss`);

          // Verify the specific nudge is gone (not just any CTA text)
          // A different nudge may appear in its place after dismiss — that's OK
          const ctaAfterDismiss = await findCTA(page);
          if (!ctaAfterDismiss) {
            log(`✅ DISMISS: Button clicked, nudge disappeared`);
            dismissSucceeded = true;
          } else {
            // CTA text still found — but is it the SAME nudge or a different one?
            const afterText = await page.locator('body').innerText();
            const nudgeGone = !afterText.includes(EXPECTED_CTA);
            if (nudgeGone) {
              log(`✅ DISMISS: Original nudge dismissed (a different nudge appeared in its place)`);
              dismissSucceeded = true;
            } else {
              log(`❌ DISMISS: Nudge still visible after clicking dismiss button`);
            }
          }
        } else {
          log(`❌ DISMISS: Could not get dismiss button bounding box`);
        }
      }
    }

    // ======= CHECK 6: Dismiss Persistence =======
    log('\n--- Check 6: Dismiss Persistence ---');
    if (!dismissSucceeded) {
      log(`⚠️ DISMISS PERSISTS: SKIPPED — dismiss was not confirmed in Check 5`);
    } else {
      await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(2000);
      await screenshot(page, `${DISMISS_LOGIN}-after-reload`);

      // Use the same timeout as the initial findCTA (30s) to give async JS
      // the same opportunity to render the nudge after reload as before.
      const ctaAfterReload = await findCTA(page);
      if (!ctaAfterReload) {
        log(`✅ DISMISS PERSISTS: Nudge stays dismissed after reload`);
      } else {
        // Check if it's the same nudge or a replacement
        const reloadText = await page.locator('body').innerText();
        const nudgeGone = !reloadText.includes(EXPECTED_CTA);
        if (nudgeGone) {
          log(`✅ DISMISS PERSISTS: Original nudge stays dismissed (different nudge visible)`);
        } else {
          log(`❌ DISMISS PERSISTS: Nudge reappeared after reload!`);
        }
      }
    }

    // ======= PHASE 2: CTA CHECKS =======

    // ======= LOGIN AS CTA ACCOUNT =======
    log('\n--- Logging in as CTA account ---');
    await login(context, page, CTA_LOGIN);

    // ======= CHECK 1: Nudge Visibility =======
    log('\n--- Check 1: Nudge Visibility ---');
    await page.goto(`${BASE_URL}${TEST_PAGE}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000); // Brief settle time for initial DOM
    await screenshot(page, `${CTA_LOGIN}-page-loaded`);

    // findCTA polls for up to 30s, handling React async renders
    let ctaElement = await findCTA(page);

    // Retry once if nudge not visible — reload and wait again
    if (!ctaElement) {
      log(`⚠️ Nudge not visible on first attempt — retrying after reload...`);
      await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(2000);
      await screenshot(page, `${CTA_LOGIN}-page-loaded-retry`);
      ctaElement = await findCTA(page);
    }

    if (!ctaElement) {
      log(`❌ NOT VISIBLE: ${NUDGE_NAME} — CTA "${EXPECTED_CTA}" not found on ${TEST_PAGE} (after retry)`);
      log('\nSkipping remaining CTA checks — nudge not visible');
      console.log(JSON.stringify({ type: 'result', success: false, message: `Nudge not visible: ${EXPECTED_CTA}`, results }));
      await context.close();
      await browser.close();
      process.exit(0);
    }

    log(`✅ VISIBLE: ${NUDGE_NAME} — CTA "${EXPECTED_CTA}" found`);

    // ======= CHECK 2: CTA Hover, Clickability & Destination =======
    log('\n--- Check 2: CTA Clickability & Destination ---');

    // Hover
    await ctaElement.hover();
    await page.waitForTimeout(500);
    await screenshot(page, `${CTA_LOGIN}-cta-hover`);

    const ctaBox = await ctaElement.boundingBox();

    // Center click — wait for actual URL change with generous timeout
    const beforeUrl = page.url();
    const ctaRefreshed = await findCTA(page);
    if (ctaRefreshed) {
      await ctaRefreshed.click({ timeout: 10000 });
    } else {
      await page.mouse.click(ctaBox.x + ctaBox.width / 2, ctaBox.y + ctaBox.height / 2);
    }
    // Wait for navigation: use waitForURL to detect actual URL change (30s timeout)
    try {
      await page.waitForURL(url => url.toString() !== beforeUrl, { timeout: 30000 });
    } catch (e) {
      // URL didn't change within timeout — may be a modal or in-page action
    }
    await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => {});
    await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(3000);
    await screenshot(page, `${CTA_LOGIN}-cta-destination-page`);

    const destinationUrl = page.url();
    log(`CTA destination: ${destinationUrl}`);

    const navigated = destinationUrl !== beforeUrl;
    if (!navigated) {
      log(`❌ CTA CLICKABILITY: Center click did not navigate — possible z-index or overlay issue`);
    } else {
      log(`✅ CTA CLICKABILITY: Center click navigated successfully`);
    }

    // Check for 404
    const pageTitle = await page.title();
    const has404 = pageTitle.toLowerCase().includes('page not found') || pageTitle.includes('404');
    if (has404) {
      log(`❌ BUG: CTA "${EXPECTED_CTA}" leads to 404 at ${destinationUrl}`);
    } else {
      log(`✅ CTA: "${EXPECTED_CTA}" → ${destinationUrl}`);
    }

    // Check destination matches expected pattern
    if (EXPECTED_DESTINATION) {
      const { matches, skipped } = destinationMatches(destinationUrl, EXPECTED_DESTINATION);
      if (skipped) {
        log(`⚠️ CTA DESTINATION: No expected destination configured — skipped`);
      } else if (matches) {
        log(`✅ CTA DESTINATION: Matches expected pattern "${EXPECTED_DESTINATION}"`);
      } else {
        log(`❌ CTA DESTINATION: "${destinationUrl}" does not match expected "${EXPECTED_DESTINATION}"`);
      }
    } else {
      log(`⚠️ CTA DESTINATION: No expected destination configured — skipped`);
    }

    // ======= CHECK 3: Page Integrity =======
    log('\n--- Check 3: Page Integrity ---');
    // After CTA click, a concurrent navigation may still be in progress.
    // Retry page.goto once if it fails with ERR_ABORTED.
    try {
      await page.goto(`${BASE_URL}${TEST_PAGE}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    } catch (e) {
      await page.waitForTimeout(2000);
      await page.goto(`${BASE_URL}${TEST_PAGE}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    }
    await page.waitForTimeout(2000);

    const integrityResult = await page.evaluate(() => {
      const html = document.documentElement;
      // Only flag images that are visible, rendered, and have meaningful size
      // Skips: tracking pixels, hidden images, lazy-loaded below-fold, display:none
      const brokenImages = [...document.querySelectorAll('img')].filter(img => {
        if (img.complete && img.naturalWidth > 0) return false; // loaded fine
        const style = getComputedStyle(img);
        if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
        const rect = img.getBoundingClientRect();
        if (rect.width < 2 || rect.height < 2) return false; // tracking pixel
        if (rect.bottom < 0 || rect.top > window.innerHeight) return false; // off-screen
        return true;
      }).map(img => img.src);
      return {
        hasHorizontalScroll: html.scrollWidth > html.clientWidth,
        bodyOverflowX: getComputedStyle(document.body).overflowX,
        brokenImages,
      };
    });

    let integrityIssues = [];
    if (integrityResult.hasHorizontalScroll) {
      integrityIssues.push('horizontal scroll');
      log(`⚠️ PAGE INTEGRITY: Horizontal scroll detected on ${TEST_PAGE}`);
    }
    if (integrityResult.brokenImages.length > 0) {
      integrityIssues.push(`${integrityResult.brokenImages.length} broken images`);
      log(`⚠️ PAGE INTEGRITY: ${integrityResult.brokenImages.length} broken images on ${TEST_PAGE}`);
    }

    // Scroll full page
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
    await screenshot(page, `${CTA_LOGIN}-full-page-scroll`);

    if (integrityIssues.length === 0) {
      log(`✅ PAGE INTEGRITY: No issues detected`);
    }

    // ======= CHECK 4: Dismiss-and-Redirect (only for dismiss-and-redirect type) =======
    if (DISMISS_TYPE === 'dismiss-and-redirect') {
      log('\n--- Check 4: Dismiss-and-Redirect ---');
      // Re-login as CTA account (CTA click in Check 2 may have changed state)
      await login(context, page, CTA_LOGIN);
      await page.goto(`${BASE_URL}${TEST_PAGE}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(2000);
      
      // Click the CTA
      const ctaForDR = await findCTA(page);
      if (ctaForDR) {
        const drBeforeUrl = page.url();
        await ctaForDR.click({ timeout: 10000 });
        try {
          await page.waitForURL(url => url.toString() !== drBeforeUrl, { timeout: 30000 });
        } catch (e) { /* may not navigate */ }
        await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => {});
        await page.waitForTimeout(2000);
        const redirectUrl = page.url();
        log(`Redirected to: ${redirectUrl}`);

        // Go back and check if nudge is gone
        await page.goto(`${BASE_URL}${TEST_PAGE}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
        await page.waitForTimeout(3000);
        await screenshot(page, `${CTA_LOGIN}-dismiss-redirect-verify`);

        const ctaStillThere = await findCTA(page);
        if (!ctaStillThere) {
          log(`✅ DISMISS-AND-REDIRECT: CTA dismissed nudge and redirected`);

          // Reload to verify dismissal persisted (same timeout as initial check)
          await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 });
          await page.waitForTimeout(2000);
          const ctaAfterReload = await findCTA(page);
          if (!ctaAfterReload) {
            log(`✅ DISMISS-AND-REDIRECT PERSISTS: Nudge stays dismissed after reload`);
          } else {
            log(`❌ DISMISS-AND-REDIRECT PERSISTS: Nudge reappeared after reload!`);
          }
        } else {
          log(`❌ DISMISS-AND-REDIRECT: Nudge was not dismissed by CTA click`);
        }
      } else {
        log(`⚠️ DISMISS-AND-REDIRECT: CTA not found — may have been dismissed by Check 2`);
        // Navigate to test page to check
        await page.goto(`${BASE_URL}${TEST_PAGE}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
        await page.waitForTimeout(3000);
        const ctaGone = !(await findCTA(page));
        if (ctaGone) {
          log(`✅ DISMISS-AND-REDIRECT: Nudge already dismissed (from Check 2 CTA click)`);
        }
        await screenshot(page, `${CTA_LOGIN}-dismiss-redirect-verify`);
      }
    }

    // ======= SUMMARY =======
    log(`\n===== END ${NUDGE_NAME} =====`);

    if (consoleErrors.length > 0) {
      log(`\n⚠️ Console errors (${consoleErrors.length}):`);
      consoleErrors.slice(0, 10).forEach(e => log(`  - ${e}`));
    }

    console.log(JSON.stringify({ type: 'result', success: true, message: 'All checks completed', results }));
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
