# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  module Public
    class BlocklistPaymentMethodTest < GitHub::BillingTestCase
      fixtures do
        @actor = create(:user)
      end

      context "blocklist_payment_method" do
        test "blocklists a payment method and executes the consequence" do
          user = create(:user_with_payment_identifier, unique_number: "12345")
          Billing::Public.blocklist_payment_method(account: user, payment_method: user.payment_method, reason: "Test reason", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked, actor: @actor) # rubocop:disable Naming/InclusiveLanguage

          assert user.reload.payment_method.blocklisted?
          assert user.disabled?
        end

        test "does not overwrite the consequence and reason of a previously blocklisted payment method if force is false" do
          user1 = create(:user_with_payment_identifier, unique_number: "12345")
          blocklisted_payment_method1 = Billing::Public.blocklist_payment_method(account: user1, payment_method: user1.payment_method, reason: "Test reason", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked, actor: @actor) # rubocop:disable Naming/InclusiveLanguage

          user2 = create(:user_with_payment_identifier, unique_number: "12345")
          blocklisted_payment_method2 = Billing::Public.blocklist_payment_method(account: user2, payment_method: user2.payment_method, reason: "Different reason", consequence: BlacklistedPaymentMethod::Consequence::Suspended, force: false, actor: @actor) # rubocop:disable Naming/InclusiveLanguage

          assert user1.reload.disabled?
          assert user2.reload.disabled?
          refute user2.suspended?
          assert_equal blocklisted_payment_method1.reason, blocklisted_payment_method2.reason
          assert_equal blocklisted_payment_method1.consequence, blocklisted_payment_method2.consequence
        end

        test "does nothing if the payment method has already been blocklisted" do
          user1 = create(:user_with_payment_identifier, unique_number: "12345")
          user2 = create(:user_with_payment_identifier, unique_number: "12345")
          blocklisted_payment_method1 = Billing::Public.blocklist_payment_method(account: user1, payment_method: user1.payment_method, reason: "Test reason", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked, actor: @actor) # rubocop:disable Naming/InclusiveLanguage
          blocklisted_payment_method2 = Billing::Public.blocklist_payment_method(account: user2, payment_method: user2.payment_method, reason: "Different reason", consequence: BlacklistedPaymentMethod::Consequence::Suspended, force: false, actor: @actor) # rubocop:disable Naming/InclusiveLanguage

          assert user1.reload.disabled?
          assert user2.reload.disabled?
          assert_equal blocklisted_payment_method1.reason, blocklisted_payment_method2.reason
          assert_equal blocklisted_payment_method1.consequence, blocklisted_payment_method2.consequence
        end

        test "overwrites the consequence and reason of a previously blocklisted payment method if force is true" do
          user1 = create(:user_with_payment_identifier, unique_number: "12345")
          blocklisted_payment_method1 = Billing::Public.blocklist_payment_method(account: user1, payment_method: user1.payment_method, reason: "Test reason", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked, actor: @actor) # rubocop:disable Naming/InclusiveLanguage

          user2 = create(:user_with_payment_identifier, unique_number: "12345")
          blocklisted_payment_method2 = Billing::Public.blocklist_payment_method(account: user2, payment_method: user2.payment_method, reason: "Different reason", consequence: BlacklistedPaymentMethod::Consequence::Suspended, force: true, actor: @actor) # rubocop:disable Naming/InclusiveLanguage

          assert user1.reload.disabled?
          assert user1.suspended?
          assert user2.reload.suspended?
          refute_equal blocklisted_payment_method1.reason, blocklisted_payment_method2.reason
          refute_equal blocklisted_payment_method1.consequence, blocklisted_payment_method2.consequence
        end

        test "executes the consequence on all users associated to a blocklisted payment method" do
          user1 = create(:user_with_payment_identifier, unique_number: "12345")
          user2 = create(:user_with_payment_identifier, unique_number: "12345")

          blocklisted_payment_method2 = Billing::Public.blocklist_payment_method(account: user2, payment_method: user2.payment_method, reason: "reason", consequence: BlacklistedPaymentMethod::Consequence::Suspended, force: true, actor: @actor) # rubocop:disable Naming/InclusiveLanguage

          assert user1.reload.suspended?
          assert user2.reload.suspended?
        end
      end
    end
  end
end
