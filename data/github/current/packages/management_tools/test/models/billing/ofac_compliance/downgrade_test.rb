# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::OFACCompliance::DowngradeTest < GitHub::BillingTestCase
  include ActionMailer::TestHelper

  fixtures do
    @user = create(:user, :zuora, :fully_trade_restricted, plan: GitHub::Plan.pro)
    GitHub.flipper[:active_job_replica_clusters_only].enable
  end

  setup do
    FakeZuora.mock # So we don't reach out to Zuora in general
  end

  context ".perform" do
    test "does not attempt to downgrade a user if they are not flagged" do
      ::Billing::Zuora::ZeroOutInvoices.expects(:for_account).never
      plan_subscription = create(:billing_plan_subscription, :zuora, user: @user)

      subscription_item = create(:billing_subscription_item, plan_subscription: plan_subscription)
      @user.trade_controls_restriction.unrestricted!

      assert_equal 1, subscription_item.quantity
      assert @user.plan.paid?
      assert plan_subscription.zuora_subscription_number

      Billing::OFACCompliance::Downgrade.perform(@user, actor: @user)

      @user.reload

      assert @user.plan.paid?
      assert_equal 1, subscription_item.reload.quantity
      assert plan_subscription.zuora_subscription_number
    end

    test "cancels the user's general-purpose subscription and subscription items" do
      plan_subscription = create(:billing_plan_subscription, :zuora, user: @user)
      subscription_item = create(:billing_subscription_item, plan_subscription: plan_subscription)
      Asset::Status.create! owner: @user, asset_packs: 3

      assert_equal 1, subscription_item.quantity
      assert @user.plan.paid?
      assert plan_subscription.zuora_subscription_number
      assert_equal 3, @user.data_packs

      Billing::OFACCompliance::Downgrade.perform(@user, actor: @user)

      @user.reload
      plan_subscription.reload

      assert @user.plan.free?
      assert subscription_item.reload.quantity.zero?
      refute plan_subscription.zuora_subscription_number
      assert @user.data_packs.zero?
    end

    test "cancels the user's Sponsors-specific subscription and subscription items" do
      sponsors_plan_sub = create(:billing_plan_subscription, :zuora, :sponsors_invoiced, user: @user, customer: @user.customer)
      subscription_item = create(:sponsors_subscription_item,
        plan_subscription: sponsors_plan_sub)

      assert_equal 1, subscription_item.quantity
      assert_predicate @user.plan, :paid?
      refute_nil sponsors_plan_sub.zuora_subscription_number
      refute_nil sponsors_plan_sub.zuora_subscription_id

      Billing::OFACCompliance::Downgrade.perform(@user, actor: @user)

      assert_predicate @user.reload.plan, :free?
      assert_equal 0, subscription_item.reload.quantity
      assert_nil sponsors_plan_sub.reload.zuora_subscription_number
      assert_nil sponsors_plan_sub.zuora_subscription_id
    end if GitHub.sponsors_enabled?

    test "resets billing related information" do
      @user.update_columns(billed_on: ::GitHub::Billing.today, billing_attempts: 2)

      Billing::OFACCompliance::Downgrade.perform(@user, actor: @user)

      @user.reload

      assert @user.billing_attempts.zero?
      refute @user.billed_on
    end

    test "payment methods are removed" do
      assert_predicate @user, :has_valid_payment_method?

      Billing::OFACCompliance::Downgrade.perform(@user, actor: @user)

      refute @user.has_valid_payment_method?
    end

    test "deactivates any associated sponsorship records for sponsors" do
      create(:billing_plan_subscription, user: @user)
      sponsorship = create(:sponsorship, sponsor: @user)
      other_sponsorship = create(:sponsorship, sponsorable: sponsorship.sponsorable)
      subscription_item = sponsorship.subscription_item
      listing = sponsorship.sponsors_listing
      @user.reload

      assert_predicate listing, :approved?
      assert_predicate sponsorship, :active?
      assert_predicate other_sponsorship, :active?
      assert_predicate sponsorship.subscription_item, :active?
      assert_equal 1, @user.active_sponsorships_as_sponsor_relation.count

      Billing::OFACCompliance::Downgrade.perform(@user, actor: @user)

      @user.reload

      assert_predicate listing.reload, :approved?
      refute_predicate sponsorship.reload, :active?
      assert_predicate other_sponsorship.reload, :active?
      refute_predicate subscription_item.reload, :active?
      assert @user.active_sponsorships_as_sponsor_relation.count.zero?
    end

    test "deactivates any associated sponsorship records for sponsorables" do
      staff_user = create(:staff_admin_user)
      sponsorable = create(:user,
        :sponsorable,
        :zuora,
        :fully_trade_restricted,
        plan: GitHub::Plan.pro
      )
      create(:billing_plan_subscription, user: sponsorable)
      sponsored = create(:sponsorship, sponsorable: sponsorable)
      sponsoring = create(:sponsorship, sponsor: sponsorable)
      other_sponsorship = create(:sponsorship, sponsorable: sponsoring.sponsorable)
      listing = sponsorable.sponsors_listing

      assert_predicate listing, :approved?
      assert_predicate sponsored, :active?
      assert_predicate sponsoring, :active?
      assert_predicate other_sponsorship, :active?
      assert_predicate sponsored.subscription_item, :active?
      assert_predicate sponsoring.subscription_item, :active?
      assert_predicate sponsorable.active_sponsorships_as_sponsor_relation, :any?
      refute_empty sponsorable.active_sponsorships_as_sponsorable

      Billing::OFACCompliance::Downgrade.perform(sponsorable, actor: staff_user)

      sponsorable.reload

      assert_predicate listing.reload, :banned?
      assert_equal staff_user, listing.reload_stafftools_metadata.banned_by
      assert_equal "OFAC compliance", listing.stafftools_metadata.banned_reason
      refute_predicate sponsored.reload, :active?
      refute_predicate sponsoring.reload, :active?
      assert_predicate other_sponsorship.reload, :active?
      refute_predicate sponsored.subscription_item.reload, :active?
      refute_predicate sponsoring.subscription_item.reload, :active?
      assert_predicate sponsorable.active_sponsorships_as_sponsor_relation, :empty?
      assert_empty sponsorable.active_sponsorships_as_sponsorable
    end

    test "destroy metered billing configurations" do
      create(:billing_budget, owner: @user, enforce_spending_limit: true, spending_limit_in_subunits: 5000)

      Billing::OFACCompliance::Downgrade.perform(@user, actor: @user)

      @user.reload

      assert_equal 0, @user.budget_for(group: "shared").spending_limit_in_subunits
      assert @user.budget_for(group: "shared").enforce_spending_limit
    end

    test "expires active coupon redemptions" do
      coupon_redemption = create(:coupon_redemption, billable_entity: @user)
      refute coupon_redemption.expired?

      Billing::OFACCompliance::Downgrade.perform(@user, actor: @user)

      coupon_redemption.reload

      assert_predicate coupon_redemption, :expired?
    end

    test "cancels the users org invitations" do
      free_org = create(:free_organization)

      paid_invite = create(:organization_invitation, invitee: @user)
      free_invite = create(:organization_invitation, organization: free_org, invitee: @user)

      @user.reload

      assert_equal 2, OrganizationInvitation.where(invitee_id: @user.id).count

      Billing::OFACCompliance::Downgrade.perform(@user, actor: @user)

      [paid_invite, free_invite].map(&:reload)

      assert_predicate paid_invite, :cancelled?
      refute_predicate free_invite, :cancelled?
    end

    test "sends zero emails to the flagged user about the downgrade process" do
      org               = create(:organization)
      org_to_downgrade  = create(:organization)
      non_flagged_user  = create(:user)

      create(:organization_invitation, invitee: @user)
      create(:coupon_redemption, billable_entity: @user)

      create(:billing_subscription_item, account: org)
      create(:sponsors_subscription_item, account: org)

      org.add_member(non_flagged_user)
      org.add_member(@user)

      org_to_downgrade.add_member(@user)

      @user.reload

      only = []
      perform_enqueued_jobs(only: only) do
        assert_no_emails do
          Billing::OFACCompliance::Downgrade.perform(@user, actor: @user)
        end
      end
    end

    test "limits queries for user account" do
      create_pair(:organization_invitation, invitee: @user)
      create_pair(:sponsorship, sponsor: @user)

      expected_queries = {
        asset_statuses: 1,
        billing_budgets: 1,
        business_organization_memberships: 3,
        business_user_accounts: 1,
        businesses: 3,
        coupon_redemptions: 1,
        customers: 2,
        flipper_gates: 0,
        organization_invitations: 3,
        payment_methods: 2, # one read, one write
        plan_subscriptions: 2, # one read, one write
        profiles: 2,
        sponsorships: 3, # one read, two writes
        sponsors_listings: 1,
        subscription_items: 3, # one read, two writes
        trade_controls_restrictions: 1,
        user_emails: 1,
        users: 7,
      }

      # clear associations loaded by factories
      @user.reload

      assert_query_count(expected_queries.values.sum) do
        assert_query_count_per_table(expected_queries, backtrace_lines: 10) do
          Billing::OFACCompliance::Downgrade.perform(@user, actor: @user)
        end
      end
    end

    test "limits queries for organization account" do
      org = create(:organization, :zuora)
      plan_subscription = create(:billing_plan_subscription, :zuora, user: org)
      create(:billing_subscription_item, plan_subscription: plan_subscription)
      Asset::Status.create!(owner: org, asset_packs: 3)
      org.trade_controls_restriction.full!

      expected_queries = {
        asset_statuses: 2, # one read, one write
        billing_budgets: 1,
        business_user_accounts: 1,
        coupon_redemptions: 1,
        customers: 1,
        flipper_gates: 0,
        organization_invitations: 1,
        payment_methods: 1,
        plan_subscriptions: 2, # one read, one write
        sponsorships: 1,
        sponsors_listings: 1,
        subscription_items: 2, # one read, one write
        users: 2,
      }

      assert_query_count(expected_queries.values.sum) do
        assert_query_count_per_table(expected_queries) do
          Billing::OFACCompliance::Downgrade.perform(org, actor: org)
        end
      end
    end

    test "works for organization accounts as well" do
      org = create(:organization, :zuora)
      plan_subscription = create(:billing_plan_subscription, :zuora, user: org)

      subscription_item = create(:billing_subscription_item, plan_subscription: plan_subscription)
      Asset::Status.create! owner: org, asset_packs: 3

      assert_equal 1, subscription_item.quantity
      assert org.plan.paid?
      assert plan_subscription.zuora_subscription_number
      assert_equal 3, org.data_packs

      org.trade_controls_restriction.full!

      Billing::OFACCompliance::Downgrade.perform(org, actor: org)

      org.reload
      plan_subscription.reload

      assert org.plan.free?
      assert subscription_item.reload.quantity.zero?
      refute plan_subscription.zuora_subscription_number
      assert org.data_packs.zero?
    end
  end
end
