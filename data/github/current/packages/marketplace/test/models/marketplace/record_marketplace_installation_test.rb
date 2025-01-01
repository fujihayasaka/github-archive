# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplaceRecordMarketplaceInstallationTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @user_plan_subscription = create(:billing_plan_subscription, user: @user)
    @org = create(:organization)
    @org_plan_subscription = create(:billing_plan_subscription, user: @org)
    @oauth_listing = create(:marketplace_listing)
    @oauth_listing_plan = create(:marketplace_listing_plan, :published, listing: @oauth_listing)
  end

  test "updates subscription items belonging to the user" do
    user_subscription = create(:billing_subscription_item, plan_subscription: @user_plan_subscription, subscribable: @oauth_listing_plan)

    Marketplace::RecordMarketplaceInstallation.call(user: @user, application: @oauth_listing.listable)

    assert user_subscription.reload.installed_at
  end

  test "updates subscription items belonging to user's orgs" do
    org_subscription = create(:billing_subscription_item, plan_subscription: @org_plan_subscription, subscribable: @oauth_listing_plan)
    @org.add_member(@user)

    Marketplace::RecordMarketplaceInstallation.call(user: @user, application: @oauth_listing.listable)

    assert org_subscription.reload.installed_at
  end

  test "does not update subscriptions belog to orgs requiring OAP" do
    @org.update!(restrict_oauth_applications: true)
    org_subscription = create(:billing_subscription_item, plan_subscription: @org_plan_subscription, subscribable: @oauth_listing_plan)
    @org.add_member(@user)

    Marketplace::RecordMarketplaceInstallation.call(user: @user, application: @oauth_listing.listable)

    assert_nil org_subscription.reload.installed_at
  end

  test "works for gh apps and users belonging to orgs with OAP enabled" do
    user = create(:user)
    integration = create(:integration, owner: user)
    org = create(:organization)
    org.add_member(user)
    org.enable_oauth_application_restrictions

    assert_empty Marketplace::RecordMarketplaceInstallation.call(user: user, application: integration)
  end
end
