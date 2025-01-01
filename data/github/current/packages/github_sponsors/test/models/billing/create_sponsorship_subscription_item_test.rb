# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::CreateSponsorshipSubscriptionItemTest < GitHub::TestCase
  include GitHub::SponsorsZuoraTestHelper
  include GitHub::ZuoraTestHelper

  fixtures do
    @user = create(:credit_card_user)
    @sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
    @general_purpose_plan_sub = create(:billing_plan_subscription)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  # https://github.com/github/sponsors/issues/4928
  test "rehomes existing Sponsors subscription to the Sponsors customer when it's tied to the general customer" do
    org = create(:credit_card_organization, admin: @user)
    general_customer = org.customer
    assert_predicate general_customer, :general_purpose?, "need a general-purpose Customer"
    sponsors_plan_sub = create(:billing_plan_subscription, :sponsors_invoiced, customer: general_customer, user: org)
    assert_predicate sponsors_plan_sub, :cancelled_or_non_zuora?
    sponsors_customer = create(:customer_account, :zuora, :sponsors_invoiced, user: org).customer
    assert_equal sponsors_customer, org.reload.sponsors_customer
    assert_nil sponsors_customer.sponsors_plan_subscription, "need the Sponsors customer to have no subscription yet"
    ::Billing::Zuora::Account.any_instance.stubs(:credit_balance).returns(@sponsors_tier.base_price)

    result = assert_no_difference("Billing::PlanSubscription.count") do
      assert_difference("Billing::SubscriptionItem.count") do
        Billing::CreateSponsorshipSubscriptionItem.call(tier: @sponsors_tier, sponsor: org, viewer: @user)
      end
    end

    subscription_item = result[:subscription_item]
    refute_nil subscription_item
    assert_equal sponsors_plan_sub, subscription_item.plan_subscription,
      "expected new sponsorship sub item to use the existing Sponsors subscription"
    assert_equal sponsors_customer, sponsors_plan_sub.reload.customer,
      "expected Sponsors plan subscription to be switched to Sponsors customer"
    assert_nil general_customer.reload.sponsors_plan_subscription,
      "expected general-purpose customer to no longer have a Sponsors plan subscription"
    assert_equal 1, subscription_item.quantity
    assert_equal @sponsors_tier, subscription_item.subscribable
    assert_equal org, subscription_item.account
  end

  test "errors if rehoming plan subscription to customer does not succeed" do
    org = create(:credit_card_organization, admin: @user)
    general_customer = org.customer
    assert_predicate general_customer, :general_purpose?, "need a general-purpose Customer"
    sponsors_plan_sub = create(:billing_plan_subscription, :sponsors_invoiced, customer: general_customer, user: org)
    assert_predicate sponsors_plan_sub, :cancelled_or_non_zuora?
    sponsors_customer = create(:customer_account, :zuora, :sponsors_invoiced, user: org).customer
    assert_equal sponsors_customer, org.reload.sponsors_customer
    assert_nil sponsors_customer.sponsors_plan_subscription, "need the Sponsors customer to have no subscription yet"
    ::Billing::Zuora::Account.any_instance.stubs(:credit_balance).returns(@sponsors_tier.base_price)

    fake_errors = stub(full_messages: ["o noes", "dear me"])
    Billing::PlanSubscription.any_instance.expects(:update).once.with(customer: sponsors_customer).returns(false)
    Billing::PlanSubscription.any_instance.stubs(:errors).returns(fake_errors)

    error = assert_no_difference(["Billing::PlanSubscription.count", "Billing::SubscriptionItem.count"]) do
      assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
        Billing::CreateSponsorshipSubscriptionItem.call(tier: @sponsors_tier, sponsor: org, viewer: @user)
      end
    end

    assert_equal "Could not purchase this item: o noes, dear me", error.message
  end

  test "errors if active subscription exists but is on the wrong customer" do
    org = create(:credit_card_organization, admin: @user)
    general_customer = org.customer
    assert_predicate general_customer, :general_purpose?, "need a general-purpose Customer"
    sponsors_plan_sub = create(:billing_plan_subscription, :zuora, :sponsors_invoiced, customer: general_customer, user: org)
    refute_predicate sponsors_plan_sub, :cancelled_or_non_zuora?
    sponsors_customer = create(:customer_account, :zuora, :sponsors_invoiced, user: org).customer
    assert_equal sponsors_customer, org.reload.sponsors_customer
    assert_nil sponsors_customer.sponsors_plan_subscription, "need the Sponsors customer to have no subscription yet"
    ::Billing::Zuora::Account.any_instance.stubs(:credit_balance).returns(@sponsors_tier.base_price)

    error = assert_no_difference(["Billing::PlanSubscription.count", "Billing::SubscriptionItem.count"]) do
      assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
        Billing::CreateSponsorshipSubscriptionItem.call(tier: @sponsors_tier, sponsor: org, viewer: @user)
      end
    end

    assert_equal "Subscription (Sponsors-specific) is not on the right account (Sponsors-specific), but is still " \
      "active so a new subscription cannot be created on the right account.", error.message
  end

  test "returns an error for invoiced orgs for a sponsorship subscription without a sponsorship-specific Zuora account" do
    org = create(:invoiced_org, admin: @user)

    error = assert_no_difference -> { Billing::SubscriptionItem.count } do
      assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
        Billing::CreateSponsorshipSubscriptionItem.call(tier: @sponsors_tier, sponsor: org, viewer: @user)
      end
    end

    expected_message = "Please contact support to sponsor #{@sponsors_tier.sponsorable} via invoice."
    assert_equal expected_message, error.message
  end

  test "disallows users to use a sponsorship-specific Zuora account" do
    sponsors_customer = create(:customer, :zuora, :sponsors_invoiced)
    create(:customer_account, :sponsors_invoiced, customer: sponsors_customer, user: @user)

    error = assert_no_difference -> { Billing::SubscriptionItem.count } do
      assert_raises Billing::CreateSubscriptionItem::UnprocessableError do
        Billing::CreateSponsorshipSubscriptionItem.call(tier: @sponsors_tier, sponsor: @user, viewer: @user)
      end
    end

    assert_equal "Only organizations can sponsor from a sponsorship-specific account", error.message
  end

  test "allows invoiced org with sponsorship-specific Zuora account to create a sponsorship subscription" do
    stub_credit_balance do
      org = create(:invoiced_org, :sponsors_invoiced, admin: @user)
      assert_nil org.sponsors_plan_subscription

      result = assert_difference(["Billing::PlanSubscription.count", "Billing::SubscriptionItem.count"]) do
        Billing::CreateSponsorshipSubscriptionItem.call(tier: @sponsors_tier, sponsor: org, viewer: @user)
      end

      subscription_item = result[:subscription_item]
      refute_nil subscription_item
      assert_equal 1, subscription_item.quantity
      assert_equal @sponsors_tier, subscription_item.subscribable
      assert_equal org, subscription_item.account
      sponsors_plan_sub = org.reload_sponsors_plan_subscription
      refute_nil sponsors_plan_sub
      assert_equal sponsors_plan_sub, subscription_item.plan_subscription
      assert_predicate sponsors_plan_sub, :sponsors_purpose?
    end
  end

  # https://github.com/github/sponsors/issues/3252
  test "allows invoiced org with sponsorship-specific and general Zuora account to create a sponsorship subscription" do
    stub_credit_balance do
      org = create(:invoiced_org, :sponsors_invoiced, admin: @user,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
      )
      assert_nil org.sponsors_plan_subscription

      result = assert_difference(["Billing::PlanSubscription.count", "Billing::SubscriptionItem.count"]) do
        Billing::CreateSponsorshipSubscriptionItem.call(tier: @sponsors_tier, sponsor: org, viewer: @user)
      end

      subscription_item = result[:subscription_item]
      refute_nil subscription_item
      assert_equal 1, subscription_item.quantity
      assert_equal @sponsors_tier, subscription_item.subscribable
      assert_equal org, subscription_item.account
      sponsors_plan_sub = org.reload_sponsors_plan_subscription
      refute_nil sponsors_plan_sub
      assert_equal sponsors_plan_sub, subscription_item.plan_subscription
      assert_predicate sponsors_plan_sub, :sponsors_purpose?
    end
  end

  # See https://github.com/github/sponsors/issues/5116
  test "allows sponsors-invoiced member orgs to create a sponsorship subscription" do
    stub_credit_balance do
      sponsors_invoiced_org = create(:enterprise_linked_organization, :sponsors_invoiced, admin: @user)

      result = assert_difference(["Billing::PlanSubscription.count", "Billing::SubscriptionItem.count"]) do
        Billing::CreateSponsorshipSubscriptionItem.call(tier: @sponsors_tier, sponsor: sponsors_invoiced_org, viewer: @user)
      end

      sponsors_plan_sub = sponsors_invoiced_org.sponsors_plan_subscription

      subscription_item = result[:subscription_item]
      refute_nil subscription_item
      assert_equal sponsors_plan_sub, subscription_item.plan_subscription
    end
  end

  test "uses existing Sponsors-purpose plan subscription for sponsorship" do
    FakeZuora.mock
    user = @general_purpose_plan_sub.user
    sponsors_plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: user, customer: user.customer)
    sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)

    result = assert_no_difference(-> { Billing::PlanSubscription.count }) do
      assert_difference(-> { Billing::SubscriptionItem.count }) do
        perform_enqueued_jobs(only: SynchronizePlanSubscriptionJob) do
          Billing::CreateSponsorshipSubscriptionItem.call(
            tier: sponsors_tier,
            sponsor: user,
            viewer: user,
          )
        end
      end
    end

    assert_performed_with(
      job: SynchronizePlanSubscriptionJob,
      args: [{ user_id: user.id, plan_name: user.plan.name, purpose: "sponsors" }, user: user]
    )
    sub_item = result[:subscription_item]
    refute_nil sub_item
    assert_equal sponsors_plan_sub, sub_item.plan_subscription
    assert_equal 1, sub_item.quantity
    assert_equal sponsors_tier, sub_item.subscribable
  end

  test "creates Sponsors-specific plan subscription when it doesn't exist" do
    FakeZuora.mock
    user = @general_purpose_plan_sub.user
    sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
    assert_nil user.sponsors_plan_subscription, "need a user with no Sponsors-specific plan subscription"

    result = assert_difference(["Billing::SubscriptionItem.count", "Billing::PlanSubscription.count"]) do
      perform_enqueued_jobs(only: SynchronizePlanSubscriptionJob) do
        Billing::CreateSponsorshipSubscriptionItem.call(
          tier: sponsors_tier,
          sponsor: user,
          viewer: user,
        )
      end
    end

    new_plan_sub = user.reload_sponsors_plan_subscription
    refute_nil new_plan_sub
    assert_equal user.customer, new_plan_sub.customer, "should have created the new Sponsors-specific plan sub " \
      "on the user's existing Customer, so it goes on their existing Zuora account"

    assert_performed_with(
      job: SynchronizePlanSubscriptionJob,
      args: [{ user_id: user.id, plan_name: user.plan.name, purpose: "sponsors" }, user: user]
    )
    sub_item = result[:subscription_item]
    refute_nil sub_item
    assert_equal new_plan_sub, sub_item.plan_subscription
    assert_equal 1, sub_item.quantity
    assert_equal sponsors_tier, sub_item.subscribable
    assert_equal user, sub_item.account
  end

  test "generates subscription item and creates sponsors-purpose plan sub for self-serve enterprise" do
    FakeZuora.mock
    admin = create(:user)
    enterprise = create(:business, :with_credit_card, owners: [admin])
    owned_org = create(:organization, admin: admin)
    enterprise.add_organization(owned_org)

    owned_org.grant_sponsorships_access(actor: admin)

    sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)

    owned_org.reload

    result = assert_difference(["Billing::SubscriptionItem.count", "Billing::PlanSubscription.count"]) do
      perform_enqueued_jobs(only: SynchronizePlanSubscriptionJob) do
        Billing::CreateSponsorshipSubscriptionItem.call(
          tier: sponsors_tier,
          sponsor: owned_org,
          viewer: admin
        )
      end
    end

    new_plan_sub = enterprise.reload_sponsors_plan_subscription
    refute_nil new_plan_sub
    assert_equal enterprise.customer, new_plan_sub.customer, "should have created the new Sponsors-specific plan sub " \
      "on the business' existing Customer, so it goes on their existing Zuora account"

    assert_performed_with(
      job: SynchronizePlanSubscriptionJob,
      args: [{ business_id: enterprise.id, plan_name: enterprise.plan.name, purpose: "sponsors" }, business: enterprise]
    )

    sub_item = result[:subscription_item]
    refute_nil sub_item
    assert_equal new_plan_sub, sub_item.plan_subscription
    assert_equal 1, sub_item.quantity
    assert_equal sponsors_tier, sub_item.subscribable
    assert_equal owned_org.id, sub_item.organization_id
  end

  test "creates subscription item when viewer is org admin and not enterprise admin for self-serve enterprise" do
    FakeZuora.mock
    enterprise = create(:business, :with_credit_card)
    owned_org = create(:organization, business: enterprise)

    enterprise_admin = enterprise.owners.first
    owned_org.grant_sponsorships_access(actor: enterprise_admin)

    sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)

    owned_org.reload

    org_admin = owned_org.admins.first
    refute_equal enterprise_admin, org_admin, "enterprise admin should not be org admin"

    result = assert_difference "Billing::SubscriptionItem.count" do
      perform_enqueued_jobs(only: SynchronizePlanSubscriptionJob) do
        Billing::CreateSponsorshipSubscriptionItem.call(
          tier: sponsors_tier,
          sponsor: owned_org,
          viewer: org_admin
        )
      end
    end

    assert_performed_with(
      job: SynchronizePlanSubscriptionJob,
      args: [{ business_id: enterprise.id, plan_name: enterprise.plan.name, purpose: "sponsors" }, business: enterprise]
    )

    sub_item = result[:subscription_item]
    refute_nil sub_item
    assert_equal 1, sub_item.quantity
    assert_equal sponsors_tier, sub_item.subscribable
    assert_equal owned_org.id, sub_item.organization_id
  end

  test "raises when viewer is not admin/owner of org or enterprise for self-serve enterprise" do
    FakeZuora.mock
    enterprise = create(:business, :with_credit_card)
    owned_org = create(:organization, business: enterprise)

    enterprise_admin = enterprise.owners.first
    owned_org.grant_sponsorships_access(actor: enterprise_admin)

    org_member = create(:user)
    owned_org.add_member(org_member)

    owned_org.reload

    sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)

    error = assert_no_difference(["Billing::PlanSubscription.count", "Billing::SubscriptionItem.count"]) do
      assert_raises Billing::CreateSubscriptionItem::ForbiddenError do
        Billing::CreateSponsorshipSubscriptionItem.call(tier: sponsors_tier, sponsor: owned_org, viewer: org_member)
      end
    end

    assert_equal "#{org_member} does not have permission to manage this account (#{enterprise})", error.message
  end

  test "uses existing sponsors-purpose plan sub for self-serve enterprise" do
    FakeZuora.mock
    sponsors_plan_sub = create(:billing_plan_subscription, :business_owned, purpose: :sponsors)
    enterprise = sponsors_plan_sub.customer.business
    admin = enterprise.owners.first
    owned_org = create(:organization, admin: admin)
    enterprise.add_organization(owned_org)

    owned_org.grant_sponsorships_access(actor: admin)
    owned_org.reload

    sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
    result = assert_no_difference(-> { Billing::PlanSubscription.count }) do
      assert_difference(-> { Billing::SubscriptionItem.count }) do
        perform_enqueued_jobs(only: SynchronizePlanSubscriptionJob) do
          Billing::CreateSponsorshipSubscriptionItem.call(
            tier: sponsors_tier,
            sponsor: owned_org,
            viewer: admin
          )
        end
      end
    end

    assert_performed_with(
      job: SynchronizePlanSubscriptionJob,
      args: [{ business_id: enterprise.id, plan_name: enterprise.plan.name, purpose: "sponsors" }, business: enterprise]
    )

    sub_item = result[:subscription_item]
    refute_nil sub_item
    assert_equal sponsors_plan_sub, sub_item.plan_subscription
    assert_equal 1, sub_item.quantity
    assert_equal sponsors_tier, sub_item.subscribable
  end

  test "creates subscription items for self-serve enterprise when different orgs sponsor the same tier" do
    FakeZuora.mock
    sponsors_plan_sub = create(:billing_plan_subscription, :business_owned, purpose: :sponsors)
    enterprise = sponsors_plan_sub.customer.business
    admin = enterprise.owners.first
    owned_org1, owned_org2 = create_pair(:organization, admin: admin)


    [owned_org1, owned_org2].each do |org|
      enterprise.add_organization(org)
      org.grant_sponsorships_access(actor: admin)
      org.reload
    end

    sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)

    result1 = Billing::CreateSponsorshipSubscriptionItem.call(tier: sponsors_tier, sponsor: owned_org1, viewer: admin)

    sub_item = result1[:subscription_item]
    refute_nil sub_item
    assert_equal owned_org1.id, sub_item.organization_id
    assert_equal sponsors_plan_sub, sub_item.plan_subscription
    assert_equal 1, sub_item.quantity
    assert_equal sponsors_tier, sub_item.subscribable

    result2 = Billing::CreateSponsorshipSubscriptionItem.call(tier: sponsors_tier, sponsor: owned_org2, viewer: admin)

    sub_item = result2[:subscription_item]
    refute_nil sub_item
    assert_equal owned_org2.id, sub_item.organization_id
    assert_equal sponsors_plan_sub, sub_item.plan_subscription
    assert_equal 1, sub_item.quantity
    assert_equal sponsors_tier, sub_item.subscribable
  end

  test "creates Sponsors-specific plan subscription when using a Sponsors-specific customer" do
    stub_credit_balance do
      FakeZuora.mock
      invoiced_org = create(:invoiced_org, :sponsors_invoiced)

      result = T.let(nil, T.nilable(Hash))
      assert_difference(["Billing::SubscriptionItem.count", "Billing::PlanSubscription.sponsors_purpose.count"]) do
        perform_enqueued_jobs(only: SynchronizePlanSubscriptionJob) do
          result = Billing::CreateSponsorshipSubscriptionItem.call(
            tier: @sponsors_tier,
            sponsor: invoiced_org,
            viewer: invoiced_org.admin,
          )
        end
      end

      assert_performed_with(
        job: SynchronizePlanSubscriptionJob,
        args: [{
          user_id: invoiced_org.id,
          plan_name: invoiced_org.plan.name,
          purpose: "sponsors",
        }, user: invoiced_org]
      )
      refute_nil result
      sub_item = T.must(result)[:subscription_item]
      refute_nil sub_item
      assert_predicate sub_item.plan_subscription, :sponsors_purpose?
      assert_equal 1, sub_item.quantity
      assert_equal @sponsors_tier, sub_item.subscribable
    end
  end

  test "instruments sponsorship added event" do
    FakeZuora.mock
    user = @general_purpose_plan_sub.user
    events = subscribe("sponsorship.added")

    result = Billing::CreateSponsorshipSubscriptionItem.call(
      tier: @sponsors_tier,
      sponsor: user,
      viewer: user,
      via_bulk_sponsorship: true,
    )

    refute_nil result[:subscription_item]
    expected_payload = {
      subscription_item_id: result[:subscription_item].id,
      sender_id: user.id,
      via_bulk_sponsorship: true,
    }
    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "supports delayed activation via future active_on date" do
    bill_on = GitHub::Billing.today + 7.days

    result = Billing::CreateSponsorshipSubscriptionItem.call(
      tier: @sponsors_tier,
      sponsor: @user,
      viewer: @user,
      active_on: bill_on,
    )

    sub_item = result[:subscription_item]

    refute_predicate sub_item, :active?
    assert_equal @sponsors_tier, sub_item.subscribable

    pending_change = sub_item.pending_subscription_item_change

    refute_nil pending_change
    assert_equal 1, pending_change.quantity
    assert_equal @sponsors_tier, pending_change.subscribable
    assert_equal bill_on, pending_change.active_on
  end

  test "activates immediately when active_on date is today" do
    bill_on = GitHub::Billing.today

    result = Billing::CreateSponsorshipSubscriptionItem.call(
      tier: @sponsors_tier,
      sponsor: @user,
      viewer: @user,
      active_on: bill_on,
    )

    sub_item = result[:subscription_item]

    assert_predicate sub_item, :active?
    assert_equal @sponsors_tier, sub_item.subscribable
  end

  test "activates immediately when active_on date is in the past" do
    bill_on = GitHub::Billing.today - 7.days

    result = Billing::CreateSponsorshipSubscriptionItem.call(
      tier: @sponsors_tier,
      sponsor: @user,
      viewer: @user,
      active_on: bill_on,
    )

    sub_item = result[:subscription_item]

    assert_predicate sub_item, :active?
    assert_equal @sponsors_tier, sub_item.subscribable
  end
end
