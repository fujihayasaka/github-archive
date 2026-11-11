# 33 — CCA Onboarding Modal: Tabs, Dropdown, and Tab-3 External CTA

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-team-welcome-modal-features` |
| **Modal Login** | `ipm-team-welcome-modal-features` |
| **Test Page** | `/copilot/agents` |
| **Modal Mode** | `features` |
| **Script** | `modal-test.mjs` |
| **Role** | Org member of `ipm-team-welcome-modal-features-org` (Team plan with CB seat) |
| **Setup** | Dedicated CB seat-holder used for non-dismissing interactions. Setup refreshes seat age + dismissal on every run. |

## Notes

- **Location:** Modal on `/copilot/agents` — verifies the modal renders on the alternate copilot-immersive route, not just `/copilot`.
- **What to verify (none of these dismiss the modal):**
  1. All three tab titles are visible: "Set up Copilot", "Plan, delegate, or manage work", "Customize your agent".
  2. **Tab 1 dropdown** — Click "Set up where you work" and verify the overlay opens, including:
     - "Set up in CLI" copy-input shows `brew install copilot-cli`.
     - Copy button (`aria-label="Copy the Copilot CLI install command"`) writes the install command to the clipboard.
     - VS Code link → `code.visualstudio.com/docs/copilot/setup`, `target="_blank"`.
     - JetBrains link → `docs.github.com/.../install-copilot-extension?tool=jetbrains`, `target="_blank"`.
     - More link → `docs.github.com/.../install-copilot-extension`, `target="_blank"`.
  3. **Tab 2 CTA** present with `dismiss-and-redirect` href containing `destination_key=accelerate_ipm_copilot_business_onboarding_modal_agents` — assertion only, NOT clicked (would dismiss the modal).
  4. **Tab 3 CTA** "Create a custom agent" is an external `<a>` to `https://docs.github.com/...` with `target="_blank"` — assertion only, NOT clicked (would open a new window).
  5. After all the above, the modal is still visible on the page.
- **Why a separate user:** the dropdown copy button + IDE links are not exercised elsewhere; isolating them keeps the test side-effect-free so it can run in parallel with the dismissing tests.
