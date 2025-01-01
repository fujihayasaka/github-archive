# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::Notifications
  class NotificationPermissionTest < GitHub::BillingTestCase

    fixtures do
      @org = create(:credit_card_organization)
    end

    setup do
      @notification_permission = Billing::Notifications::NotificationPermission.new(@org)
    end

    context "#receive_notification_for_free_usage?" do
      test "returns true if overages are not enabled" do
        assert @notification_permission.receive_notification_for_free_usage?
      end

      test "returns true if overages are enabled" do
        create(:billing_budget, :enforce, owner: @org, spending_limit_in_subunits: 10000)
        assert @notification_permission.receive_notification_for_free_usage?
      end

      test "returns false if overages are enabled and free usage notification disabled in current cycle" do
        create(:billing_budget, :enforce, owner: @org, spending_limit_in_subunits: 10000)
        @notification_permission.disable_free_usage_notification_in_current_cycle
        refute @notification_permission.receive_notification_for_free_usage?
      end
    end

    context "#receive_notification_for_paid_usage?" do
      test "returns true if overages are enabled" do
        create(:billing_budget, :enforce, owner: @org, spending_limit_in_subunits: 10000)
        assert @notification_permission.receive_notification_for_paid_usage?
      end

      test "returns false if overages are not enabled" do
        refute @notification_permission.receive_notification_for_paid_usage?
      end
    end

    context "#free_usage_notification_disabled_in_current_cycle?" do
      test "returns true if free notification is disabled in current billing cycle" do
        @notification_permission.disable_free_usage_notification_in_current_cycle
        assert @notification_permission.free_usage_notification_disabled_in_current_cycle?
      end

      test "returns false if free notification is not disabled in current cycle" do
        refute @notification_permission.free_usage_notification_disabled_in_current_cycle?
      end
    end
  end
end
