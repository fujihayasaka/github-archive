# typed: true
# frozen_string_literal: true

require "test_helper"

class TotpAppRegistrationTest < GitHub::TestCase
  extend EncryptedColumnTestHelper
  test_encrypted_column(:totp_app_registration, :encrypted_otp_secret)

  test "only one app registration per user" do
    user = create(:user)
    create(:totp_app_registration, user: user).save!

    assert_raises do
      create(:totp_app_registration, user: user).save!
    end
  end

  test "create eomts audit log event" do
    add_factor_events = subscribe "two_factor_authentication.add_factor"
    user = create(:user)

    create(:totp_app_registration, user: user).save!

    assert add_event = add_factor_events.pop, "an event was expected"
  end

  test "destroy emits audit log event" do
    remove_factor_events = subscribe "two_factor_authentication.remove_factor"
    user = create(:user)
    create(:totp_app_registration, user: user).save!

    user.totp_app_registration&.destroy

    assert remove_event = remove_factor_events.pop, "an event was expected"
  end
end
