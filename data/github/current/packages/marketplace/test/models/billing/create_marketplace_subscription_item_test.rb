# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::CreateMarketplaceSubscriptionItemTest < GitHub::TestCase
  include HookIntegrationTestHelper
  include HydroTestHelpers

  fixtures do
    @business = create :business, :with_self_serve_payment
    @business_plan_subscription = create :billing_plan_subscription, :zuora, :business_owned, customer: @business.customer
    @business_owner_org_admin = @business.owners.first
    @business_org = create :organization, business: @business, admin: @business_owner_org_admin
    @business_org2 = create :organization, business: @business, admin: @business_owner_org_admin
    @marketplace_paid_listing_plan = create(:marketplace_listing_plan, :verified_listing, :paid)
    @marketplace_free_trial_listing_plan = create(:marketplace_listing_plan, :verified_listing, has_free_trial: true)
  end

  setup do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  teardown do
    self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  unless GitHub.enterprise?
    test "creates a subscription item for the specified account's subscription" do
      FakeZuora.mock
      user = create(:user)
      org = create(:organization, :zuora, admin: user)
      plan_sub = create(:billing_plan_subscription, :zuora, user: org)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

      result = T.let(nil, T.untyped)
      assert_difference "Billing::SubscriptionItem.count" do
        assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
          result = Billing::CreateMarketplaceSubscriptionItem.call(
            listing_plan: marketplace_listing_plan,
            quantity: 3,
            account: org,
            viewer: user,
          )
        end
      end

      assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
        user_id: org.id, plan_name: org.plan.name, purpose: plan_sub.purpose,
      }, user: org])
      assert_equal 3, result[:subscription_item].quantity
      assert_equal marketplace_listing_plan.listing.name, result[:subscription_item].subscribable.listing.name
    end

    test "sends a marketplace subscription purchased event" do
      FakeZuora.mock
      user = create(:user)
      org = create(:organization, :zuora, admin: user)
      plan_sub = create(:billing_plan_subscription, :zuora, user: org)

      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
      listing = marketplace_listing_plan.listing

      hook = create :hook, :web,
        installation_target: listing,
        events: %w(marketplace_purchase)
      deliveries = subscribe_to_hook_delivery "marketplace_purchase"

      SynchronizePlanSubscriptionJob.expects(:perform_later).with({
        user_id: org.id, plan_name: org.plan.name, purpose: plan_sub.purpose,
      }, user: org)

      Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: marketplace_listing_plan,
        quantity: 3,
        account: org,
        viewer: user,
      )

      assert_equal 1, deliveries.count
      assert_includes deliveries.hooks, hook

      payload = deliveries.payload_for_hook(hook)
      assert_equal "purchased", payload[:action]
      assert_equal marketplace_listing_plan.id, payload[:marketplace_purchase][:plan][:id]
    end

    test "verifies the publishing of the marketplace subscription purchased hydro event without an order preview" do
      FakeZuora.mock
      user = create(:user)
      org = create(:organization, :zuora, admin: user)
      plan_sub = create(:billing_plan_subscription, :zuora, user: org)

      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
      listing = marketplace_listing_plan.listing

      hook = create :hook, :web,
        installation_target: listing,
        events: %w(marketplace_purchase)
      deliveries = subscribe_to_hook_delivery "marketplace_purchase"

      SynchronizePlanSubscriptionJob.expects(:perform_later).with({
        user_id: org.id, plan_name: org.plan.name, purpose: plan_sub.purpose,
      }, user: org)

      result = Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: marketplace_listing_plan,
        quantity: 3,
        account: org,
        viewer: user,
      )
      subscription_item = result[:subscription_item]

      expected_hydro_payload = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(user),
        account: Hydro::EntitySerializer.user(org),
        subscription_item_id: subscription_item.id,
        marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
        marketplace_listing_plan: Hydro::EntitySerializer.marketplace_listing_plan(marketplace_listing_plan),
      }

      assert_hydro_published(expected_hydro_payload, schema: "github.marketplace.v0.PurchasePurchased")
      assert_hydro_messages(count: 1, schema: "github.marketplace.v0.PurchasePurchased")
    end

    test "verifies the publishing of the marketplace subscription purchased hydro event with an order preview" do
      FakeZuora.mock
      user = create(:user)
      org = create(:organization, :zuora, admin: user)
      plan_sub = create(:billing_plan_subscription, :zuora, user: org)

      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
      listing = marketplace_listing_plan.listing
      order_preview = create(:marketplace_order_preview, listing: listing, listing_plan: marketplace_listing_plan,
        user: user, email_notification_sent_at: 1.day.ago)

      hook = create :hook, :web,
        installation_target: listing,
        events: %w(marketplace_purchase)
      deliveries = subscribe_to_hook_delivery "marketplace_purchase"

      SynchronizePlanSubscriptionJob.expects(:perform_later).with({
        user_id: org.id, plan_name: org.plan.name, purpose: plan_sub.purpose,
      }, user: org)

      result = Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: marketplace_listing_plan,
        quantity: 3,
        account: org,
        viewer: user,
      )
      subscription_item = result[:subscription_item]

      expected_hydro_payload = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(user),
        account: Hydro::EntitySerializer.user(org),
        subscription_item_id: subscription_item.id,
        marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
        marketplace_listing_plan: Hydro::EntitySerializer.marketplace_listing_plan(marketplace_listing_plan),
        order_preview_viewed_at: order_preview.viewed_at,
        order_preview_email_notification_sent_at: order_preview.email_notification_sent_at,
      }

      assert_hydro_published(expected_hydro_payload, schema: "github.marketplace.v0.PurchasePurchased")
      assert_hydro_messages(count: 1, schema: "github.marketplace.v0.PurchasePurchased")
    end

    test "resets the viewer's pending installation notice for a new subscription" do
      FakeZuora.mock

      user = create(:credit_card_user)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

      notice = Marketplace::PendingInstallations::Notice.new(user_id: user.id)
      notice.dismiss

      assert_predicate notice, :dismissed?

      Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: marketplace_listing_plan,
        quantity: 1,
        account: user,
        viewer: user,
      )

      refute notice.dismissed?
    end

    test "does not reset the viewer's pending installation notice for a plan change on a previously installed listing" do
      FakeZuora.mock

      plan_subscription = create(:billing_plan_subscription)
      user = plan_subscription.user
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
      subscription = create(:billing_subscription_item, :installed, plan_subscription: plan_subscription,
        subscribable: marketplace_listing_plan)
      subscription.cancel!(actor: user, force: true)

      notice = Marketplace::PendingInstallations::Notice.new(user_id: user.id)
      notice.dismiss

      assert notice.dismissed?

      Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: marketplace_listing_plan,
        quantity: 1,
        account: user,
        viewer: user,
      )

      assert notice.dismissed?
    end

    test "when user has already installed app, sets installed_at for subscription item & subscription_item_id for integration installation" do
      user = create(:credit_card_user)
      integration_installation = make_integration_installation(target: user)
      listing = create(:marketplace_listing, :verified, :with_plans, listable: integration_installation.integration)

      result = Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: listing.listing_plans.first,
        quantity: 1,
        account: user,
        viewer: user,
      )

      subscription_item = result[:subscription_item]
      integration_installation.reload

      assert_equal integration_installation.created_at, subscription_item.installed_at
      assert_equal integration_installation.subscription_item_id, subscription_item.id
    end

    test "when user has not already installed app, does not set installed_at for subscription item" do
      user = create(:credit_card_user)
      listing = create(:marketplace_listing, :verified, :with_plans, :integration)

      result = Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: listing.listing_plans.first,
        quantity: 1,
        account: user,
        viewer: user,
      )

      subscription_item = result[:subscription_item]
      assert_nil subscription_item.installed_at
    end

    test "when org has already installed app, sets installed_at for subscription item & subscription_item_id for integration installation" do
      user = create(:credit_card_user)
      org = create(:credit_card_organization, admin: user)
      integration_installation = make_integration_installation(target: org)
      listing = create(:marketplace_listing, :verified, :with_plans, listable: integration_installation.integration)

      result = Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: listing.listing_plans.first,
        quantity: 1,
        account: org,
        viewer: user,
      )

      subscription_item = result[:subscription_item]
      integration_installation.reload

      assert_equal integration_installation.created_at, subscription_item.installed_at
      assert_equal integration_installation.subscription_item_id, subscription_item.id
    end

    test "when org has not already installed app, does not set installed_at for subscription item" do
      user = create(:credit_card_user)
      org = create(:credit_card_organization, admin: user)
      listing = create(:marketplace_listing, :verified, :with_plans, :integration)

      result = Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: listing.listing_plans.first,
        quantity: 1,
        account: org,
        viewer: user,
      )

      subscription_item = result[:subscription_item]
      assert_nil subscription_item.installed_at
    end

    test "when user has installed app on personal account, does not set installed_at for organization subscription item & subscription_item_id for personal integration installation" do
      user = create(:credit_card_user)
      org = create(:credit_card_organization, admin: user)
      integration_installation = make_integration_installation(target: user)
      listing = create(:marketplace_listing, :verified, :with_plans, listable: integration_installation.integration)

      result = Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: listing.listing_plans.first,
        quantity: 1,
        account: org,
        viewer: user,
      )

      subscription_item = result[:subscription_item]
      integration_installation.reload

      assert_nil subscription_item.installed_at
      assert_nil integration_installation.subscription_item_id
    end

    test "when app has been installed on org account, does not set installed_at for subscription item on an admin's personal account & subscription_item_id for org integration installation" do
      user = create(:credit_card_user)
      org = create(:credit_card_organization, admin: user)
      integration_installation = make_integration_installation(target: org)
      listing = create(:marketplace_listing, :verified, :with_plans, listable: integration_installation.integration)

      inputs = {
        listing_plan: listing.listing_plans.first,
        quantity: 1,
        account: user,
        viewer: user,
      }
      result = Billing::CreateMarketplaceSubscriptionItem.call(**inputs)
      subscription_item = result[:subscription_item]
      integration_installation.reload

      assert_nil subscription_item.installed_at
      assert_nil integration_installation.subscription_item_id
    end

    test "creates a subscription item for a free user" do
      self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      user = create :credit_card_user
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

      result = assert_difference "Billing::SubscriptionItem.count" do
        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 2,
          account: user,
          viewer: user,
        )
      end

      assert_equal 2, result[:subscription_item].quantity
      assert_equal marketplace_listing_plan.listing.name, result[:subscription_item].subscribable.listing.name
      assert_equal GitHub::Plan.find!("free_with_addons"), user.reload.plan
    end

    test "creates a subscription item for users covered by coupons" do
      user = create :no_credit_card_user, plan: "pro"
      user.coupons << create(:coupon)
      user.customer.payment_method = create :payment_method

      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

      assert_difference "Billing::SubscriptionItem.count" do
        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 2,
          account: user,
          viewer: user,
        )
      end

      assert_equal GitHub::Plan.find!("pro"), user.reload.plan
    end

    test "does not disclose account payment status to unauthorized accounts" do
      account = create(:user)
      unauthorized = create(:user)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

      error = assert_raises Billing::CreateSubscriptionItem::ForbiddenError do
        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 2,
          account: account,
          viewer: unauthorized,
        )
      end
      assert_equal "#{unauthorized} does not have permission to manage this account (#{account})", error.message
    end

    test "does not disclose account spammy status to unauthorized accounts" do
      account = create(:user)
      account.update(spammy: true)
      unauthorized = create(:user)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

      error = assert_raises Billing::CreateSubscriptionItem::ForbiddenError do
        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 2,
          account: account,
          viewer: unauthorized,
        )
      end
      assert_equal "#{unauthorized} does not have permission to manage this account (#{account})", error.message
    end

    test "raises an error for a User trying to subscribe to an Org only plan" do
      user = create(:credit_card_user)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing, :organizations_only)

      error = assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 2,
          account: user,
          viewer: user,
        )
      end
      expected_message = "Could not purchase this item: This plan is for organizations only, " \
        "please select a different billing account or plan."
      assert_equal expected_message, error.message
    end

    test "raises an error for a User trying to install on a random" do
      biz = create :business, :with_self_serve_payment, trial_expires_at: 1.week.from_now
      random_org = create(:organization)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

      error = assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 2,
          account:  biz,
          viewer: biz.owners.first,
          installation_account: random_org,
        )
      end
      expected_message = "#{random_org} is not a valid installation account."
      assert_equal expected_message, error.message
    end

    test "raises an error for an Org trying to subscribe to a User only plan" do
      user = create(:user)
      org = create(:credit_card_org, admin: user)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing, :users_only)

      error = assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 1,
          account: org,
          viewer: user,
        )
      end
      expected_message = "Could not purchase this item: This plan is for personal accounts only, " \
        "please select a different billing account or plan."
      assert_equal expected_message, error.message
    end

    test "raises an error for users without a valid payment method" do
      user = create(:user)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

      error = assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 2,
          account: user,
          viewer: user,
        )
      end
      assert_equal "Please add a payment method before checking out.", error.message
    end

    test "refuses to create a subscription item for another account" do
      FakeZuora.mock
      user = create(:user)
      org = create(:organization, :zuora)
      create(:billing_plan_subscription, :zuora, user: org)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

      initial_count = Billing::SubscriptionItem.count

      error = T.let(nil, T.untyped)
      assert_no_performed_jobs(only: SynchronizePlanSubscriptionJob) do
        error = assert_raises Billing::CreateSubscriptionItem::ForbiddenError do
          Billing::CreateMarketplaceSubscriptionItem.call(
            listing_plan: marketplace_listing_plan,
            quantity: 2,
            account: org,
            viewer: user,
          )
        end
      end
      assert_equal "#{user} does not have permission to manage this account (#{org})", error.message
      assert_equal initial_count, Billing::SubscriptionItem.count
    end

    test "refuses to create a subscription item for an unknown account" do
      FakeZuora.mock
      user = create(:user)
      org = create(:organization, :zuora)
      create(:billing_plan_subscription, :zuora, user: org)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

      initial_count = Billing::SubscriptionItem.count

      error = T.let(nil, T.untyped)
      assert_no_performed_jobs(only: SynchronizePlanSubscriptionJob) do
        error = assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
          Billing::CreateMarketplaceSubscriptionItem.call(
            listing_plan: marketplace_listing_plan,
            quantity: 2,
            account: nil,
            viewer: user,
          )
        end
      end
      assert_equal "Account not found", error.message
      assert_equal initial_count, Billing::SubscriptionItem.count
    end

    test "does not create a subscription item for a delisted Marketplace listing" do
      user = create(:user)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
      marketplace_listing_plan.listing.delist!

      initial_count = Billing::SubscriptionItem.count

      error = T.let(nil, T.untyped)
      assert_no_performed_jobs(only: SynchronizePlanSubscriptionJob) do
        error = assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
          Billing::CreateMarketplaceSubscriptionItem.call(
            listing_plan: marketplace_listing_plan,
            quantity: 2,
            account: user,
            viewer: user,
          )
        end
      end
      assert_equal "Please add a payment method before checking out.", error.message
      assert_equal initial_count, Billing::SubscriptionItem.count
    end

    test "free user can add a free plan" do
      user = create(:user)
      marketplace_listing_plan = create :marketplace_listing_plan, :verified_listing,
        monthly_price_in_cents: 0,
        yearly_price_in_cents: 0

      result = T.let(nil, T.untyped)
      assert_difference "Billing::SubscriptionItem.count" do
        result = Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 2,
          account: user,
          viewer: user,
        )
      end
      assert_equal 2, result[:subscription_item].quantity
    end

    test "sets free users with plan subscriptions to free_with_addons plan" do
      FakeZuora.mock
      plan_subscription = create(:billing_plan_subscription, :zuora, user: create(:user, :zuora, plan: GitHub::Plan.free))
      user = plan_subscription.user
      marketplace_listing_plan = create :marketplace_listing_plan, :verified_listing,
        monthly_price_in_cents: 0,
        yearly_price_in_cents: 0

      result = T.let(nil, T.untyped)
      assert_difference "Billing::SubscriptionItem.count" do
        result = Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 2,
          account: user,
          viewer: user,
        )
      end

      assert_equal 2, result[:subscription_item].quantity
      assert_equal "free_with_addons", user.reload.plan.name
    end

    test "sets free users with sponsors-purpose plan subscription adding marketplace item to free_with_addons plan" do
      FakeZuora.mock
      sponsors_plan_subscription = create(:billing_plan_subscription, :sponsors_invoiced)
      org = sponsors_plan_subscription.user
      org.update!(plan: GitHub::Plan::FREE)

      assert_predicate org, :sponsors_invoiced?, "requires org to pay for sponsorships using a separate Zuora account"
      assert_predicate org.plan, :free?, "requires org to be on a free plan"

      marketplace_listing_plan = create :marketplace_listing_plan, :verified_listing,
        monthly_price_in_cents: 0,
        yearly_price_in_cents: 0

      result = T.let(nil, T.untyped)
      assert_difference "Billing::SubscriptionItem.count" do
        result = Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 2,
          account: org,
          viewer: org.admin,
        )
      end

      assert_equal 2, result[:subscription_item].quantity
      assert_equal "free_with_addons", org.reload.plan.name
    end if GitHub.sponsors_enabled?

    test "updates an existing cancelled item" do
      FakeZuora.mock
      plan_subscription = create(:billing_plan_subscription, :zuora, user: create(:user, :zuora, plan: GitHub::Plan.free_with_addons))
      user = plan_subscription.user
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
      cancelled_item = create :billing_subscription_item, :cancelled,
        plan_subscription: plan_subscription,
        subscribable: marketplace_listing_plan

      # reinstate payment method after cancelled subscription item cancels it
      user.payment_method.update!(attributes_for(:payment_method, :zuora))

      result = T.let(nil, T.untyped)
      assert_no_difference "Billing::SubscriptionItem.count" do
        assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
          result = Billing::CreateMarketplaceSubscriptionItem.call(
            listing_plan: marketplace_listing_plan,
            quantity: 3,
            account: user,
            viewer: user,
          )
        end
      end

      assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
        user_id: user.id, plan_name: user.plan.name, purpose: plan_subscription.purpose,
      }, user: user])
      assert_equal 3, result[:subscription_item].quantity
      assert_equal 3, cancelled_item.reload.quantity
    end

    test "returns an error for invoiced orgs for a paid Marketplace plan" do
      user = create(:user)
      org = create(:invoiced_org, admin: user)
      marketplace_listing_plan = create(:marketplace_listing_plan, :paid, :verified_listing)

      error = assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 3,
          account: org,
          viewer: user,
        )
      end

      expected_message = "Invoiced customers cannot purchase paid Marketplace plans at this time. " \
        "Please contact GitHub Support if you have any questions."
      assert_equal expected_message, error.message
    end

    test "invoiced orgs can use a general-purpose Zuora account for free, non-sponsorship purchases" do
      user = create(:user)
      org = create(:invoiced_org, :sponsors_invoiced, admin: user)
      marketplace_listing_plan = create(:marketplace_listing_plan, :free, :verified_listing)
      assert_nil org.plan_subscription

      result = assert_difference(["Billing::SubscriptionItem.count", "Billing::PlanSubscription.count"]) do
        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 1,
          account: org,
          viewer: user,
        )
      end

      subscription_item = result[:subscription_item]
      refute_nil subscription_item
      assert_equal 1, subscription_item.quantity
      assert_equal marketplace_listing_plan, subscription_item.subscribable
      assert_equal org, subscription_item.account
      plan_subscription = org.reload_plan_subscription
      refute_nil plan_subscription
      assert_equal plan_subscription, subscription_item.plan_subscription
      assert_predicate plan_subscription, :general_purpose?
    end

    test "creates a subscription for invoiced orgs for a free plan" do
      user = create(:user)
      org = create(:invoiced_organization, admin: user)
      marketplace_listing_plan = create(:marketplace_listing_plan, :free, :verified_listing)

      result = T.let(nil, T.untyped)
      assert_difference "Billing::SubscriptionItem.count" do
        result = Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 3,
          account: org,
          viewer: user,
        )
      end

      assert_equal 3, result[:subscription_item].quantity
      assert_equal marketplace_listing_plan.listing.name, result[:subscription_item].subscribable.listing.name
    end

    test "does not create subscription item for billing manager of an organization" do
      user = create(:user)
      org = create(:credit_card_org)
      org.billing.add_manager(user, actor: org.admins.first)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

      error = assert_raises Billing::CreateSubscriptionItem::ForbiddenError do
        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 1,
          account: org,
          viewer: user,
        )
      end
      assert_equal "#{user} does not have permission to manage this account (#{org})", error.message
    end

    test "requires a quantity greater than zero" do
      FakeZuora.mock
      plan_subscription = create(:billing_plan_subscription, :zuora, user: create(:user, :zuora, plan: GitHub::Plan.free_with_addons))
      user = plan_subscription.user
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

      error = assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 0,
          account: user,
          viewer: user,
        )
      end
      assert_equal "Quantity must be greater than 0.", error.message
    end

    test "whitelists the listing's oauth application if :grantOap is specified" do
      FakeZuora.mock
      user = create(:user)
      org = create(:organization, :zuora, admin: user)
      create(:billing_plan_subscription, :zuora, user: org)
      org.enable_oauth_application_restrictions
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
      oauth_app = marketplace_listing_plan.listing.listable

      assert Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: marketplace_listing_plan,
        quantity: 3,
        account: org,
        grant_oap: true,
        viewer: user,
      )
      assert org.allows_oauth_application?(oauth_app), "OAuth app should be whitelisted"
    end

    test "returns an error for trade restricted users" do
      user = create(:user, :fully_trade_restricted)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

      error = assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 3,
          account: user,
          viewer: user,
        )
      end
      assert_equal TradeControls::Notices.notice_as_plaintext(:user_account_restricted), error.message
    end

    test "instruments marketplace_purchase.purchased event with an order preview" do
      FakeZuora.mock
      user = create(:user)
      org = create(:organization, :zuora, admin: user)
      plan_sub = create(:billing_plan_subscription, :zuora, user: org)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
      listing = marketplace_listing_plan.listing
      order_preview = create(:marketplace_order_preview, listing: listing, listing_plan: marketplace_listing_plan,
        user: user, email_notification_sent_at: 1.day.ago)
      SynchronizePlanSubscriptionJob.expects(:perform_later).with({
        user_id: org.id, plan_name: org.plan.name, purpose: plan_sub.purpose,
      }, user: org)
      events = subscribe("marketplace_purchase.purchased")
      expected_payload = {
        sender_id: user.id,
        order_preview_viewed_at: order_preview.viewed_at,
        order_preview_email_notification_sent_at: order_preview.email_notification_sent_at,
      }

      result = Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: marketplace_listing_plan, quantity: 3, account: org, viewer: user,
      )

      refute_nil event = events.pop, "an event was expected"
      subscription_item = result[:subscription_item]
      expected_payload[:subscription_item_id] = subscription_item.id
      assert_equal expected_payload, event.payload
    end

    test "instruments marketplace_purchase.purchased event without an order preview" do
      FakeZuora.mock
      user = create(:user)
      org = create(:organization, :zuora, admin: user)
      plan_sub = create(:billing_plan_subscription, :zuora, user: org)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
      listing = marketplace_listing_plan.listing
      SynchronizePlanSubscriptionJob.expects(:perform_later).with({
        user_id: org.id, plan_name: org.plan.name, purpose: plan_sub.purpose,
      }, user: org)
      events = subscribe("marketplace_purchase.purchased")
      expected_payload = { sender_id: user.id }

      result = Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: marketplace_listing_plan, quantity: 3, account: org, viewer: user,
      )

      refute_nil event = events.pop, "an event was expected"
      subscription_item = result[:subscription_item]
      expected_payload[:subscription_item_id] = subscription_item.id
      assert_equal expected_payload, event.payload
    end

    test "does not use Sponsors-specific plan subscription for a Marketplace subscribable" do
      FakeZuora.mock
      default_plan_sub = create(:billing_plan_subscription)
      user = default_plan_sub.user
      sponsors_plan_sub = create(:billing_plan_subscription, :sponsors_invoiced, user: user)
      marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

      result = T.let(nil, T.untyped)
      assert_difference "Billing::SubscriptionItem.count" do
        assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
          result = Billing::CreateMarketplaceSubscriptionItem.call(
            listing_plan: marketplace_listing_plan,
            quantity: 1,
            account: user,
            viewer: user,
          )
        end
      end

      assert_performed_with(
        job: SynchronizePlanSubscriptionJob,
        args: [{ user_id: user.id, plan_name: user.plan.name, purpose: default_plan_sub.purpose }, user: user]
      )
      sub_item = result[:subscription_item]
      refute_nil sub_item
      assert_equal default_plan_sub, sub_item.plan_subscription
      assert_equal 1, sub_item.quantity
      assert_equal marketplace_listing_plan, sub_item.subscribable
    end

    context "self-serve payment enterprise account orgs" do
      test "returns an error if no payment information" do
        business = create :business, :with_self_serve_payment, trial_expires_at: 1.week.from_now
        # Remove the payment details to mimic an EA trial that hasn't entered any payment information yet
        business.payment_method.delete
        business.reload

        user = business.owners.first
        org = create :organization, business: business, admin: user
        marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

        error = assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
          Billing::CreateMarketplaceSubscriptionItem.call(
            listing_plan: marketplace_listing_plan,
            quantity: 2,
            account: business,
            installation_account: org,
            viewer: user,
          )
        end
        assert_equal "Please add a payment method before checking out.", error.message
      end

      test "creates a subscription item for the specified account's subscription" do
        FakeZuora.mock
        business = create :business, :with_self_serve_payment
        user = business.owners.first
        org = create :organization, business: business, admin: user
        plan_sub = create :billing_plan_subscription, :zuora, customer: business.customer

        marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

        result = T.let(nil, T.untyped)
        assert_difference "Billing::SubscriptionItem.count" do
          assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
            result = Billing::CreateMarketplaceSubscriptionItem.call(
              listing_plan: marketplace_listing_plan,
              quantity: 3,
              account: business,
              installation_account: org,
              viewer: user,
            )
          end
        end

        assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
          business_id: business.id, plan_name: org.plan.name, purpose: plan_sub.purpose,
        }, business: business])
        assert_equal 3, result[:subscription_item].quantity
        assert_equal marketplace_listing_plan.listing.name, result[:subscription_item].subscribable.listing.name
      end

      test "creates a subscription item for the same plan on two different orgs" do
        FakeZuora.mock
        business = create :business, :with_self_serve_payment
        user = business.owners.first
        org1 = create :organization, business: business, admin: user
        org2 = create :organization, business: business, admin: user
        plan_sub = create :billing_plan_subscription, :zuora, customer: business.customer

        marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

        result_org1 = T.let(nil, T.untyped)
        result_org2 = T.let(nil, T.untyped)
        assert_difference "Billing::SubscriptionItem.count", 2 do
          assert_performed_jobs(2, only: SynchronizePlanSubscriptionJob) do
            result_org1 = Billing::CreateMarketplaceSubscriptionItem.call(
              listing_plan: marketplace_listing_plan,
              quantity: 3,
              account: business,
              installation_account: org1,
              viewer: user,
            )
            result_org2 = Billing::CreateMarketplaceSubscriptionItem.call(
              listing_plan: marketplace_listing_plan,
              quantity: 2,
              account: business,
              installation_account: org2,
              viewer: user,
            )
          end
        end

        assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
          business_id: business.id, plan_name: org1.plan.name, purpose: plan_sub.purpose,
        }, business: business])
        assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
          business_id: business.id, plan_name: org2.plan.name, purpose: plan_sub.purpose,
        }, business: business])
        assert_equal 3, result_org1[:subscription_item].quantity
        assert_equal marketplace_listing_plan.listing.name, result_org1[:subscription_item].subscribable.listing.name

        assert_equal 2, result_org2[:subscription_item].quantity
        assert_equal marketplace_listing_plan.listing.name, result_org2[:subscription_item].subscribable.listing.name
      end

      test "sends a marketplace subscription purchased event" do
        FakeZuora.mock
        business = create :business, :with_self_serve_payment
        user = business.owners.first
        org = create :organization, business: business, admin: user
        plan_sub = create :billing_plan_subscription, :zuora, customer: business.customer

        marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
        listing = marketplace_listing_plan.listing

        hook = create :hook, :web,
          installation_target: listing,
          events: %w(marketplace_purchase)
        deliveries = subscribe_to_hook_delivery "marketplace_purchase"

        SynchronizePlanSubscriptionJob.expects(:perform_later).with({
          business_id: business.id, plan_name: org.plan.name, purpose: plan_sub.purpose,
        }, business: business)

        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 3,
          account: business,
          installation_account: org,
          viewer: user,
        )

        assert_equal 1, deliveries.count
        assert_includes deliveries.hooks, hook

        payload = deliveries.payload_for_hook(hook)
        assert_equal "purchased", payload[:action]
        assert_equal org.id, payload[:marketplace_purchase][:account][:id]
        assert_equal org.login, payload[:marketplace_purchase][:account][:login]
        assert_equal marketplace_listing_plan.id, payload[:marketplace_purchase][:plan][:id]
      end

      test "verifies the publishing of the marketplace subscription purchased hydro event without an order preview" do
        FakeZuora.mock
        business = create :business, :with_self_serve_payment
        user = business.owners.first
        org = create :organization, business: business, admin: user
        plan_sub = create :billing_plan_subscription, :zuora, customer: business.customer

        marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
        listing = marketplace_listing_plan.listing

        hook = create :hook, :web,
          installation_target: listing,
          events: %w(marketplace_purchase)
        deliveries = subscribe_to_hook_delivery "marketplace_purchase"

        SynchronizePlanSubscriptionJob.expects(:perform_later).with({
          business_id: business.id, plan_name: org.plan.name, purpose: plan_sub.purpose,
        }, business: business)

        result = Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 3,
          account: business,
          installation_account: org,
          viewer: user,
        )
        subscription_item = result[:subscription_item]

        expected_hydro_payload = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(user),
          account: Hydro::EntitySerializer.user(org),
          subscription_item_id: subscription_item.id,
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          marketplace_listing_plan: Hydro::EntitySerializer.marketplace_listing_plan(marketplace_listing_plan),
        }

        assert_hydro_published(expected_hydro_payload, schema: "github.marketplace.v0.PurchasePurchased")
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.PurchasePurchased")
      end

      test "verifies the publishing of the marketplace subscription purchased hydro event with an order preview" do
        FakeZuora.mock
        business = create :business, :with_self_serve_payment
        user = business.owners.first
        org = create :organization, business: business, admin: user
        plan_sub = create :billing_plan_subscription, :zuora, customer: business.customer

        marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
        listing = marketplace_listing_plan.listing
        order_preview = create(:marketplace_order_preview, listing: listing, listing_plan: marketplace_listing_plan,
          user: user, email_notification_sent_at: 1.day.ago)

        hook = create :hook, :web,
          installation_target: listing,
          events: %w(marketplace_purchase)
        deliveries = subscribe_to_hook_delivery "marketplace_purchase"

        SynchronizePlanSubscriptionJob.expects(:perform_later).with({
          business_id: business.id, plan_name: org.plan.name, purpose: plan_sub.purpose,
        }, business: business)

        result = Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 3,
          account: business,
          installation_account: org,
          viewer: user,
        )
        subscription_item = result[:subscription_item]

        expected_hydro_payload = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(user),
          account: Hydro::EntitySerializer.user(org),
          subscription_item_id: subscription_item.id,
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          marketplace_listing_plan: Hydro::EntitySerializer.marketplace_listing_plan(marketplace_listing_plan),
          order_preview_viewed_at: order_preview.viewed_at,
          order_preview_email_notification_sent_at: order_preview.email_notification_sent_at,
        }

        assert_hydro_published(expected_hydro_payload, schema: "github.marketplace.v0.PurchasePurchased")
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.PurchasePurchased")
      end

      test "resets the viewer's pending installation notice for a new subscription" do
        FakeZuora.mock
        business = create :business, :with_self_serve_payment
        user = business.owners.first
        org = create :organization, business: business, admin: user
        marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

        notice = Marketplace::PendingInstallations::Notice.new(user_id: user.id)
        notice.dismiss

        assert_predicate notice, :dismissed?

        Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 1,
          account: business,
          installation_account: org,
          viewer: user,
        )

        refute notice.dismissed?
      end

      test "when org has already installed app, sets installed_at for subscription item & subscription_item_id for integration installation" do
        business = create :business, :with_self_serve_payment
        user = business.owners.first
        org = create :organization, business: business, admin: user
        integration_installation = make_integration_installation(target: org)
        listing = create(:marketplace_listing, :verified, :with_plans, listable: integration_installation.integration)

        result = Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: listing.listing_plans.first,
          quantity: 1,
          account: business,
          installation_account: org,
          viewer: user,
        )

        subscription_item = result[:subscription_item]
        integration_installation.reload

        assert_equal integration_installation.created_at, subscription_item.installed_at
        assert_equal integration_installation.subscription_item_id, subscription_item.id
      end

      test "when org has not already installed app, does not set installed_at for subscription item" do
        business = create :business, :with_self_serve_payment
        user = business.owners.first
        org = create :organization, business: business, admin: user
        listing = create(:marketplace_listing, :verified, :with_plans, :integration)

        result = Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: listing.listing_plans.first,
          quantity: 1,
          account: business,
          installation_account: org,
          viewer: user,
        )

        subscription_item = result[:subscription_item]
        assert_nil subscription_item.installed_at
      end

      test "when app has been installed on org account, does not set installed_at for subscription item on an admin's personal account & subscription_item_id for org integration installation" do
        user = create(:credit_card_user)
        business = create :business, :with_self_serve_payment
        business.add_owner(user, actor: nil)
        org = create :organization, business: business, admin: user
        integration_installation = make_integration_installation(target: org)
        listing = create(:marketplace_listing, :verified, :with_plans, listable: integration_installation.integration)

        inputs = {
          listing_plan: listing.listing_plans.first,
          quantity: 1,
          account: user,
          viewer: user,
        }
        result = Billing::CreateMarketplaceSubscriptionItem.call(**inputs)
        subscription_item = result[:subscription_item]
        integration_installation.reload

        assert_nil subscription_item.installed_at
        assert_nil integration_installation.subscription_item_id
      end

      test "raises an error for an Org trying to subscribe to a User only plan" do
        business = create :business, :with_self_serve_payment
        user = business.owners.first
        org = create :organization, business: business, admin: user
        marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing, :users_only)

        error = assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
          Billing::CreateMarketplaceSubscriptionItem.call(
            listing_plan: marketplace_listing_plan,
            quantity: 1,
            account: business,
            installation_account: org,
            viewer: user,
          )
        end
        expected_message = "Could not purchase this item: This plan is for personal accounts only, " \
          "please select a different billing account or plan."
        assert_equal expected_message, error.message
      end

      test "does not create subscription item for org admin that is not an EA owner" do
        business = create :business, :with_self_serve_payment
        org = create :organization, business: business
        user = org.admins.first

        marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)

        error = assert_raises Billing::CreateSubscriptionItem::ForbiddenError do
          Billing::CreateMarketplaceSubscriptionItem.call(
            listing_plan: marketplace_listing_plan,
            quantity: 1,
            account: business,
            installation_account: org,
            viewer: user,
          )
        end
        assert_equal "#{user} does not have permission to manage this account (#{business})", error.message
      end

      test "whitelists the listing's oauth application if :grantOap is specified" do
        FakeZuora.mock
        business = create :business, :with_self_serve_payment
        user = business.owners.first
        org = create :organization, business: business, admin: user
        plan_subscription = create :billing_plan_subscription, :zuora, customer: business.customer
        org.enable_oauth_application_restrictions
        marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
        oauth_app = marketplace_listing_plan.listing.listable

        assert Billing::CreateMarketplaceSubscriptionItem.call(
          listing_plan: marketplace_listing_plan,
          quantity: 3,
          account: business,
          installation_account: org,
          grant_oap: true,
          viewer: user,
        )
        assert org.allows_oauth_application?(oauth_app), "OAuth app should be whitelisted"
      end
    end

    context "free trials" do
      test "requires payment information" do
        user = create(:user)
        marketplace_listing_plan = create :marketplace_listing_plan,
          :verified_listing, has_free_trial: true

        error = assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
          Billing::CreateMarketplaceSubscriptionItem.call(
            listing_plan: marketplace_listing_plan,
            quantity: 3,
            account: user,
            viewer: user,
          )
        end
        assert_equal "Please add a payment method before checking out.", error.message
      end

      test "schedules a pending plan change if the item has a free trial" do
        self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
        plan_subscription = create(:billing_plan_subscription, :zuora)
        user = plan_subscription.user
        marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing, has_free_trial: true)

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::CreateMarketplaceSubscriptionItem.call(
            listing_plan: marketplace_listing_plan,
            quantity: 3,
            account: user,
            viewer: user,
          )
        end

        change = user.reload.pending_subscription_item_changes.first
        assert_equal marketplace_listing_plan, change.subscribable
        assert_equal 3, change.quantity
      end

      test "does not create multiple pending plan changes for the same free trial" do
        self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
        plan_subscription = create(:billing_plan_subscription, :zuora)
        user = plan_subscription.user
        marketplace_listing_plan = create(:marketplace_listing_plan, :free_trial)

        inputs = {
          listing_plan: marketplace_listing_plan,
          quantity: 3,
          account: user,
          viewer: user,
        }

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::CreateMarketplaceSubscriptionItem.call(**inputs)
        end

        change = user.reload.pending_subscription_item_changes.first
        assert_equal marketplace_listing_plan, change.subscribable
        assert_equal 3, change.quantity

        initial_count = Billing::SubscriptionItem.count
        error = assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
          Billing::CreateMarketplaceSubscriptionItem.call(**inputs)
        end
        assert_equal "Could not purchase this item: already has an active subscription " \
          "for #{marketplace_listing_plan.name}", error.message
        assert_equal initial_count, Billing::SubscriptionItem.count

        # For cancelled items
        change.destroy
        subscription_item = user.reload.subscription_items.last
        subscription_item.update!(quantity: 0, free_trial_ends_on: GitHub::Billing.yesterday)

        assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
          Billing::CreateMarketplaceSubscriptionItem.call(**inputs)
        end

        subscription_item.reload
        assert_equal 3, subscription_item.quantity
        refute subscription_item.on_free_trial?
      end

      test "creates a subscription item with free trial for a free user" do
        self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

        user = create :credit_card_user
        marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing, has_free_trial: true)

        result = T.let(nil, T.untyped)
        assert_difference "Billing::SubscriptionItem.count" do
          result = Billing::CreateMarketplaceSubscriptionItem.call(
            listing_plan: marketplace_listing_plan,
            quantity: 2,
            account: user,
            viewer: user,
          )
        end

        assert_equal 2, result[:subscription_item].quantity
        assert_equal marketplace_listing_plan.listing.name, result[:subscription_item].subscribable.listing.name
        assert_equal GitHub::Plan.find!("free_with_addons"), user.reload.plan
        assert_equal 1, user.reload.pending_subscription_item_changes.count
      end

      context "self-serve payment enterprise account orgs" do
        test "schedules a pending plan change if the item has a free trial" do
          self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

          assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
            Billing::CreateMarketplaceSubscriptionItem.call(
              listing_plan: @marketplace_free_trial_listing_plan,
              quantity: 3,
              account: @business,
              viewer: @business_owner_org_admin,
              installation_account: @business_org
            )
          end

          change = @business.reload.pending_subscription_item_changes.first
          assert_equal @marketplace_free_trial_listing_plan, change.subscribable
          assert_equal @business_org, change.organization
          assert_equal 3, change.quantity
        end

        test "schedules a pending plan change only for the first org if the item has a free trial when installed on multiple orgs" do
          self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

          assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
            [@business_org, @business_org2].each do |org|
              Billing::CreateMarketplaceSubscriptionItem.call(
                listing_plan: @marketplace_free_trial_listing_plan,
                quantity: 3,
                account: @business,
                viewer: @business_owner_org_admin,
                installation_account: org
              )
            end
          end

          assert_equal 1, @business.reload.pending_subscription_item_changes.count

          change = @business.pending_subscription_item_changes.first
          assert_equal @marketplace_free_trial_listing_plan, change.subscribable
          assert_equal @business_org, change.organization
          assert_equal 3, change.quantity
        end

        test "does not create multiple pending plan changes for the same free trial" do
          self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

          inputs = {
            listing_plan: @marketplace_free_trial_listing_plan,
            quantity: 3,
            account: @business,
            viewer: @business_owner_org_admin,
            installation_account: @business_org
          }

          assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
            Billing::CreateMarketplaceSubscriptionItem.call(**inputs)
          end

          change = @business.reload.pending_subscription_item_changes.first
          assert_equal @marketplace_free_trial_listing_plan, change.subscribable
          assert_equal @business_org, change.organization
          assert_equal 3, change.quantity

          initial_count = Billing::SubscriptionItem.count
          error = assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
            Billing::CreateMarketplaceSubscriptionItem.call(**inputs)
          end
          assert_equal "Could not purchase this item: already has an active subscription " \
            "for #{@marketplace_free_trial_listing_plan.name}", error.message
          assert_equal initial_count, Billing::SubscriptionItem.count

          # For cancelled items
          change.destroy
          subscription_item = @business.reload.subscription_items.last
          subscription_item.update!(quantity: 0, free_trial_ends_on: GitHub::Billing.yesterday)

          assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
            Billing::CreateMarketplaceSubscriptionItem.call(**inputs)
          end

          subscription_item.reload
          assert_equal 3, subscription_item.quantity
          refute subscription_item.on_free_trial?
        end
      end
    end
  end
end
