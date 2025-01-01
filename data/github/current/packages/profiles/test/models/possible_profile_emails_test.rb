# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class PossibleProfileEmailsTest < GitHub::TestCase
    fixtures do
      @user_with_emails = create(:user)
    end

    if GitHub.email_verification_enabled?
      test "gets only verified emails when email verification is enabled" do
        @user_with_emails.emails.create(state: "verified", email: "verified@github.com")
        @user_with_emails.emails.create(state: "unverified", email: "unverified@github.com")

        assert_same_elements ["verified@github.com"], @user_with_emails.possible_profile_emails
      end
    else
      test "gets unverified emails when email verification is disabled" do
        @user_with_emails.emails.create(state: "unverified", email: "unverified-1@github.com")
        @user_with_emails.emails.create(state: "unverified", email: "unverified-2@github.com")

        assert_same_elements ["unverified-1@github.com", "unverified-2@github.com"], @user_with_emails.possible_profile_emails
      end
    end
  end
end
