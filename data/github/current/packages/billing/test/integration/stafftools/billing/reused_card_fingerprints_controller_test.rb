# typed: true
# frozen_string_literal: true

# rubocop:disable Naming/InclusiveLanguage

require "test_helper"

class Stafftools::Billing::ReusedCardFingerprintsControllerTest < GitHub::IntegrationTestCase
  fixtures do
    @staff = create(:staff_admin_user)
    @user = create(:user)
  end

  context "GET :index" do
    test "renders all reused card fingerprints created in last 30 days over the threshold with a link to the fingerprint" do
      as @staff
      get "stafftools/reused_card_fingerprints"

      assert_response :success
      assert_template :index
    end
  end

  context "GET :lookup" do
    test "renders all payment methods with the given fingerprint" do
      as @staff
      payment_method = create(:payment_method)
      get "stafftools/reused_card_fingerprints/lookup?card_fingerprint=#{payment_method.card_fingerprint}"

      assert_response :success
      assert_template :lookup
    end

    test "renders a 404 if no payment methods exist for the given fingerprint" do
      as @staff
      get "stafftools/reused_card_fingerprints/lookup?card_fingerprint=123456789"

      assert_response :not_found
    end
  end

  context "UPDATE" do
    test "adds card fingerprint to the deny list" do
      as @staff
      user = create(:user)
      payment_method = create :payment_method, user: user, unique_number_identifier: "123456789"

      refute BlacklistedPaymentMethod.exists?(unique_number_identifier: "123456789")
      put "stafftools/reused_card_fingerprints/123456789", params: { payment_method_action: "block", reason: "Fraudulent", blocklist_consequence: BlacklistedPaymentMethod::Consequence::Suspended.serialize  }
      assert BlacklistedPaymentMethod.exists?(unique_number_identifier: "123456789")
      assert T.must(BlacklistedPaymentMethod.find_by_payment_method(payment_method)).reason == "Fraudulent"
    end

    test "suspends users attached to the card fingerprint" do
      as @staff
      user = create(:user)
      fingerprint = "123456789"
      create :payment_method, user: user, unique_number_identifier: fingerprint

      refute user.suspended?
      put "stafftools/reused_card_fingerprints/#{fingerprint}", params: { payment_method_action: "block", reason: "Fraudulent", blocklist_consequence: BlacklistedPaymentMethod::Consequence::Suspended.serialize }
      assert user.reload.suspended?
      assert_includes flash[:success], "Succcessfully blocked payment fingerprint #{fingerprint} and suspended all accounts associated to that fingerprint"
    end

    test "locks the billing of users attached to the card fingerprint" do
      as @staff
      user = create(:user)
      fingerprint = "123456789"
      create :payment_method, user: user, unique_number_identifier: fingerprint

      refute user.suspended?
      put "stafftools/reused_card_fingerprints/#{fingerprint}", params: { payment_method_action: "block", reason: "Fraudulent", blocklist_consequence: BlacklistedPaymentMethod::Consequence::BillingLocked.serialize }
      assert user.reload.disabled?
      assert_includes flash[:success], "Succcessfully blocked payment fingerprint #{fingerprint} and locked billing for all accounts associated to that fingerprint"
    end

    test "displays error flash if no reason is provided" do
      as @staff
      user = create(:user)
      payment_method = create :payment_method, user: user, unique_number_identifier: "123456789"
      put "stafftools/reused_card_fingerprints/123456789", params: { payment_method_action: "block" }

      assert_includes flash[:error],  "A reason is mandatory to block this card fingerprint. Please provide a reason and try again."
    end

    test "removes card fingerprint from the deny list" do
      as @staff
      user = create(:user)
      payment_method = create :payment_method, user: user, unique_number_identifier: "123456789"

      refute BlacklistedPaymentMethod.exists?(unique_number_identifier: "123456789")
      put "stafftools/reused_card_fingerprints/123456789", params: { payment_method_action: "block", reason: "Fraudulent", blocklist_consequence: BlacklistedPaymentMethod::Consequence::Suspended.serialize  }
      assert BlacklistedPaymentMethod.exists?(unique_number_identifier: "123456789")

      put "stafftools/reused_card_fingerprints/123456789", params: { payment_method_action: "unblock", reason: "No longer fraudulent" }
      refute BlacklistedPaymentMethod.exists?(unique_number_identifier: "123456789")
    end

    test "removes card fingerprint from the deny list and undos the consequences performed on the accounts" do
      as @staff
      user = create(:user)
      payment_method = create :payment_method, user: user, unique_number_identifier: "123456789"

      refute BlacklistedPaymentMethod.exists?(unique_number_identifier: "123456789")
      put "stafftools/reused_card_fingerprints/123456789", params: { payment_method_action: "block", reason: "Fraudulent", blocklist_consequence: BlacklistedPaymentMethod::Consequence::Suspended.serialize }
      assert BlacklistedPaymentMethod.exists?(unique_number_identifier: "123456789")
      assert user.reload.suspended?

      put "stafftools/reused_card_fingerprints/123456789", params: { payment_method_action: "unblock", reason: "No longer fraudulent", undo_account_consequence: ["true"] }
      refute BlacklistedPaymentMethod.exists?(unique_number_identifier: "123456789")
      refute user.reload.suspended?
    end
  end
end if GitHub.billing_enabled?

# rubocop:enable Naming/InclusiveLanguage
