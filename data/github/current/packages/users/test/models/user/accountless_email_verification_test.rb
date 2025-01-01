# typed: true
# frozen_string_literal: true

require "test_helper"

class User::AccountlessEmailVerificationTest < GitHub::TestCase
  include ActionMailer::TestHelper

  setup do
    @octocaptcha = Octocaptcha.new(Rack::Test::Session.new(Rack::MockSession.new(GitHub::Application)))
    @user = build(:user)
  end

  context ".create_and_send_verification_email" do
    test "creates the account verification and sends the verification email" do
      spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
      assert_enqueued_emails 1 do
        id = User::AccountlessEmailVerification.create_and_send_verification_email(
          user: @user,
          octocaptcha: @octocaptcha,
          visitor_id: 1,
          spamurai_form_signals: spamurai_form_signals,
          funcaptcha_data_exchange: { "just" => "testing" },
          country_code: "JP",
          explicit_marketing_consent: true
        )
        verification = User::AccountlessEmailVerification.find_email_verification(id)

        assert_equal @user.display_login, verification&.display_login
        assert_equal @user.email, verification&.email
        assert_equal 1, verification&.visitor_id
        assert_equal spamurai_form_signals.as_json, verification&.spamurai_form_signals&.as_json
        assert_equal({ "just" => "testing" }, verification&.funcaptcha_data_exchange)
        assert_equal "JP", verification&.country_code
        assert_equal true, verification&.explicit_marketing_consent
      end
    end
  end

  context ".find_email_verification" do
    test "expires the record after 2 hours" do
      spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
      id = User::AccountlessEmailVerification.create_and_send_verification_email(
        user: @user, octocaptcha: @octocaptcha
      )

      travel_to(2.hours.from_now) do
        verification = User::AccountlessEmailVerification.find_email_verification(id)

        assert_nil verification
      end
    end
  end
end
