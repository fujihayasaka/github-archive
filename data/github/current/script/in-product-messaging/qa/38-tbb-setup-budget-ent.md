# 38 — TBB Setup Budget Banner (Enterprise)

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-tbb-setup-budget-ent` |
| **Dismiss Login** | `ipm-tbb-setup-budget-ent-dismiss` |
| **Test Page** | `/enterprises/ipm-tbb-setup-budget-ent-biz` |
| **Test Page (Dismiss)** | `/enterprises/ipm-tbb-setup-budget-ent-dismiss-biz` |
| **Expected CTA** | "Set your budget" |
| **Expected Destination** | `/enterprises/{enterprise_slug}/billing/budgets/new?budget_type=premium_requests&budget_scope=multi_user_customer` |
| **Dismiss Type** | Standard — dismiss button on the banner |
| **Role** | Enterprise owner of `ipm-tbb-setup-budget-ent-biz` |
| **Setup** | Enterprise account, no Copilot Business. Feature flags `general_ipm_tbb_setup_budget`, `billing_user_level_budgets`, `billing_user_level_budgets_manage` enabled. No existing Copilot multi-user budget. |

## Notes

- **Location:** Enterprise pages — banner rendered via `TbbSetupBudgetBannerComponent` in `app/views/businesses/_layout.html.erb`.
- **Banner text:** Prompts enterprise owners to set up a per-user Copilot premium request budget.
- **Issue:** [github/in-product-messaging#473](https://github.com/github/in-product-messaging/issues/473)
- **Nudge ID:** `general_ipm_tbb_setup_budget`
- **Component:** `InProductTargeting::Components::OrganizationBanners::TbbSetupBudgetBannerComponent`
- **CTA account** (`ipm-tbb-setup-budget-ent`): Use for Checks 1–4. Test page: `/enterprises/ipm-tbb-setup-budget-ent-biz`.
- **Dismiss account** (`ipm-tbb-setup-budget-ent-dismiss`): Use for Checks 5–6. Test page: `/enterprises/ipm-tbb-setup-budget-ent-dismiss-biz`. Identical setup — separate enterprise so dismiss state doesn't affect CTA tests.
- **Eligibility:**
  1. User must have `general_ipm_tbb_setup_budget` feature flag enabled.
  2. User must be an enterprise owner or billing manager.
  3. Enterprise must have `billing_user_level_budgets` and `billing_user_level_budgets_manage` flags enabled.
  4. No existing Copilot multi-user budget on the enterprise.
  5. Enterprise must not be in an active DFD trial or have an expired trial.
  6. User has not dismissed the notice.
  7. User is subscribed to in-product messages.
