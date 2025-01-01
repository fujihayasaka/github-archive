# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  module Public
    class InAppPurchaseTest < GitHub::BillingTestCase
      context "equality" do
        test "true if type and identifier are same" do
          assert_equal InAppPurchase.apple(original_transaction_id: "123"), InAppPurchase.apple(original_transaction_id: "123")

          assert_equal InAppPurchase.google(purchase_token: "123"), InAppPurchase.google(purchase_token: "123")
        end

        test "identifier is case insensitive" do
          assert_equal InAppPurchase.apple(original_transaction_id: "abc"), InAppPurchase.apple(original_transaction_id: "ABc")

          assert_equal InAppPurchase.google(purchase_token: "ABC"), InAppPurchase.google(purchase_token: "aBc")
        end

        test "false if type is different" do
          refute_equal InAppPurchase.apple(original_transaction_id: "123"), InAppPurchase.google(purchase_token: "123")
        end

        test "false if identifier is different" do
          refute_equal InAppPurchase.apple(original_transaction_id: "abc"), InAppPurchase.apple(original_transaction_id: "zyx")

          refute_equal InAppPurchase.google(purchase_token: "abc"), InAppPurchase.google(purchase_token: "zyx")
        end
      end
    end
  end
end
