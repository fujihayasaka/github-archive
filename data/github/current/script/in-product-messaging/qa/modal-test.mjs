// Playwright test for the CCA onboarding modal (a.k.a. Copilot Welcome Modal).
//
// Driven by env vars from a per-test `.md` file. The runner picks this script
// when the `.md` file's `Script` field contains `modal-test`.
//
// Modes (`MODAL_MODE`):
//   cta_main   — Click main CTA "Get started"; verify destination and dismissal.
//   cta_tab2   — Click tab 2, click "Start with agents"; verify destination
//                and dismissal.
//   features   — Tab nav + dropdown + IDE-link assertions + tab-3 external
//                CTA assertion (no popup navigation). Modal must remain visible.
//   close      — Click X close; modal disappears; reload; modal stays gone.
//                Note: the X-close handler POSTs to /track-nudge-dismissal —
//                that endpoint is named for analytics, but its server-side
//                handler ALSO calls `User#dismiss_notice(id) if UserNotice.find(id)`,
//                which IS the canonical persistence path. The dismissal sticks
//                because this nudge is registered in config/notices.yml.
//
// All selectors are scoped to the modal root
// (`[data-testid="product-announcement-modal"]`) so we never collide with
// page chrome or other nudges.
//
// See script/in-product-messaging/qa/setup.md for the per-test `.md` schema
// and the run-parallel.sh dispatch logic.

import { chromium } from 'playwright';

// ---------------------------------------------------------------------------
// Config from env
// ---------------------------------------------------------------------------
const MODAL_LOGIN = process.env.MODAL_LOGIN;
const TEST_PAGE = process.env.TEST_PAGE || '/copilot';
const MODAL_MODE = process.env.MODAL_MODE || 'cta_main';
const EXPECTED_DESTINATION = process.env.EXPECTED_DESTINATION || '';
const NUDGE_NAME = process.env.NUDGE_NAME || 'unknown';
const PASSWORD = 'passworD1';
const BASE_URL = 'http://github.localhost';

const SCREENSHOTS_DIR = process.env.SCREENSHOTS_DIR || './screenshots';
const VIDEOS_DIR = process.env.VIDEOS_DIR || './videos';

// ---------------------------------------------------------------------------
// Constants from the modal data (packages/product-announcement/data/ccaOnboarding.ts)
// ---------------------------------------------------------------------------
const MODAL_ROOT_SELECTOR = '[data-testid="product-announcement-modal"]';
const TAB_TITLES = ['Set up Copilot', 'Plan, delegate, or manage work', 'Customize your agent'];
const MAIN_CTA_TEXT = 'Get started';
const TAB2_CTA_TEXT = 'Start with agents';
const TAB3_CTA_TEXT = 'Create a custom agent';
const DROPDOWN_TRIGGER_TEXT = 'Set up where you work';
const DROPDOWN_COPY_VALUE = 'brew install copilot-cli';
const DROPDOWN_COPY_BUTTON_ARIA = 'Copy the Copilot CLI install command';
const TAB3_CTA_EXPECTED_HREF_PREFIX = 'https://docs.github.com/';

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
  for (let attempt = 1; attempt <= 3; attempt++) {
    await context.clearCookies();
    await page.goto(`${BASE_URL}/login`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.evaluate(() => {
      try { localStorage.clear(); } catch (e) {}
      try { sessionStorage.clear(); } catch (e) {}
    });
    await page.waitForTimeout(1000);

    // GitHub's login form has JS event handlers that can drop or mis-validate
    // characters when `.type()` (or `.pressSequentially()`) fires individual
    // keystrokes, producing intermittent "Incorrect username or password"
    // errors on otherwise valid credentials. `.fill()` sets the value
    // atomically and dispatches a single synthetic input event — see the qa
    // skill's `github-localhost-login.mjs` for the same approach.
    const loginField = page.locator('#login_field');
    await loginField.fill(username);
    const filledLogin = await loginField.inputValue();
    if (filledLogin !== username) {
      log(`⚠️ LOGIN: username field contained "${filledLogin}" after fill; retrying`);
      continue;
    }
    await page.locator('#password').fill(PASSWORD);

    await Promise.all([
      page.waitForURL((url) => !url.pathname.includes('/login'), { timeout: 30000 }).catch(() => {}),
      page.locator('input[type="submit"], input[name="commit"]').first().click(),
    ]);
    await page.waitForLoadState('domcontentloaded', { timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(2000);

    if (page.url().includes('/sessions/verified-device')) {
      try {
        await Promise.all([
          page.waitForURL((url) => !url.pathname.includes('/sessions/verified-device'), { timeout: 15000 }).catch(() => {}),
          page.getByRole('button', { name: /verify/i }).click({ timeout: 5000 }),
        ]);
        await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => {});
        await page.waitForTimeout(2000);
      } catch (e) {
        try {
          await Promise.all([
            page.waitForURL((url) => !url.pathname.includes('/sessions/verified-device'), { timeout: 15000 }).catch(() => {}),
            page.locator('button:has-text("Verify"), input[type="submit"]').first().click({ timeout: 5000 }),
          ]);
          await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => {});
          await page.waitForTimeout(2000);
        } catch (e2) { /* continue to success check below */ }
      }
    }

    const currentPath = new URL(page.url()).pathname;
    const loginError = await page.locator('.flash-error, [role="alert"]').first()
      .textContent({ timeout: 1000 })
      .catch(() => '');
    if (!currentPath.includes('/login') && currentPath !== '/session' && !currentPath.includes('/sessions/verified-device')) {
      await screenshot(page, `${username}-login-success`);
      return;
    }

    log(`⚠️ LOGIN: attempt ${attempt} failed at ${page.url()}${loginError ? ` (${loginError.trim().replace(/\s+/g, ' ')})` : ''}`);
  }

  throw new Error(`Login failed for ${username} after 3 attempts`);
}

// Wait for the modal portal to mount and become visible. Returns the modal
// root locator, or null if not visible after a retry.
//
// Note: the root `[data-testid="product-announcement-modal"]` element has
// `position: fixed` with no width/height (its visible content lives in
// absolutely-positioned children — backdrop + content panel). Its bounding
// box is therefore 0×0, which makes Playwright's `state: 'visible'` check
// reject the root even when the modal is fully rendered. We instead wait for
// the root to be attached, then poll `modalIsOpen`, which checks the root's
// effective open/closed state plus a real, sized close button.
async function waitForModal(page, { retry = true, timeout = 30000 } = {}) {
  const root = page.locator(MODAL_ROOT_SELECTOR).first();
  try {
    await root.waitFor({ state: 'attached', timeout });
    if (!(await waitForModalOpen(page, { timeout }))) throw new Error('Modal root attached but not open');
    return root;
  } catch (e) {
    if (!retry) return null;
    log(`⚠️ Modal not visible on first attempt — retrying after reload…`);
    await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);
    try {
      await root.waitFor({ state: 'attached', timeout: 15000 });
      if (!(await waitForModalOpen(page, { timeout: 15000 }))) throw new Error('Modal root attached but not open after retry');
      return root;
    } catch (e2) {
      return null;
    }
  }
}

async function waitForModalOpen(page, { timeout = 5000 } = {}) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const remaining = Math.max(deadline - Date.now(), 1);
    if (await modalIsOpen(page, { timeout: Math.min(remaining, 1000) })) return true;
    await page.waitForTimeout(250);
  }
  return false;
}

// Returns true iff the modal is currently rendered in its open state.
// Always include the root's dialog state in the check: when the modal closes,
// ProductAnnouncementModal keeps the portal mounted during/after the transition
// with `aria-modal="false"`, `inert`, and `opacity: 0`. Playwright's
// `isVisible()` ignores opacity, so checking only the close button can report a
// visually dismissed modal as still open.
async function modalIsOpen(page, { timeout = 5000 } = {}) {
  const root = page.locator(MODAL_ROOT_SELECTOR).first();
  try {
    await root.waitFor({ state: 'attached', timeout });
    return await root.evaluate((element) => {
      const rootStyle = getComputedStyle(element);
      if (element.getAttribute('aria-modal') !== 'true') return false;
      if (element.hasAttribute('inert')) return false;
      if (rootStyle.display === 'none' || rootStyle.visibility === 'hidden') return false;
      if (Number(rootStyle.opacity) === 0) return false;

      const closeButton = element.querySelector('button[aria-label*="close" i]');
      if (!closeButton) return false;

      const closeStyle = getComputedStyle(closeButton);
      const closeRect = closeButton.getBoundingClientRect();
      return closeRect.width > 0 &&
        closeRect.height > 0 &&
        closeStyle.display !== 'none' &&
        closeStyle.visibility !== 'hidden' &&
        Number(closeStyle.opacity) !== 0;
    });
  } catch (e) {
    return false;
  }
}

// Compare an actual URL against an expected pattern. Strips utm_* params and
// supports {slug} placeholders. Mirrors nudge-test.mjs#destinationMatches so
// the same `Expected Destination` semantics work in `.md` files.
function destinationMatches(actualUrl, pattern) {
  if (!pattern) return { matches: true, skipped: true };

  let normalizedActual = actualUrl.replace(BASE_URL, '');
  try {
    const url = new URL(actualUrl);
    for (const key of [...url.searchParams.keys()]) {
      if (key.startsWith('utm_')) url.searchParams.delete(key);
    }
    if (pattern.startsWith('http')) {
      normalizedActual = url.toString().replace(/\?$/, '');
    } else {
      const search = url.searchParams.toString();
      normalizedActual = url.pathname + (search ? `?${search}` : '') + url.hash;
    }
  } catch (e) {
    // fall through with raw value
  }

  const escaped = pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regexStr = escaped.replace(/\\{[^}]+\\}/g, '[^/?&#]+');
  const regex = new RegExp(`^${regexStr}$`);
  return { matches: regex.test(normalizedActual), skipped: false };
}

// Click the named tab inside the modal. Tabs are rendered as
// `<button data-tab>` (desktop) by ProductAnnouncementModalDesktop. No
// fallback selector — if `data-tab` regresses we want the test to fail loudly
// instead of silently clicking the wrong button.
async function clickTab(modalRoot, tabTitle) {
  const tabButton = modalRoot.locator('button[data-tab]').filter({ hasText: tabTitle }).first();
  if (!(await tabButton.isVisible({ timeout: 5000 }).catch(() => false))) {
    return false;
  }
  await tabButton.click();
  return true;
}

// Find the modal close button. ProductAnnouncementModalDesktop renders it as
// a top-level button with an aria-label.
async function findCloseButton(modalRoot) {
  const candidates = [
    modalRoot.locator('button[aria-label="Close"]').first(),
    modalRoot.locator('button[aria-label*="close" i]').first(),
    modalRoot.locator('button:has(svg.octicon-x)').first(),
  ];
  for (const btn of candidates) {
    if (await btn.isVisible({ timeout: 1000 }).catch(() => false)) return btn;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Mode runners
// ---------------------------------------------------------------------------

async function runCtaMain(page, modalRoot) {
  log('\n--- Modal Mode: cta_main (main "Get started" CTA) ---');

  const cta = modalRoot.locator('a, button').filter({ hasText: MAIN_CTA_TEXT }).first();
  if (!(await cta.isVisible({ timeout: 10000 }).catch(() => false))) {
    log(`❌ MAIN CTA: "${MAIN_CTA_TEXT}" not found inside modal`);
    return false;
  }

  const href = await cta.getAttribute('href');
  log(`Main CTA href: ${href ?? '(button — no href)'}`);
  if (!href || !href.includes('/in-product-messaging/dismiss-and-redirect')) {
    log(`❌ MAIN CTA: expected dismiss-and-redirect href, got "${href}"`);
    return false;
  }
  if (!href.includes('destination_key=accelerate_ipm_copilot_business_onboarding_modal_copilot')) {
    log(`❌ MAIN CTA: missing destination_key=accelerate_ipm_copilot_business_onboarding_modal_copilot`);
    return false;
  }
  log(`✅ MAIN CTA: href routes through dismiss-and-redirect → /copilot`);

  const beforeUrl = page.url();
  // Wait for the dismiss-and-redirect endpoint to respond. This handles the
  // same-URL case (start at /copilot, end at /copilot) reliably — `waitForURL`
  // with a "url changed" predicate would never fire there.
  const dismissResponse = page.waitForResponse(
    resp => resp.url().includes('/in-product-messaging/dismiss-and-redirect'),
    { timeout: 30000 }
  ).catch(() => null);
  await cta.click({ timeout: 10000 });
  await dismissResponse;
  await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(2000);
  await screenshot(page, 'cta-main-destination');
  const destinationUrl = page.url();
  log(`Navigation: ${beforeUrl} -> ${destinationUrl}`);

  const pageTitle = await page.title();
  if (pageTitle.toLowerCase().includes('page not found') || pageTitle.includes('404')) {
    log(`❌ MAIN CTA: destination is 404`);
    return false;
  }

  if (EXPECTED_DESTINATION) {
    const { matches, skipped } = destinationMatches(destinationUrl, EXPECTED_DESTINATION);
    if (skipped) {
      log(`⚠️ DESTINATION: skipped (none configured)`);
    } else if (matches) {
      log(`✅ DESTINATION: matches expected "${EXPECTED_DESTINATION}"`);
    } else {
      log(`❌ DESTINATION: "${destinationUrl}" does not match expected "${EXPECTED_DESTINATION}"`);
      return false;
    }
  }

  // Modal must be gone on the destination page (this is the read-after-write
  // race fixed by PR #430548 + #19862 — verify it is fixed end-to-end).
  if (await modalIsOpen(page, { timeout: 5000 })) {
    log(`❌ DISMISSAL: modal still visible on destination page (read-after-write race regression)`);
    return false;
  }
  log(`✅ DISMISSAL: modal absent on destination page`);

  // Reload the destination — modal should still be absent (KV-backed).
  // Wait the same 30s as the initial modal appearance check (waitForModal) to
  // give async JS the same opportunity to render after reload as before.
  await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);
  if (await modalIsOpen(page, { timeout: 30000 })) {
    log(`❌ PERSISTENCE: modal reappeared after reload`);
    return false;
  }
  log(`✅ PERSISTENCE: modal stays dismissed after reload`);
  return true;
}

async function runCtaTab2(page, modalRoot) {
  log('\n--- Modal Mode: cta_tab2 (tab-2 "Start with agents" CTA) ---');

  if (!(await clickTab(modalRoot, TAB_TITLES[1]))) {
    log(`❌ TAB 2: could not click tab "${TAB_TITLES[1]}"`);
    return false;
  }
  await page.waitForTimeout(500);
  await screenshot(page, 'tab-2-active');

  const cta = modalRoot.locator('a, button').filter({ hasText: TAB2_CTA_TEXT }).first();
  if (!(await cta.isVisible({ timeout: 10000 }).catch(() => false))) {
    log(`❌ TAB 2 CTA: "${TAB2_CTA_TEXT}" not found inside modal`);
    return false;
  }

  const href = await cta.getAttribute('href');
  log(`Tab-2 CTA href: ${href ?? '(button — no href)'}`);
  if (!href || !href.includes('/in-product-messaging/dismiss-and-redirect')) {
    log(`❌ TAB 2 CTA: expected dismiss-and-redirect href, got "${href}"`);
    return false;
  }
  if (!href.includes('destination_key=accelerate_ipm_copilot_business_onboarding_modal_agents')) {
    log(`❌ TAB 2 CTA: missing destination_key=accelerate_ipm_copilot_business_onboarding_modal_agents`);
    return false;
  }
  log(`✅ TAB 2 CTA: href routes through dismiss-and-redirect → /copilot/agents`);

  const beforeUrl = page.url();
  const dismissResponse = page.waitForResponse(
    resp => resp.url().includes('/in-product-messaging/dismiss-and-redirect'),
    { timeout: 30000 }
  ).catch(() => null);
  await cta.click({ timeout: 10000 });
  await dismissResponse;
  await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(2000);
  await screenshot(page, 'cta-tab2-destination');
  const destinationUrl = page.url();
  log(`Navigation: ${beforeUrl} -> ${destinationUrl}`);

  const pageTitle = await page.title();
  if (pageTitle.toLowerCase().includes('page not found') || pageTitle.includes('404')) {
    log(`❌ TAB 2 CTA: destination is 404`);
    return false;
  }

  if (EXPECTED_DESTINATION) {
    const { matches, skipped } = destinationMatches(destinationUrl, EXPECTED_DESTINATION);
    if (skipped) {
      log(`⚠️ DESTINATION: skipped (none configured)`);
    } else if (matches) {
      log(`✅ DESTINATION: matches expected "${EXPECTED_DESTINATION}"`);
    } else {
      log(`❌ DESTINATION: "${destinationUrl}" does not match expected "${EXPECTED_DESTINATION}"`);
      return false;
    }
  }

  if (await modalIsOpen(page, { timeout: 5000 })) {
    log(`❌ DISMISSAL: modal still visible on /copilot/agents after CTA click`);
    return false;
  }
  log(`✅ DISMISSAL: modal absent on /copilot/agents`);

  // Reload — modal should still be absent (KV-backed). Use the same 30s
  // timeout as the initial modal appearance check to give async JS the same
  // opportunity to render after reload as before.
  await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);
  if (await modalIsOpen(page, { timeout: 30000 })) {
    log(`❌ PERSISTENCE: modal reappeared after reload`);
    return false;
  }
  log(`✅ PERSISTENCE: modal stays dismissed after reload`);
  return true;
}

async function runFeatures(page, context, modalRoot) {
  log('\n--- Modal Mode: features (tabs + dropdown + tab-3 external CTA) ---');
  let ok = true;

  // Tab titles all rendered (sidebar buttons exist for all 3 tabs).
  for (const title of TAB_TITLES) {
    const tabBtn = modalRoot.locator('button[data-tab]').filter({ hasText: title }).first();
    if (!(await tabBtn.isVisible({ timeout: 5000 }).catch(() => false))) {
      log(`❌ TAB TITLE: "${title}" not visible`);
      ok = false;
    } else {
      log(`✅ TAB TITLE: "${title}" visible`);
    }
  }

  // Tab 1 — open dropdown, verify trigger + sections.
  if (!(await clickTab(modalRoot, TAB_TITLES[0]))) {
    log(`❌ TAB 1: could not click "${TAB_TITLES[0]}"`);
    ok = false;
  }
  await page.waitForTimeout(500);
  await screenshot(page, 'features-tab-1');

  const dropdownTrigger = modalRoot.locator('button').filter({ hasText: DROPDOWN_TRIGGER_TEXT }).first();
  if (!(await dropdownTrigger.isVisible({ timeout: 5000 }).catch(() => false))) {
    log(`❌ DROPDOWN: trigger "${DROPDOWN_TRIGGER_TEXT}" not visible on tab 1`);
    ok = false;
  } else {
    await dropdownTrigger.click();
    await page.waitForTimeout(800);
    await screenshot(page, 'features-dropdown-open');

    // Primer ActionMenu.Overlay portals out of the modal — query at page scope.
    // The TextInput holds the brew install command.
    const cliInput = page.locator(`input[value="${DROPDOWN_COPY_VALUE}"]`).first();
    if (await cliInput.isVisible({ timeout: 5000 }).catch(() => false)) {
      log(`✅ DROPDOWN: "Set up in CLI" input shows "${DROPDOWN_COPY_VALUE}"`);
    } else {
      log(`❌ DROPDOWN: "Set up in CLI" input not found with value "${DROPDOWN_COPY_VALUE}"`);
      ok = false;
    }

    // IDE links — assert href + target=_blank without navigating.
    const ideLinkAssertions = [
      { id: 'vscode',    label: 'VS Code',   hrefIncludes: 'code.visualstudio.com/docs/copilot/setup' },
      { id: 'jetbrains', label: 'JetBrains', hrefIncludes: 'docs.github.com/en/copilot/how-tos/set-up/install-copilot-extension?tool=jetbrains' },
      { id: 'more',      label: 'More',      hrefIncludes: 'docs.github.com/en/copilot/how-tos/set-up/install-copilot-extension' },
    ];
    for (const item of ideLinkAssertions) {
      const link = page.locator('a').filter({ hasText: new RegExp(`^${item.label}$`) }).first();
      if (!(await link.isVisible({ timeout: 3000 }).catch(() => false))) {
        log(`❌ DROPDOWN: "${item.label}" link not visible`);
        ok = false;
        continue;
      }
      const href = await link.getAttribute('href');
      const target = await link.getAttribute('target');
      if (!href || !href.includes(item.hrefIncludes)) {
        log(`❌ DROPDOWN: "${item.label}" href "${href}" does not include "${item.hrefIncludes}"`);
        ok = false;
      } else if (target !== '_blank') {
        log(`❌ DROPDOWN: "${item.label}" target="${target}" (expected "_blank")`);
        ok = false;
      } else {
        log(`✅ DROPDOWN: "${item.label}" → ${href} (target=_blank)`);
      }
    }

    // Copy button — verify clipboard contents. Permissions were granted at
    // context creation, so navigator.clipboard.readText is allowed.
    //
    // The CopyToClipboardButton wraps an IconButton in a Tooltip. Primer's
    // IconButton uses `aria-labelledby={tooltipId}` (NOT `aria-label`) when
    // wrapped in a Tooltip, so a `[aria-label="…"]` selector cannot find
    // this button. Use `getByRole('button', { name })` — Playwright's role
    // engine resolves the accessible name through `aria-labelledby`. The
    // `octicon-copy` SVG narrows in case future markup pluralizes the name.
    const copyBtn = page
      .getByRole('button', { name: DROPDOWN_COPY_BUTTON_ARIA })
      .filter({ has: page.locator('svg.octicon-copy') })
      .first();
    if (await copyBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      // Reset clipboard to a sentinel so we can prove the click changed it.
      await page.evaluate(() => navigator.clipboard.writeText('__MODAL_TEST_SENTINEL__').catch(() => {}));
      await copyBtn.click();
      await page.waitForTimeout(500);
      const clipboardText = await page.evaluate(() => navigator.clipboard.readText().catch(() => ''));
      if (clipboardText === DROPDOWN_COPY_VALUE) {
        log(`✅ DROPDOWN: copy button wrote "${DROPDOWN_COPY_VALUE}" to clipboard`);
      } else {
        log(`❌ DROPDOWN: clipboard contains "${clipboardText}" (expected "${DROPDOWN_COPY_VALUE}")`);
        ok = false;
      }
    } else {
      log(`❌ DROPDOWN: copy button (accessible name="${DROPDOWN_COPY_BUTTON_ARIA}") not visible`);
      ok = false;
    }

    // Close the dropdown so its overlay can't intercept later tab clicks.
    // Pressing Escape works only if the dropdown still has focus; toggling
    // the trigger is more reliable across copy success/failure paths.
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    if (await page.locator('input[value="' + DROPDOWN_COPY_VALUE + '"]').isVisible({ timeout: 500 }).catch(() => false)) {
      // Escape didn't close it — toggle the trigger.
      await dropdownTrigger.click().catch(() => {});
      await page.waitForTimeout(500);
    }
  }

  // Tab 2 — verify "Start with agents" CTA exists with correct href, but do
  // NOT click (would dismiss the modal).
  if (!(await clickTab(modalRoot, TAB_TITLES[1]))) {
    log(`❌ TAB 2: could not click "${TAB_TITLES[1]}"`);
    ok = false;
  } else {
    await page.waitForTimeout(500);
    await screenshot(page, 'features-tab-2');
    const tab2Cta = modalRoot.locator('a, button').filter({ hasText: TAB2_CTA_TEXT }).first();
    if (await tab2Cta.isVisible({ timeout: 5000 }).catch(() => false)) {
      const href = await tab2Cta.getAttribute('href');
      if (href && href.includes('destination_key=accelerate_ipm_copilot_business_onboarding_modal_agents')) {
        log(`✅ TAB 2 CTA: "${TAB2_CTA_TEXT}" present with dismiss-and-redirect href`);
      } else {
        log(`❌ TAB 2 CTA: href "${href}" missing expected destination_key`);
        ok = false;
      }
    } else {
      log(`❌ TAB 2 CTA: "${TAB2_CTA_TEXT}" not visible`);
      ok = false;
    }
  }

  // Tab 3 — assert "Create a custom agent" anchor has correct href +
  // target="_blank". Do NOT click it (would open a popup).
  if (!(await clickTab(modalRoot, TAB_TITLES[2]))) {
    log(`❌ TAB 3: could not click "${TAB_TITLES[2]}"`);
    ok = false;
  } else {
    await page.waitForTimeout(500);
    await screenshot(page, 'features-tab-3');
    const tab3Cta = modalRoot.locator('a').filter({ hasText: TAB3_CTA_TEXT }).first();
    if (!(await tab3Cta.isVisible({ timeout: 5000 }).catch(() => false))) {
      log(`❌ TAB 3 CTA: "${TAB3_CTA_TEXT}" not visible`);
      ok = false;
    } else {
      const href = await tab3Cta.getAttribute('href');
      const target = await tab3Cta.getAttribute('target');
      if (!href || !href.startsWith(TAB3_CTA_EXPECTED_HREF_PREFIX)) {
        log(`❌ TAB 3 CTA: href "${href}" does not start with "${TAB3_CTA_EXPECTED_HREF_PREFIX}"`);
        ok = false;
      } else if (target !== '_blank') {
        log(`❌ TAB 3 CTA: target="${target}" (expected "_blank")`);
        ok = false;
      } else {
        log(`✅ TAB 3 CTA: "${TAB3_CTA_TEXT}" → ${href} (target=_blank)`);
      }
    }
  }

  // None of the above interactions should have dismissed the modal. The
  // root has a 0×0 bounding box (see `waitForModal` notes), so check the
  // close button as the open-state proxy instead of the root itself.
  if (await modalIsOpen(page, { timeout: 3000 })) {
    log(`✅ MODAL STATE: still visible after non-dismissing interactions`);
  } else {
    log(`❌ MODAL STATE: modal disappeared during features test (none of these should dismiss it)`);
    ok = false;
  }

  return ok;
}

async function runClose(page, modalRoot) {
  log('\n--- Modal Mode: close (X button + persistence) ---');

  const closeBtn = await findCloseButton(modalRoot);
  if (!closeBtn) {
    log(`❌ CLOSE: X button not found inside modal`);
    return false;
  }

  await closeBtn.hover();
  await page.waitForTimeout(300);
  await screenshot(page, 'close-hover');

  // The X close handler in CopilotWelcomeModal fires
  // `verifiedFetch(POST /track-nudge-dismissal, …)` and does NOT await the
  // response. The endpoint is named for analytics (`/track-nudge-dismissal`),
  // but its handler ALSO calls `current_user.dismiss_notice(id) if UserNotice.find(id)`
  // — and this nudge IS registered in config/notices.yml, so the KV
  // `user.dismissed_notice.accelerate_ipm_copilot_business_onboarding_modal`
  // gets written as a side-effect. Capture the response promise so we know
  // both side-effects committed before the persistence reload below.
  const dismissResponse = page.waitForResponse(
    resp => resp.url().includes('/track-nudge-dismissal') && resp.request().method() === 'POST',
    { timeout: 30000 }
  ).catch(() => null);

  await closeBtn.click();
  await page.waitForTimeout(2000);
  await screenshot(page, 'close-clicked');

  const goneAfterClick = !(await modalIsOpen(page, { timeout: 5000 }));
  if (!goneAfterClick) {
    log(`❌ CLOSE: modal still visible after clicking X`);
    return false;
  }
  log(`✅ CLOSE: modal disappeared after clicking X`);

  // Wait for the POST response so both side-effects (analytics +
  // dismiss_notice) have committed before reloading.
  const dismissalResp = await dismissResponse;
  if (dismissalResp) {
    log(`✅ /track-nudge-dismissal POST responded ${dismissalResp.status()} (dismiss_notice side-effect should have committed)`);
  } else {
    log(`⚠️ /track-nudge-dismissal POST not observed within 30s — reload-persistence assertion may race the dismiss_notice write`);
  }

  // Reload — the modal must stay gone because eligibility now sees
  // `user.dismissed_notice?(...)` return true. Use the same 30s timeout as the
  // initial modal appearance check to give async JS the same opportunity to
  // render after reload as before.
  await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);
  await screenshot(page, 'close-after-reload');
  if (await modalIsOpen(page, { timeout: 30000 })) {
    log(`❌ PERSISTENCE: modal reappeared after reload`);
    return false;
  }
  log(`✅ PERSISTENCE: modal stays dismissed after reload`);
  return true;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  const browser = await chromium.launch({ headless: true });
  // Grant clipboard permissions explicitly — the features test reads/writes
  // navigator.clipboard, which requires `clipboard-read` + `clipboard-write`
  // origin permissions in Chromium.
  const context = await browser.newContext({
    viewport: { width: 1280, height: 720 },
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    recordVideo: { dir: VIDEOS_DIR, size: { width: 1280, height: 720 } },
    ignoreHTTPSErrors: true,
    permissions: ['clipboard-read', 'clipboard-write'],
  });
  await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: BASE_URL });
  const page = await context.newPage();

  page.on('console', msg => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });

  let success = false;
  try {
    log(`\n===== MODAL TEST: ${NUDGE_NAME} =====`);
    log(`Account: ${MODAL_LOGIN} | Test Page: ${TEST_PAGE} | Mode: ${MODAL_MODE}`);

    if (!MODAL_LOGIN) {
      log('❌ MODAL_LOGIN env var is required');
      console.log(JSON.stringify({ type: 'result', success: false, message: 'MODAL_LOGIN missing', results }));
      await context.close();
      await browser.close();
      process.exit(0);
    }

    await login(context, page, MODAL_LOGIN);
    await page.goto(`${BASE_URL}${TEST_PAGE}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);
    await screenshot(page, `${MODAL_LOGIN}-page-loaded`);

    const modalRoot = await waitForModal(page);
    if (!modalRoot) {
      log(`❌ NOT VISIBLE: modal not found on ${TEST_PAGE} for ${MODAL_LOGIN} (after retry)`);
      console.log(JSON.stringify({ type: 'result', success: false, message: 'Modal not visible', results }));
      await context.close();
      await browser.close();
      process.exit(0);
    }
    log(`✅ VISIBLE: modal rendered on ${TEST_PAGE}`);
    await screenshot(page, 'modal-visible');

    switch (MODAL_MODE) {
      case 'cta_main':
        success = await runCtaMain(page, modalRoot);
        break;
      case 'cta_tab2':
        success = await runCtaTab2(page, modalRoot);
        break;
      case 'features':
        success = await runFeatures(page, context, modalRoot);
        break;
      case 'close':
        success = await runClose(page, modalRoot);
        break;
      default:
        log(`❌ Unknown MODAL_MODE: ${MODAL_MODE}`);
        success = false;
    }
  } catch (e) {
    log(`❌ Exception: ${e.message}\n${e.stack}`);
    success = false;
  }

  log(`\n===== END ${NUDGE_NAME} =====`);
  if (consoleErrors.length > 0) {
    log(`\n⚠️ Console errors (${consoleErrors.length}):`);
    consoleErrors.slice(0, 10).forEach(e => log(`  - ${e}`));
  }

  console.log(JSON.stringify({
    type: 'result',
    success,
    mode: MODAL_MODE,
    results,
  }));

  await context.close();
  await browser.close();
  process.exit(success ? 0 : 1);
})();
