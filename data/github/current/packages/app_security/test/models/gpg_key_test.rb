# typed: true
# frozen_string_literal: true

require "test_helper"

module GpgKeyValidationSharedTests
  extend T::Helpers

  requires_ancestor { GitHub::TestCase }

  def test_ordinary_key_is_valid
    assert_predicate @key, :valid?
  end

  def test_subkey_is_valid
    assert_predicate @sign_subkey, :valid?
  end

  def test_key_id_is_exactly_8_bytes
    @key.key_id = "A" * 7
    refute_predicate @key, :valid?

    @key.key_id = "A" * 8
    assert_predicate @key, :valid?

    @key.key_id = "A" * 9
    refute_predicate @key, :valid?
  end

  def test_public_key_is_capped_at_100kb
    @key.public_key = "A" * 101.kilobytes
    refute_predicate @key, :valid?

    @key.public_key = "A" * 99.kilobytes
    assert_predicate @key, :valid?
  end

  def test_name_is_capped_at_100_chars_and_can_be_blank
    @key.name = "A" * 101
    refute_predicate @key, :valid?

    @key.name = "A" * 99
    assert_predicate @key, :valid?

    @key.name = nil
    assert_predicate @key, :valid?
  end

  def test_public_key_is_unique_per_user
    new_key = @user.gpg_keys.create_from_armored_public_key(@armored_public_key)
    refute_predicate new_key, :valid?
  end

  def test_subkey_key_ids_are_unique
    armored = GpgKeyHelper::KEYS["dup_key_ids"]["armored_public_key"]
    new_key = @user.gpg_keys.create_from_armored_public_key(armored)
    refute_predicate new_key, :new_record?
    refute_predicate new_key.errors, :any?

    # 12 total, 10 of which were the same
    assert_equal 3, new_key.subkeys.count
  end

  def test_does_not_require_subkeys
    armored = GpgKeyHelper::KEYS["no_sub_keys"]["armored_public_key"]
    new_key = @user.gpg_keys.create_from_armored_public_key(armored)
    refute_predicate new_key, :new_record?
    refute_predicate new_key.errors, :any?
  end

  def test_public_key_is_not_globally_unique
    new_key = @other_user.gpg_keys.create_from_armored_public_key(@armored_public_key)
    assert_predicate new_key, :valid?
  end

  def test_public_key_validates_utf8
    new_key = @user.gpg_keys.create_from_armored_public_key(@emoji)
    assert_predicate new_key.errors, :any?
    assert_equal new_key.errors.first.type, "contains unsupported characters"
  end
end

module GpgKeyInstrumentationSharedTests
  extend T::Helpers

  requires_ancestor { GitHub::TestCase }

  def test_creation
    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      key_id: @key.hex_key_id,
      subkeys: @key.subkeys.map(&:hex_key_id),
      emails: @key.emails.map(&:email),
      expires_at: @key.expires_at,
      can_sign: @key.can_sign,
      can_encrypt_comms: @key.can_encrypt_comms,
      can_encrypt_storage: @key.can_encrypt_storage,
      can_certify: @key.can_certify,
      name: @key.name,
      revoked: @key.revoked,
    }.sort
    @key.destroy
    events = subscribe "gpg_key.create"
    @user.gpg_keys.create_from_armored_public_key(@armored_public_key)

    assert event = events.pop, "an event was expected"
    assert_equal "gpg_key.create", event.name
    assert_equal expected_payload, event.payload.sort
  end

  def test_deletion
    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      key_id: @key.hex_key_id,
    }
    events = subscribe "gpg_key.destroy"
    @key.destroy

    assert event = events.pop, "an event was expected"
    assert_equal "gpg_key.destroy", event.name
    assert_equal expected_payload, event.payload
  end
end

module GpgKeyCreateFromArmoredPublicKeySharedTests
  extend T::Helpers

  requires_ancestor { GitHub::TestCase }

  def test_saves_raw_key
    refute_predicate @key, :blank?
  end

  def test_decodes_armored_public_key
    @key.destroy

    new_key = @user.gpg_keys.create_from_armored_public_key(@armored_public_key)
    assert_predicate new_key, :valid?
    assert_equal @public_key, new_key.public_key
    assert_equal @key_id, new_key.key_id
  end

  def test_does_not_trigger_query_warnings
    @key.destroy

    T.cast(self, T.untyped).assert_no_query_warnings do
      new_key = @user.gpg_keys.create_from_armored_public_key(@armored_public_key)
      assert_equal @public_key, new_key.public_key
      assert_equal @key_id, new_key.key_id
    end
  end

  def test_allows_leading_whitespace
    @key.destroy

    ws_key = @armored_public_key.split("\n").map { |l| "  " + l }.join("\n")
    new_key = @user.gpg_keys.create_from_armored_public_key(ws_key)
    assert_predicate new_key, :valid?
    assert_equal @public_key, new_key.public_key
    assert_equal @key_id, new_key.key_id
  end

  def test_emails_added_from_key
    emails = @key.emails
    assert_equal 1, emails.size
    assert_equal "someuser@gmail.com", emails.first.email
    assert_equal @user.emails.verified.first, emails.first.user_email
  end
end

module GpgKeyExpiredSharedTests
  extend T::Helpers

  requires_ancestor { GitHub::TestCase }

  def test_false_for_nil_expiration
    refute_predicate @key, :expired?
  end

  def test_true_for_expired_keys
    assert_predicate @expired_key, :expired?
  end
end

module GpgKeyCanSignSharedTests
  extend T::Helpers

  requires_ancestor { GitHub::TestCase }

  def test_true_for_signing_key
    assert_predicate @sign_subkey, :can_sign?
    assert_predicate @key, :can_sign?
    assert_predicate @other_key, :can_sign?
  end

  def test_false_for_encryption_key
    refute_predicate @encrypt_subkey, :can_sign?
  end
end

module GpgKeyAllowedEmailSharedTests
  extend T::Helpers

  requires_ancestor { GitHub::TestCase }

  def test_verified_emails_that_are_in_key_are_allowed
    assert @key.allowed_email?("someuser@gmail.com", business: @enterprise), "expected someuser@gmail.com to be allowed"
    assert @sign_subkey.allowed_email?("someuser@gmail.com", business: @enterprise), "expected someuser@gmail.com to be allowed"
  end

  def test_emails_not_in_key_are_disallowed
    email = "#{SecureRandom.hex}@gmail.com"
    create(:user_email, :verified, user: @user, email: email)
    refute @key.allowed_email?(email, business: @enterprise), "expected #{email} to not be allowed"
    refute @sign_subkey.allowed_email?(email, business: @enterprise), "expected #{email} to not be allowed"
  end

  def test_unverified_emails_verification
    email = if @user.is_enterprise_managed?
      User::EnterpriseManagedDependency.add_shortcode("someuser@gmail.com", @user.enterprise_managed_business)
    else
      "someuser@gmail.com"
    end

    @user.emails.where(email: email).first.unverify!

    if @user.is_enterprise_managed?
      assert @key.allowed_email?("someuser@gmail.com", business: @enterprise), "expected someuser@gmail.com to not be allowed"
      assert @sign_subkey.allowed_email?("someuser@gmail.com", business: @enterprise), "expected someuser@gmail.com to not be allowed"
    elsif GitHub.email_verification_enabled?
      refute @key.allowed_email?("someuser@gmail.com", business: @enterprise), "expected someuser@gmail.com to not be allowed"
      refute @sign_subkey.allowed_email?("someuser@gmail.com", business: @enterprise), "expected someuser@gmail.com to not be allowed"
    else
      assert @key.allowed_email?("someuser@gmail.com", business: @enterprise), "expected someuser@gmail.com to not be allowed"
      assert @sign_subkey.allowed_email?("someuser@gmail.com", business: @enterprise), "expected someuser@gmail.com to not be allowed"
    end
  end

  def test_emails_are_not_case_sensitive
    assert @key.allowed_email?("SomeUser@gmail.com", business: @enterprise), "expected SomeUser@gmail.com to be allowed"
    assert @sign_subkey.allowed_email?("SomeUser@gmail.com", business: @enterprise), "expected SomeUser@gmail.com to be allowed"
  end

  def test_legacy_stealth_emails_are_not_case_sensitive
    user = create(:user, login: "MiXeDcAsE")
    key = T.unsafe(self).create_gpg_key(user: user)
    email = StealthEmail.new(user).legacy_email
    key.emails.create(email: email)

    assert key.allowed_email?(email), "expected #{email} to be allowed"
  end

  def test_legacy_stealth_emails_are_not_allowed_unless_in_key
    email = StealthEmail.new(@user).legacy_email

    refute @key.allowed_email?(email, business: @enterprise), "expected #{email} not to be allowed"
  end
end

module GpgKeyVerifySharedTests
  extend T::Helpers

  requires_ancestor { GitHub::TestCase }

  def test_returns_true_for_valid_signatures
    assert @key.verify(@message, @signature), "expected signature to be valid"
  end

  def test_returns_false_for_invalid_signatures
    refute @other_key.verify(@message, @signature), "expected signature to be invalid"
  end
end

module GpgKeyHexKeyIdSharedTests
  extend T::Helpers

  requires_ancestor { GitHub::TestCase }

  def test_returns_hex_key_id
    assert_equal "3262EFF25BA0D270", @key.hex_key_id
    assert_equal "8AA21378761AB66F", @sign_subkey.hex_key_id
  end
end

module GpgKeyCreateEmailsSharedTests
  extend T::Helpers

  requires_ancestor { GitHub::TestCase }

  def test_does_not_raise_if_no_emails
    @key.create_emails([])
    @key.create_emails([{}])
    @key.create_emails([{ "email" => nil }])
    @key.create_emails([{ "email" => "" }])
  end
end

module GpgKeyUpdateGpgKeyEmailsSharedTests
  extend T::Helpers

  requires_ancestor { GitHub::TestCase }

  def test_email_has_user_email_id_removed_when_user_email_changes
    user_email = @user.emails.verified.first
    user_email.email = "#{SecureRandom.hex}@gmail.com"
    user_email.save

    assert_nil @key.emails.first.user_email
  end

  def remove_then_readd_verified_gpg_email
    user_email = @user.emails.verified.first

    # create an additional email to avoid errors around deleting the "last primary email"
    create :user_email, user: @user

    # save the email string to reuse later to help with the enterprise_managed_business.shortcode in EMU mode
    user_email_string = user_email.email

    gpg_key_email = @key.emails.where(user_email_id: user_email.id).first

    user_email.destroy!
    assert_nil gpg_key_email.reload.user_email_id

    # add back the original verified emu email
    readd_email = create :user_email, user: @user, state: "verified", email: user_email_string

    assert_equal readd_email.id, gpg_key_email.reload.user_email_id
  end
end

class GpgKeyTest < GitHub::TestCase
  include GpgKeyValidationSharedTests
  include GpgKeyInstrumentationSharedTests
  include GpgKeyCreateFromArmoredPublicKeySharedTests
  include GpgKeyExpiredSharedTests
  include GpgKeyCanSignSharedTests
  include GpgKeyAllowedEmailSharedTests
  include GpgKeyVerifySharedTests
  include GpgKeyHexKeyIdSharedTests
  include GpgKeyCreateEmailsSharedTests
  include GpgKeyUpdateGpgKeyEmailsSharedTests

  include GpgKeyHelper
  include GitHub::DatabaseQueryWarningsTestHelpers

  fixtures do
    @key = create_gpg_key
    @user = @key.user
    @public_key = @key.public_key
    @key_id = @key.key_id
    @armored_public_key = GpgKeyHelper::KEYS["one"]["armored_public_key"]
    @emoji = GpgKeyHelper::KEYS["utf8mb4"]["armored_public_key"]

    @encrypt_subkey = @key.subkeys.first
    @sign_subkey = @key.subkeys.last

    @expired_key = create_gpg_key("expired")

    @other_key = create_gpg_key("two")
    @other_user = @other_key.user
    @other_public_key = @other_key.public_key
    @other_key_id = @other_key.key_id

    @message = "hello world"
    @signature = <<-HERE.gsub(/^ +|\n\z/, "")
      -----BEGIN PGP SIGNATURE BLOCK-----

      iQEcBAEBAgAGBQJWsnMPAAoJEDJi7/JboNJw1JcH/3Q1Bi/BxhLl6TUo+vIprnz9
      liGBzTeX6RdLprsuzx+gdgT0183q+fNtNWQESsmnsKtdKHZoTUykH3Y03kj8OEHf
      1Z/NoQc6igolOzBqaHYw7jtNC+DDNpEHJGZvRGy7Ikj8ZZWiJ8gvIHSgNS2BfJvS
      vbXFazhT093ol9QJ6+T7rtKlMgR1B34jW5nGf85ZeRJU3FY3LnYJi+ncK6pfLeIz
      AER2Fa/fA+0hST4O7q5Muy/Bh5AQqMQJ7edAJnk7gYmvPc0ktV+1Xn8z7sIvYPws
      BlinAotMZ+tBoy3EMxq8WxakR6nEwtD51z2zkw3/v/T6qXGPEP2lwEYfzP9vFqE=
      =ggHD
      -----END PGP SIGNATURE BLOCK-----
    HERE
  end

  test "legacy stealth emails are allowed if in key" do
    email = StealthEmail.new(@user).legacy_email
    @key.emails.create(email: email)

    assert @key.allowed_email?(email), "expected #{email} to be allowed"
  end

  context "GpgKey.create_from_armored_public_key" do
    test "adds emails that are not on account" do
      @key.destroy
      @user.emails.verified.destroy_all

      key = create_gpg_key(user: @user)
      assert_equal "someuser@gmail.com", key.emails.first.email
    end

    test "successfully creates primary key when all subkeys are revoked" do
      key = create_gpg_key("all_revoked_subkeys", user: @user)
      refute_nil key
      assert_empty key.subkeys
    end
  end

  context "UserEmail#update_gpg_key_emails" do
    test "email has user_email_id removed when user email is removed" do
      @user.emails.verified.destroy_all
      assert_nil @key.emails.first.user_email_id
    end

    test "email has user_email_id added when user email is added" do
      @user.emails.verified.destroy_all
      assert_nil @key.emails.first.reload.user_email_id

      user_email = @user.emails.create(
        state: "verified",
        email: "someuser@gmail.com",
      )

      assert_equal user_email, @key.emails.first.user_email
    end
  end
end

class EmuGpgKeyTest < GitHub::TestCase
  include GpgKeyValidationSharedTests
  include GpgKeyInstrumentationSharedTests
  include GpgKeyCreateFromArmoredPublicKeySharedTests
  include GpgKeyExpiredSharedTests
  include GpgKeyCanSignSharedTests
  include GpgKeyAllowedEmailSharedTests
  include GpgKeyVerifySharedTests
  include GpgKeyHexKeyIdSharedTests
  include GpgKeyCreateEmailsSharedTests
  include GpgKeyUpdateGpgKeyEmailsSharedTests

  include GpgKeyHelper
  include GitHub::DatabaseQueryWarningsTestHelpers

  fixtures do
    @key = create_gpg_key emu: true
    @user = @key.user

    @enterprise = @user.enterprise_managed_business

    @public_key = @key.public_key
    @key_id = @key.key_id
    @armored_public_key = GpgKeyHelper::KEYS["one"]["armored_public_key"]
    @emoji = GpgKeyHelper::KEYS["utf8mb4"]["armored_public_key"]

    @encrypt_subkey = @key.subkeys.first
    @sign_subkey = @key.subkeys.last

    @expired_key = create_gpg_key("expired", business: @enterprise, emu: true)

    @other_key = create_gpg_key("two", business: @enterprise, emu: true)
    @other_user = @other_key.user
    @other_public_key = @other_key.public_key
    @other_key_id = @other_key.key_id

    @message = "hello world"
    @signature = <<-HERE.gsub(/^ +|\n\z/, "")
      -----BEGIN PGP SIGNATURE BLOCK-----

      iQEcBAEBAgAGBQJWsnMPAAoJEDJi7/JboNJw1JcH/3Q1Bi/BxhLl6TUo+vIprnz9
      liGBzTeX6RdLprsuzx+gdgT0183q+fNtNWQESsmnsKtdKHZoTUykH3Y03kj8OEHf
      1Z/NoQc6igolOzBqaHYw7jtNC+DDNpEHJGZvRGy7Ikj8ZZWiJ8gvIHSgNS2BfJvS
      vbXFazhT093ol9QJ6+T7rtKlMgR1B34jW5nGf85ZeRJU3FY3LnYJi+ncK6pfLeIz
      AER2Fa/fA+0hST4O7q5Muy/Bh5AQqMQJ7edAJnk7gYmvPc0ktV+1Xn8z7sIvYPws
      BlinAotMZ+tBoy3EMxq8WxakR6nEwtD51z2zkw3/v/T6qXGPEP2lwEYfzP9vFqE=
      =ggHD
      -----END PGP SIGNATURE BLOCK-----
    HERE
  end

  context "#allowed_email?" do
    test "case sensitive shortcode returns true" do
      business = create :business, :enterprise_managed, shortcode: "ABC"
      key = create_gpg_key("three", emu: true, business: business)
      user = key.user

      assert key.allowed_email?("nickborromeo@github.com", business: business), "expected nickborromeo@github.com to be allowed"
    end
  end
end unless GitHub.single_business_environment?
