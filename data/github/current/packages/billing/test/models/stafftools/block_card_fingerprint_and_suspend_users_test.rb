# typed: true
# frozen_string_literal: true

# rubocop:disable Naming/InclusiveLanguage

require "test_helper"

class StafftoolsBlockCardFingerprintAndSuspendUsersTest < GitHub::TestCase
  setup do
    @user_1 = create :user
    create :payment_method, unique_number_identifier: "1234", paypal_email: nil, user: @user_1

    @paypal_email = "user@example.com"
    @user_2 = create :user
    create :payment_method, paypal_email: @paypal_email, unique_number_identifier: nil, user: @user_2

    @actor = create :user
  end

  context "#call" do
    context "with a unique_number_identifier" do
      test "blocks the card fingerprint" do
        refute BlacklistedPaymentMethod.exists?(unique_number_identifier: "1234")
        Billing::Stafftools::BlockCardFingerprintAndSuspendUsers.new(card_fingerprint: "1234", actor: @actor).call
        assert BlacklistedPaymentMethod.exists?(unique_number_identifier: "1234")
      end

      test "blocks the card fingerprint and persists the reason" do
        refute BlacklistedPaymentMethod.exists?(unique_number_identifier: "1234")
        Billing::Stafftools::BlockCardFingerprintAndSuspendUsers.new(card_fingerprint: "1234", actor: @actor, reason: "Fraudulent credit card").call
        assert BlacklistedPaymentMethod.exists?(unique_number_identifier: "1234")
        assert T.must(BlacklistedPaymentMethod.find_by_card_fingerprint("1234")).reason == "Fraudulent credit card"
      end

      test "suspends the users" do
        refute @user_1.suspended?
        Billing::Stafftools::BlockCardFingerprintAndSuspendUsers.new(card_fingerprint: "1234", actor: @actor).call
        assert @user_1.reload.suspended?
      end
    end

    context "with a paypal_email" do
      test "blocks the card fingerprint" do
        refute BlacklistedPaymentMethod.exists?(paypal_email: @paypal_email)
        Billing::Stafftools::BlockCardFingerprintAndSuspendUsers.new(card_fingerprint: @paypal_email, actor: @actor).call
        assert BlacklistedPaymentMethod.exists?(paypal_email: @paypal_email)
      end

      test "suspends the users" do
        refute @user_2.suspended?
        Billing::Stafftools::BlockCardFingerprintAndSuspendUsers.new(card_fingerprint: @paypal_email, actor: @actor).call
        assert @user_2.reload.suspended?
      end
    end
  end
end if GitHub.billing_enabled?

# rubocop:enable Naming/InclusiveLanguage
