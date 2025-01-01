# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::MeteredThresholdNotifierTest < GitHub::TestCase
  setup do
    @product = ::Billing::Notifications::ACTIONS_PRODUCT
    @content = mock
    @notification = mock
    @notifier_mock = mock
  end

  def assert_usage_notifier(owner)
    Billing::Notifications::UsageNotification.expects(:new).with(owner, product: @product).returns(@notification)
    @notification.stubs(:highest_priority_notification).returns(@content)
    Billing::Notifications::UsageNotifier.expects(:new).with(owner, product: @product, usage_notification: @notification).returns(@notifier_mock)
  end

  def refute_usage_notifier(owner)
    Billing::Notifications::UsageNotification.expects(:new).with(owner, product: @product).returns(@notification).never
    @notification.stubs(:highest_priority_notification).returns(@content)
    Billing::Notifications::UsageNotifier.expects(:new).with(owner, product: @product, usage_notification: @notification).returns(@notifier_mock).never
  end

  context "#notify_if_applicable" do
    test "multiple notifications aren't sent within a cached interval for an org" do
      freeze_time do
        organization = create(:organization, plan: "free")
        cache_key = "billing:metered_threshold_notifier:#{organization}:#{organization.id}:#{@product}"

        # First call should send a notification
        assert_usage_notifier(organization)

        @notifier_mock.expects(:notify_if_applicable).once
        Billing::MeteredThresholdNotifier.new(owner_id: organization.id, product: @product).notify_if_applicable

        assert GitHub.job_coordination_redis.exists(cache_key)

        # Second call should not send a notification
        refute_usage_notifier(organization)

        @notifier_mock.expects(:notify_if_applicable).never
        Billing::MeteredThresholdNotifier.new(owner_id: organization.id, product: @product).notify_if_applicable

        GitHub.job_coordination_redis.expire(cache_key, 0)

        # Third call should send a notification again (cache expired)
        assert_usage_notifier(organization)

        @notifier_mock.expects(:notify_if_applicable).once
        Billing::MeteredThresholdNotifier.new(owner_id: organization.id, product: @product).notify_if_applicable
      end
    end

    test "uses the correct notifier for free usage on enterprise accounts paying through Azure enterprise agreement" do
      business = create(:business, :with_azure_subscription)
      business_owned_organization = create(:organization, business: business)

      # free usage
      @content.stubs(:within_entitlements?).returns(true)

      if GitHub.flipper[:ghe_spending_limits].enabled?
        assert_usage_notifier(business_owned_organization)
        assert_usage_notifier(business)
        @notifier_mock.expects(:notify_if_applicable).twice
      else
        assert_usage_notifier(business)
        @notifier_mock.expects(:notify_if_applicable).once
      end

      Billing::MeteredThresholdNotifier.new(owner_id: business_owned_organization.id, product: @product).notify_if_applicable
    end

    test "uses the correct notifier for paid usage on enterprise accounts paying through Azure enterprise agreement" do
      business = create(:business, :with_azure_subscription)
      business_owned_organization = create(:organization, business: business)

      # paid usage
      @content.stubs(:within_entitlements?).returns(false)

      if GitHub.flipper[:ghe_spending_limits].enabled?
        assert_usage_notifier(business_owned_organization)
        assert_usage_notifier(business)
        @notifier_mock.expects(:notify_if_applicable).twice
      else
        assert_usage_notifier(business)
        @notifier_mock.expects(:notify_if_applicable).once
      end

      Billing::MeteredThresholdNotifier.new(owner_id: business_owned_organization.id, product: @product).notify_if_applicable
    end

    test "uses the correct notifier for invoiced organizations" do
      organization = create(:invoiced_organization, plan: "business")

      assert_usage_notifier(organization)

      @notifier_mock.expects(:notify_if_applicable).once
      Billing::MeteredThresholdNotifier.new(owner_id: organization.id, product: @product).notify_if_applicable
    end

    test "uses the correct notifier for enterprise accounts paying through GitHub" do
      business = create(:business)
      business_owned_organization = create(:organization, business: business)

      if GitHub.flipper[:ghe_spending_limits].enabled?
        assert_usage_notifier(business_owned_organization)
        assert_usage_notifier(business)
        @notifier_mock.expects(:notify_if_applicable).twice
      else
        assert_usage_notifier(business)
        @notifier_mock.expects(:notify_if_applicable).once
      end

      Billing::MeteredThresholdNotifier.new(owner_id: business_owned_organization.id, product: @product).notify_if_applicable
    end

    test "uses the correct notifier for self-serve organizations" do
      organization = create(:organization, plan: "free")

      assert_usage_notifier(organization)

      @notifier_mock.expects(:notify_if_applicable).once
      Billing::MeteredThresholdNotifier.new(owner_id: organization.id, product: @product).notify_if_applicable
    end

    test "uses the correct notifier for users" do
      user = create(:user, plan: "free")

      assert_usage_notifier(user)

      @notifier_mock.expects(:notify_if_applicable).once
      Billing::MeteredThresholdNotifier.new(owner_id: user.id, product: @product).notify_if_applicable
    end

    test "skips notifier for accounts on legacy plan" do
      user = create(:user, plan: "bronze")

      refute_usage_notifier(user)

      @notifier_mock.expects(:notify_if_applicable).never
      Billing::MeteredThresholdNotifier.new(owner_id: user.id, product: @product).notify_if_applicable
    end
  end
end if GitHub.billing_enabled?
