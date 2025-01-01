# typed: true
# frozen_string_literal: true

require "test_helper"

class U2fRegistrationTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @user = create(:user)
    @registration = create :security_key, user: @user
  end

  test "is valid with normal attributes" do
    assert_predicate @registration, :valid?
  end

  test "validates that the nickname is unique to the user" do
    @second_registration = build(:security_key, user: @user, nickname: @registration.nickname)
    refute_predicate @second_registration, :valid?
  end

  test "rejects the nickname if it contains emoji" do
    @registration = build(:security_key, user: @user, nickname: "🐹")
    refute_predicate @registration, :valid?
    assert @registration.errors[:nickname].any?
  end

  test "bad bytes are treated as invalid public key" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    @registration.public_key = "f+CaaK851Y+ffkqGqgwNWGx7Qq4eSgJb+Q=="
    refute_predicate @registration, :valid?
    assert_equal 1, GitHub.dogstats.increments("authentication.webauthn", tags: ["reason:cose/malformed_key_error", "action:validate_public_key"]).length
  end

  test "validates certificate is valid base64" do
    @registration.certificate = "*"
    refute_predicate @registration, :valid?
  end

  test "validates certificate is valid x509" do
    @registration.certificate = Base64.strict_encode64("foo")
    refute_predicate @registration, :valid?
  end

  test "creation is instrumented" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    @user.security_checkup_completed("updated")
    events = subscribe "security_key.register"
    create :security_key, user: @user
    assert event = events.pop, "an instrumentation even was expected"
    assert_equal @user.login, event.payload[:user]
    assert_equal 1, GitHub.dogstats.increments("u2f_registration", tags: ["action:register", "recent_security_checkup:true"]).count
  end

  test "deletion is instrumented" do
    events = subscribe "security_key.remove"
    @registration.destroy
    assert event = events.pop, "an instrumentation even was expected"
    assert_equal @user.login, event.payload[:user]
  end

  test "passkeys can be associated with a multiple authenticated devices" do
    first_device, second_device, third_device = create_list(:authenticated_device, 3, user: @user)
    trusted_device = create(:trusted_device, user: @user)

    trusted_device.trusted_device_client_registrations.create!(authenticated_device: first_device, user: @user)
    trusted_device.trusted_device_client_registrations.create!(authenticated_device: second_device, user: @user)
    trusted_device.trusted_device_client_registrations.create!(authenticated_device: third_device, user: @user)

    assert trusted_device.authenticated_devices_registered.include?(first_device)
    assert trusted_device.authenticated_devices_registered.include?(second_device)
    assert trusted_device.authenticated_devices_registered.include?(third_device)
    assert trusted_device.authenticated_devices_registered.count == 3
  end

  test "deletion removes passkey join table entries" do
    authenticated_device = create(:authenticated_device, user: @user)
    trusted_device = create(:trusted_device, user: @user)
    authenticated_device.trusted_device_client_registrations.create!(trusted_device: trusted_device, user: @user)

    assert_equal [authenticated_device], trusted_device.authenticated_devices_registered

    assert_difference "TrustedDeviceClientRegistration.count", -1 do
      trusted_device.destroy!
    end

    assert_empty authenticated_device.trusted_devices
  end

  test "registering a passkey creates an audit log entry" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    passkey = T.let(nil, T.nilable(U2fRegistration))
    # The events variable is an array of event hashes.
    events = assert_performed_audit_entries(count: 1, only: "passkey.register") do
      passkey = create(:trusted_device, user: @user, nickname: "test_name")
    end

    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      is_passkey_registration: true,
      is_uvpa: true,
      credential_id: passkey&.id,
      nickname: "test_name",
      is_backup_eligible: false,
    }

    # Here we are verifying that the expected_payload hash is a subset of the event hash.
    assert_subset_hash expected_payload, events.first
    assert_equal 1, GitHub.dogstats.increments("u2f_registration", tags: ["action:register"]).count
  end

  test "passkey deletion is instrumented" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    passkey = create :trusted_device, user: @user, nickname: "test_name"

    events = subscribe "passkey.remove"
    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      is_passkey_registration: true,
      is_backup_eligible: false,
      is_uvpa: true,
      credential_id: passkey.id,
      nickname: "test_name",
    }

    passkey.destroy
    # verify that the expected_payload hash is a subset of the event hash.
    assert_subset_hash expected_payload, events.first.payload
    assert_equal 1, GitHub.dogstats.increments("u2f_registration", tags: ["action:remove"]).count
  end

  test "registering a security key creates an audit log entry" do

    security_key = T.let(nil, T.nilable(U2fRegistration))
    events = assert_performed_audit_entries(count: 1, only: "security_key.register") do
      security_key = create(:security_key, user: @user)
    end

    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      is_passkey_registration: false,
      is_backup_eligible: false,
      is_uvpa: false,
      credential_id: security_key&.id
    }

    assert_subset_hash expected_payload, events.first
  end

  test "user can only register 100 security keys" do
    create(:security_key, user: @user) until @user.u2f_registrations.count == 100
    registration = build :security_key, user: @user
    refute registration.valid?
    assert_equal "users can only register 100 security keys", registration.errors[:base].first
  end

  test "user can view passkeys registered" do
    registration_trusted = create(:trusted_device, user: @user, nickname: "trusted")
    registration_untrusted = create(:security_key, user: @user, nickname: "untrusted")
    assert_predicate registration_trusted, :valid?
    assert_predicate registration_untrusted, :valid?
    trusted_devices = @user.u2f_registrations.passkeys
    assert_includes trusted_devices, registration_trusted
    refute_includes trusted_devices, registration_untrusted
  end

  test "last_used_at used when set when FF enabled" do
    now = Time.now
    registration_a = create(:trusted_device, user: @user, updated_at: now, last_used_at: nil)
    registration_b = create(:security_key, user: @user, last_used_at: now)

    assert_nil registration_a.last_used_at
    assert_equal registration_a.get_last_used_at, registration_a.updated_at

    registration_b.update!(updated_at: Time.now + 1.minute)
    refute_equal registration_b.last_used_at, registration_b.updated_at
    assert_equal registration_b.get_last_used_at, registration_b.last_used_at
  end

  test "passkeys can't have the same nickname" do
    assert_difference "@user.u2f_registrations.passkeys.count" do
      create(:trusted_device, user: @user, nickname: "my device")
    end
    error = assert_raises(ActiveRecord::RecordInvalid) do
      create(:trusted_device, user: @user, nickname: "my device")
    end
    assert_equal "Validation failed: Nickname has already been taken", error.message
  end

  test "security keys cannot have the same nickname" do
    assert_difference "@user.u2f_registrations.security_keys.count" do
      create(:u2f_registration, user: @user, nickname: "my device")
    end
    error = assert_raises(ActiveRecord::RecordInvalid) do
      create(:u2f_registration, user: @user, nickname: "my device")
    end
    assert_equal "Validation failed: Nickname has already been taken", error.message
  end

  test "security keys can't have the same nickname already taken by trusted_device" do
    create(:trusted_device, user: @user, nickname: "my device")
    assert_equal 1, @user.u2f_registrations.passkeys.length
    error = assert_raises(ActiveRecord::RecordInvalid) do
      create(:u2f_registration, user: @user, nickname: "my device")
    end
    assert_equal "Validation failed: Nickname has already been taken", error.message
  end

  test "passkeys nickname cannot be null" do
    error = assert_raises(ActiveRecord::RecordInvalid) do
      create(:u2f_registration, user: @user, nickname: nil)
    end
    assert_equal "Validation failed: Nickname can't be blank", error.message
  end

  def assert_valid_registration(webauthn_register_challenge, response)
    register_response_hash = JSON.parse(response)

    attestation_object = Base64.urlsafe_decode64(register_response_hash["response"]["attestationObject"])

    registration = WebAuthn::AuthenticatorAttestationResponse.new(
      client_data_json: Base64.urlsafe_decode64(register_response_hash["response"]["clientDataJSON"]),
      attestation_object: attestation_object,
    )

    decoded_challenge = Base64.urlsafe_decode64(webauthn_register_challenge)
    assert registration.valid?(decoded_challenge, "https://oreoshake.review-lab.github.com", rp_id: "github.com")
  end

  context "webauthn validation" do
    test "works with windows hello on firefox" do
      webauthn_register_challenge = "y94BMXPkz2HPW9Whch_4djFLGXfonSm9Ov0FhM-XMsY"
      response = %(
        {"type":"public-key","id":"BQa9gIySCPp4uyur1lX61SXqTNE1Vn5Yhvqwq5RByYvCJniTXEYCs9h8X7XRt88hkidg5Qu2XNTo25TtWBPunw","rawId":"BQa9gIySCPp4uyur1lX61SXqTNE1Vn5Yhvqwq5RByYvCJniTXEYCs9h8X7XRt88hkidg5Qu2XNTo25TtWBPunw","response":{"clientDataJSON":"eyJjaGFsbGVuZ2UiOiJ5OTRCTVhQa3oySFBXOVdoY2hfNGRqRkxHWGZvblNtOU92MEZoTS1YTXNZIiwiY2xpZW50RXh0ZW5zaW9ucyI6e30sImhhc2hBbGdvcml0aG0iOiJTSEEtMjU2Iiwib3JpZ2luIjoiaHR0cHM6Ly9vcmVvc2hha2UucmV2aWV3LWxhYi5naXRodWIuY29tIiwidHlwZSI6IndlYmF1dGhuLmNyZWF0ZSJ9","attestationObject":"o2NmbXRmcGFja2VkZ2F0dFN0bXSjY2FsZyZjc2lnWEcwRQIgD9gFoU25c1phYbNW4oB4fD_Kj3TGSdv2xEcg0-yFqRwCIQCAhL2m9y6O-wFh3h4ercBnQmoThmcpJoufsaQr7901X2N4NWOBWQLBMIICvTCCAaWgAwIBAgIEDRbt_TANBgkqhkiG9w0BAQsFADAuMSwwKgYDVQQDEyNZdWJpY28gVTJGIFJvb3QgQ0EgU2VyaWFsIDQ1NzIwMDYzMTAgFw0xNDA4MDEwMDAwMDBaGA8yMDUwMDkwNDAwMDAwMFowbjELMAkGA1UEBhMCU0UxEjAQBgNVBAoMCVl1YmljbyBBQjEiMCAGA1UECwwZQXV0aGVudGljYXRvciBBdHRlc3RhdGlvbjEnMCUGA1UEAwweWXViaWNvIFUyRiBFRSBTZXJpYWwgMjE5NjA2NTI1MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEfb_E2lHuq9DWfQUG5bFBvLTumoDR8bwXYxgCDrwsUN1-_oJqaz_3_ZJcVUV-pdTGDrW_xrbJDJyA7d0DbJHQbKNsMGowIgYJKwYBBAGCxAoCBBUxLjMuNi4xLjQuMS40MTQ4Mi4xLjcwEwYLKwYBBAGC5RwCAQEEBAMCBDAwIQYLKwYBBAGC5RwBAQQEEgQQL8BXn4ETR-qxFrtajbkgKjAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4IBAQBpg-Qf4C4xjP8hkYd2MyNxwlWU9CLURN60CKcvdQXj1GOghDUot-5e-3T0IdGVwvFS-WKcB0cYeRMrjjKW5LhmheU891iyfNikkI8DV1f0VOtnob-A_Jka-pzoDhL-ZxqbLgTlqQaneWYYFXLdYGXcDIzPoaj6t_2IgOcKvP68PeWYF0-7inZhpgG-chuWMkf5nL3hyf3e52c8-DnMzGICMRllwUyjXmESXoTJPSFovhZO3DwmHtMyxfeJRszNE0irwfDg7bBKOcn7qtp_8ynyjfRFamjzK4lmrsx0Vz_u4o9FLU-g8i6uAZ_Y_eiasYr-UbhOSqu3dnMaE-8WSGRBaGF1dGhEYXRhWMQ66wAkYDgcbyWOg5XTAm9XHw2adkiNzYN2ObE67TFlYEUAAAACL8BXn4ETR-qxFrtajbkgKgBABQa9gIySCPp4uyur1lX61SXqTNE1Vn5Yhvqwq5RByYvCJniTXEYCs9h8X7XRt88hkidg5Qu2XNTo25TtWBPun6UBAgMmIAEhWCBLKLUJVpAueZ8jO8Z2pX4sdAtE8CbtUQM-JexBLoXv8CJYIK0ZG2nvEAhRFD8dnCcdIubcvEEfTWPfK6EvjBCPHrLH"},"clientExtensionResults":{}}
      )
      assert_valid_registration(webauthn_register_challenge, response)
    end

    test "works with windows hello in chrome" do
      webauthn_register_challenge = "WKXrIuFM46_xRe9_G3xX4C8HNG51DeisZ96fB1G7US0"
      response = %(
        {"type":"public-key","id":"iikS90FWVR3vKWAN481WTWaTPyxp15LWK2l4RYv7g5jhBd7OetXXJhmZQ-ABxZD_5A9tiLvEanX_DxmsfUELdg","rawId":"iikS90FWVR3vKWAN481WTWaTPyxp15LWK2l4RYv7g5jhBd7OetXXJhmZQ-ABxZD_5A9tiLvEanX_DxmsfUELdg","response":{"clientDataJSON":"eyJ0eXBlIjoid2ViYXV0aG4uY3JlYXRlIiwiY2hhbGxlbmdlIjoiV0tYckl1Rk00Nl94UmU5X0czeFg0QzhITkc1MURlaXNaOTZmQjFHN1VTMCIsIm9yaWdpbiI6Imh0dHBzOi8vb3Jlb3NoYWtlLnJldmlldy1sYWIuZ2l0aHViLmNvbSIsImNyb3NzT3JpZ2luIjpmYWxzZX0","attestationObject":"o2NmbXRkbm9uZWdhdHRTdG10oGhhdXRoRGF0YVjEOusAJGA4HG8ljoOV0wJvVx8NmnZIjc2DdjmxOu0xZWBFAAAABAAAAAAAAAAAAAAAAAAAAAAAQIopEvdBVlUd7ylgDePNVk1mkz8sadeS1itpeEWL-4OY4QXeznrV1yYZmUPgAcWQ_-QPbYi7xGp1_w8ZrH1BC3alAQIDJiABIVggpTbh2CE1XhNRkwfAcp4NHlyKFX21jMX7YxSMj7kAKuMiWCCZ2w0e6pJL1omK7-UdfoMJhRfHBl2nmj5GX4McpjalVQ"},"clientExtensionResults":{"credProps":{}}}
      )
      assert_valid_registration(webauthn_register_challenge, response)
    end

    test "works in firefox on macos" do
      webauthn_register_challenge = "oKjSIOlE4HfF3s4n5Tgo6ApaVCBL6VhNRJB1OrLAqU4"
      response = %(
        {"type":"public-key","id":"7cFGHgSFQ18aJdC-ywma_9E73HPJbwK5kXAd_oeC3PajdoTBYRwtmYiUfW7_fpHNNkgcgCOXjRr4IkFJF9r6JQ","rawId":"7cFGHgSFQ18aJdC-ywma_9E73HPJbwK5kXAd_oeC3PajdoTBYRwtmYiUfW7_fpHNNkgcgCOXjRr4IkFJF9r6JQ","response":{"clientDataJSON":"eyJjaGFsbGVuZ2UiOiJvS2pTSU9sRTRIZkYzczRuNVRnbzZBcGFWQ0JMNlZoTlJKQjFPckxBcVU0IiwiY2xpZW50RXh0ZW5zaW9ucyI6e30sImhhc2hBbGdvcml0aG0iOiJTSEEtMjU2Iiwib3JpZ2luIjoiaHR0cHM6Ly9vcmVvc2hha2UucmV2aWV3LWxhYi5naXRodWIuY29tIiwidHlwZSI6IndlYmF1dGhuLmNyZWF0ZSJ9","attestationObject":"o2NmbXRkbm9uZWdhdHRTdG10oGhhdXRoRGF0YVjEOusAJGA4HG8ljoOV0wJvVx8NmnZIjc2DdjmxOu0xZWBBAAAAAAAAAAAAAAAAAAAAAAAAAAAAQO3BRh4EhUNfGiXQvssJmv_RO9xzyW8CuZFwHf6Hgtz2o3aEwWEcLZmIlH1u_36RzTZIHIAjl40a-CJBSRfa-iWlAQIDJiABIVgg9oKjfIBM6xiApQXhLs67eJG7u2_OPPJP9b_BM4asGIgiWCDZObtHjMjRd327yuH_u2fEhI2mBhqKP9-IOnh2SpdZIQ"},"clientExtensionResults":{}}
      )
      assert_valid_registration(webauthn_register_challenge, response)
    end

    test "works in chrome on macos" do
      webauthn_register_challenge = "lY3CgSnHopWL4rAGAFm3bMr0S0_29ZlcuWHPykU2JyY"
      response = %(
        {"type":"public-key","id":"PgxMX1WGtKC5LL9P_RBvCqqZiJ3v_hmah9cIlwvFe-bP0rfwN4Pa7lR0p5eJp7I7Mn71JTSFXXwRIccsVnJjWQ","rawId":"PgxMX1WGtKC5LL9P_RBvCqqZiJ3v_hmah9cIlwvFe-bP0rfwN4Pa7lR0p5eJp7I7Mn71JTSFXXwRIccsVnJjWQ","response":{"clientDataJSON":"eyJ0eXBlIjoid2ViYXV0aG4uY3JlYXRlIiwiY2hhbGxlbmdlIjoibFkzQ2dTbkhvcFdMNHJBR0FGbTNiTXIwUzBfMjlabGN1V0hQeWtVMkp5WSIsIm9yaWdpbiI6Imh0dHBzOi8vb3Jlb3NoYWtlLnJldmlldy1sYWIuZ2l0aHViLmNvbSIsImNyb3NzT3JpZ2luIjpmYWxzZX0","attestationObject":"o2NmbXRkbm9uZWdhdHRTdG10oGhhdXRoRGF0YVjEOusAJGA4HG8ljoOV0wJvVx8NmnZIjc2DdjmxOu0xZWBBAAAAAAAAAAAAAAAAAAAAAAAAAAAAQD4MTF9VhrSguSy_T_0QbwqqmYid7_4ZmofXCJcLxXvmz9K38DeD2u5UdKeXiaeyOzJ-9SU0hV18ESHHLFZyY1mlAQIDJiABIVggbrwlgXS1d9k5dUQ439dPe7rO6DLMkWzHb5VVDb-RFOgiWCD9wl5pDSYPSXDuxrizkwKpnTjFwL0TLwkO4ySrAvFwRg"},"clientExtensionResults":{"credProps":{"rk":false}}}
      )
      assert_valid_registration(webauthn_register_challenge, response)
    end
  end
end
