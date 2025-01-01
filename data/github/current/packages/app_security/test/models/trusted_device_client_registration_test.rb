# typed: true
# frozen_string_literal: true

require "test_helper"

class TrustedDeviceClientRegistrationTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @security_key = create(:security_key, user: @user)
    @trusted_device = create(:trusted_device, user: @user)
    @authenticated_device = create(:authenticated_device, user: @user)
  end

  test "security keys cannot be associated with authenticated devices" do
    error = assert_raises ActiveRecord::RecordInvalid do
      @security_key.trusted_device_client_registrations.create!(authenticated_device: @authenticated_device, user: @user)
    end
    assert_equal "Validation failed: security key provided instead of passkey", error.message
  end

  test "authenticated devices cannot be associated with security keys" do
    error = assert_raises ActiveRecord::RecordInvalid do
      @authenticated_device.trusted_device_client_registrations.create!(trusted_device: @security_key, user: @user)
    end
    assert_equal "Validation failed: security key provided instead of passkey", error.message
  end

  test "requires that association record belongs to the same user" do
    error = assert_raises ActiveRecord::RecordInvalid do
      @trusted_device.trusted_device_client_registrations.create!(authenticated_device: @authenticated_device, user: create(:user))
    end
    assert_equal "Validation failed: devices not owned by same user", error.message

    authenticated_device = create(:authenticated_device, user: create(:user))
    error = assert_raises ActiveRecord::RecordInvalid do
      @trusted_device.trusted_device_client_registrations.create!(authenticated_device: authenticated_device, user: @user)
    end
    assert_equal "Validation failed: devices not owned by same user", error.message
  end

  test "client registrations require authenticated devices" do
    error = assert_raises ActiveRecord::RecordInvalid do
      @trusted_device.trusted_device_client_registrations.create!(authenticated_device: nil, user: @user)
    end
    assert_equal "Validation failed: Authenticated device can't be blank", error.message
  end

  test "client registrations require trusted_devices" do
    error = assert_raises ActiveRecord::RecordInvalid do |_asdf|
      @authenticated_device.trusted_device_client_registrations.create!(trusted_device: nil, user: @user)
    end
    assert_equal "Validation failed: passkey not supplied", error.message
  end

  test "passkey client registrations are readonly" do
    client_registration = @authenticated_device.trusted_device_client_registrations.create!(trusted_device: @trusted_device, user: @user)
    assert_predicate client_registration, :readonly?
    assert_predicate TrustedDeviceClientRegistration.find_by(id: client_registration.id), :readonly?
  end
end
