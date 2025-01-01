# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class ProfileEmailIsValidTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
    end

    if GitHub.email_verification_enabled?
      test "does not allow unverified email addresses" do
        unverified = @user.emails.create(state: "unverified", email: Faker::Internet.email)

        @user.profile_email = unverified.email
        refute_predicate @user, :valid?
        assert_includes @user.errors[:profile_email], "must be one of the user's verified email addresses"
      end

      test "does not allow unregistered email addresses" do
        @user.profile_email = Faker::Internet.email
        refute_predicate @user, :valid?
        assert_includes @user.errors[:profile_email], "must be one of the user's verified email addresses"
      end
    else
      test "allows unverified email addresses" do
        unverified = @user.emails.create(state: "unverified", email: Faker::Internet.email)

        @user.profile_email = unverified.email
        assert_predicate @user, :valid?
      end

      test "does not allow unregistered email addresses" do
        @user.profile_email = Faker::Internet.email
        refute_predicate @user, :valid?
        assert_includes @user.errors[:profile_email], "must be one of the user's known email addresses"
      end
    end

    test "allows verified email addresses" do
      verified = @user.emails.create(state: "verified", email: Faker::Internet.email)

      @user.profile_email = verified.email
      assert_predicate @user, :valid?
    end

    test "allows current profile email" do
      profile = create(:profile, user: @user)

      @user.profile_email = profile.email
      assert_predicate @user, :valid?
    end

    test "allows nil email" do
      create(:profile, user: @user)

      @user.profile_email = nil
      assert_predicate @user, :valid?
    end
  end
end
