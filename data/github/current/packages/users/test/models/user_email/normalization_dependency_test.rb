# typed: true
# frozen_string_literal: true

require "test_helper"

class UserEmailnormalizeTest < GitHub::TestCase
  test "raises an ArgumentError if given a bad email address" do
    assert_raises ArgumentError do
      UserEmail.normalize "bad email"
    end
  end

  test "handles email addresses with single-level domain" do
    assert_equal "john@localhost", UserEmail.normalize("john@localhost")
  end

  test "downcases the email address" do
    assert_equal "support@github.com", UserEmail.normalize("Support@GitHub.com")
  end

  test "does local-part normalization for gmail domains" do
    assert_equal "johnsmith@gmail.com", UserEmail.normalize("john.smith@gmail.com")

    assert_equal "john.smith@github.com", UserEmail.normalize("john.smith@github.com")
  end

  test "removes sub-addresses from gmail domains" do
    assert_equal "hello@gmail.com", UserEmail.normalize("hello+sub@gmail.com")

    assert_equal "hello+sub@github.com", UserEmail.normalize("hello+sub@github.com")
  end

  test "removes sub-addresses from icloud domains" do
    assert_equal "hello@icloud.com", UserEmail.normalize("hello+sub@icloud.com")
    assert_equal "hello@mac.com", UserEmail.normalize("hello+sub@mac.com")
    assert_equal "hello@me.com", UserEmail.normalize("hello+sub@me.com")

    assert_equal "hello+sub@github.com", UserEmail.normalize("hello+sub@github.com")
  end

  test "removes sub-addresses from outlook domains" do
    assert_equal "hello@outlook.com", UserEmail.normalize("hello+sub@outlook.com")

    assert_equal "hello+sub@github.com", UserEmail.normalize("hello+sub@github.com")
  end

  test "removes sub-addresses from yahoo domains" do
    assert_equal "hello@yahoo.com", UserEmail.normalize("hello-sub@yahoo.com")
    assert_equal "hello@ymail.com", UserEmail.normalize("hello-sub@ymail.com")

    assert_equal "hello-sub@github.com", UserEmail.normalize("hello-sub@github.com")
  end

  test "normalizes very denormalized addresses" do
    assert_equal "helloworld@gmail.com", UserEmail.normalize("Hello.World+sub@gMail.com")
  end
end

class UserEmailsafeBulkNormalizeTest < GitHub::TestCase
  test "normalizes a number of users and email addresses" do
    user = create(:user)
    user.add_email("One@example.com")
    user.add_email("Two@example.com")
    emails = %w(Three@example.com Four@example.com)

    result = UserEmail.safe_bulk_normalize(users: user, emails: emails, verified: false)

    expected = %w(one@example.com two@example.com three@example.com four@example.com) << user.email

    assert_same_elements expected, result
  end

  test "handles no users" do
    emails = %w(Three@example.com Four@example.com)

    result = UserEmail.safe_bulk_normalize(users: nil, emails: emails, verified: false)

    expected = %w(three@example.com four@example.com)

    assert_same_elements expected, result
  end

  test "handles no emails" do
    user = create(:user)
    user.add_email("One@example.com")
    user.add_email("Two@example.com")

    result = UserEmail.safe_bulk_normalize(users: user, emails: nil, verified: false)

    expected = %w(one@example.com two@example.com) << user.email

    assert_same_elements expected, result
  end

  test "handles invalid emails" do
    user = create(:user)
    user.add_email("INVALID EMAIL ADDRESS")
    emails = %w(Three@example.com INVALID!)

    result = UserEmail.safe_bulk_normalize(users: user, emails: emails, verified: false)

    expected = %w(three@example.com) << user.email

    assert_same_elements expected, result
  end

  test "returns only verified user emails by default" do
    user = create(:user)
    user.emails.delete_all
    user.emails << create(:user_email, :verified, email: "verified@example.com")
    user.emails << create(:user_email, email: "unverified@example.com")

    result = UserEmail.safe_bulk_normalize(users: user)

    assert_same_elements %w(verified@example.com), result
  end

  test "doesn't return private emails if argument is set to false" do
    user = create(:user)
    user.emails.delete_all

    user.add_email("verified-private@example.com", is_primary: true)
    user.primary_user_email.verify!
    user.primary_user_email.toggle_visibility
    refute user.primary_user_email.public?

    user.emails << create(:user_email, :verified, email: "verified-public@example.com")

    result = UserEmail.safe_bulk_normalize(users: user, include_private_emails: false)

    assert_same_elements %w(verified-public@example.com), result
  end

  test "returns private emails by default" do
    user = create(:user)
    user.emails.delete_all

    user.add_email("verified-private@example.com", is_primary: true)
    user.primary_user_email.verify!
    user.primary_user_email.toggle_visibility
    refute user.primary_user_email.public?

    user.emails << create(:user_email, :verified, email: "verified-public@example.com")

    result = UserEmail.safe_bulk_normalize(users: user)

    assert_same_elements %w(verified-private@example.com verified-public@example.com), result
  end
end

class UserEmailemailAddressesForTest < GitHub::TestCase
  test "returns unverified and private emails by default" do
    user = create(:user)
    user.emails.delete_all
    user.emails << create(:user_email, email: "unverified@example.com")

    user.add_email("verified@example.com", is_primary: true)
    user.primary_user_email.verify!
    user.primary_user_email.toggle_visibility
    refute user.primary_user_email.public?

    result = UserEmail.email_addresses_for(user)

    assert_same_elements %w(unverified@example.com verified@example.com), result
  end

  test "does not return private emails if include_private_emails is false" do
    user = create(:user)
    user.emails.delete_all
    user.emails << create(:user_email, email: "unverified@example.com")

    result = UserEmail.email_addresses_for(user, include_private_emails: false)

    user.add_email("verified@example.com", is_primary: true)
    user.primary_user_email.verify!
    user.primary_user_email.toggle_visibility
    refute user.primary_user_email.public?

    assert_same_elements %w(unverified@example.com), result
  end

  test "returns only verified emails if verified is true" do
    user = create(:user)
    user.emails.delete_all
    user.emails << create(:user_email, :verified, email: "verified@example.com")
    user.emails << create(:user_email, email: "unverified@example.com")

    result = UserEmail.email_addresses_for(user, verified: true)

    assert_same_elements %w(verified@example.com), result
  end

  test "returns no emails for a mannequin" do
    mannequin = create(:mannequin)

    result = UserEmail.email_addresses_for(mannequin, verified: true, include_private_emails: false)

    assert_same_elements [], result
  end
end
