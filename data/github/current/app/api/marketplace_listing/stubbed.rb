# typed: true
# frozen_string_literal: true

class Api::MarketplaceListing::Stubbed < Api::App
  include Api::App::MarketplaceListingHelpers

  get "/marketplace_listing/stubbed/plans", operation_id: "apps/list-plans-stubbed" do
    if FeatureFlag.vexi.enabled?(:marketplace_stub_apis_return_404, default: false)
      deliver_error!(404)
    end

    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed
    deliver_raw Marketplace::StubbedResponse.plans
  end

  get "/marketplace_listing/stubbed/accounts/:account_id", operation_id: "apps/get-subscription-plan-for-account-stubbed" do
    if FeatureFlag.vexi.enabled?(:marketplace_stub_apis_return_404, default: false)
      deliver_error!(404)
    end

    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed
    deliver_raw Marketplace::StubbedResponse.organization_subscription_item
  end

  get "/marketplace_listing/stubbed/plans/:plan_id/accounts", operation_id: "apps/list-accounts-for-plan-stubbed" do
    if FeatureFlag.vexi.enabled?(:marketplace_stub_apis_return_404, default: false)
      deliver_error!(404)
    end

    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed
    deliver_raw Marketplace::StubbedResponse.subscription_items
  end
end
