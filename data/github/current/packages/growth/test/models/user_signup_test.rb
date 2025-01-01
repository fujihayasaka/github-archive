# typed: true
# frozen_string_literal: true

require "test_helper"

class UserSignupTest < GitHub::TestCase
  setup do
    @user = create(:user)
  end

  test "user_signup saves when valid" do
    user_signup = UserSignup.new(
      user: @user,
      email: @user.email,
      country_code: "US",
      marketing_consent: :explicit_optin
    )

    assert user_signup.valid?
    user_signup.save

    user_signup.reload
    assert user_signup.id != nil
    assert user_signup.user == @user
    assert user_signup.email == @user.email
    assert user_signup.country_code == "US"
    assert user_signup.marketing_consent_explicit_optin?
  end

  test "unable to save user_signup without an email" do
    user_signup = UserSignup.new(
      user: @user,
      email: nil,
      country_code: "US",
      marketing_consent: :explicit_optin
    )

    refute user_signup.valid?
    assert_raises ActiveRecord::RecordInvalid do
      user_signup.save!
    end
  end

  test "unable to save user_signup when email is too long" do
    user_signup = UserSignup.new(
      user: @user,
      email: "a" * 256 + "@example.com",
      country_code: "US",
      marketing_consent: :explicit_optin
    )

    refute user_signup.valid?
    assert_raises ActiveRecord::RecordInvalid do
      user_signup.save!
    end
  end

  test "unable to save user_signup when email is invalid" do
    user_signup = UserSignup.new(
      user: @user,
      email: "not_an_email",
      country_code: "US",
      marketing_consent: :explicit_optin
    )

    refute user_signup.valid?
    assert_raises ActiveRecord::RecordInvalid do
      user_signup.save!
    end
  end

  test "unable to save user_signup without a country code" do
    user_signup = UserSignup.new(
      user: @user,
      email: @user.email,
      country_code: nil,
      marketing_consent: :explicit_optin
    )

    refute user_signup.valid?
    assert_raises ActiveRecord::RecordInvalid do
      user_signup.save!
    end
  end

  test "unable to save user_signup when country code is invalid" do
    user_signup = UserSignup.new(
      user: @user,
      email: @user.email,
      country_code: "not_a_country_code",
      marketing_consent: :explicit_optin
    )

    refute user_signup.valid?
    assert_raises ActiveRecord::RecordInvalid do
      user_signup.save!
    end
  end

  test "unable to save user_signup when country code is too short" do
    user_signup = UserSignup.new(
      user: @user,
      email: @user.email,
      country_code: "A",
      marketing_consent: :explicit_optin
    )

    refute user_signup.valid?
    assert_raises ActiveRecord::RecordInvalid do
      user_signup.save!
    end
  end

  test "unable to save user_signup when country code is too long" do
    user_signup = UserSignup.new(
      user: @user,
      email: @user.email,
      country_code: "ABC",
      marketing_consent: :explicit_optin
    )

    refute user_signup.valid?
    assert_raises ActiveRecord::RecordInvalid do
      user_signup.save!
    end
  end

  test "unable to save user_signup when country code is not in the list of marketing targeted countries" do
    user_signup = UserSignup.new(
      user: @user,
      email: @user.email,
      country_code: "KP",
      marketing_consent: :explicit_optin
    )

    refute user_signup.valid?
    assert_raises ActiveRecord::RecordInvalid do
      user_signup.save!
    end
  end

  test "user_signup saves when marketing consent is nil" do
    user_signup = UserSignup.new(
      user: @user,
      email: @user.email,
      country_code: "US",
      marketing_consent: nil
    )

    assert user_signup.valid?
    user_signup.save

    user_signup.reload
    assert user_signup.id != nil
    assert user_signup.user == @user
    assert user_signup.email == @user.email
    assert user_signup.country_code == "US"
    assert user_signup.marketing_consent.nil?
  end

  test "user_signup saves when marketing consent is valid" do
    user_signup = UserSignup.new(
      user: @user,
      email: @user.email,
      country_code: "US",
      marketing_consent: :implicit_optin
    )

    assert user_signup.valid?
    user_signup.save

    user_signup.reload
    assert user_signup.id != nil
    assert user_signup.user == @user
    assert user_signup.email == @user.email
    assert user_signup.country_code == "US"
    assert user_signup.marketing_consent_implicit_optin?
  end

  test "unable to save user_signup when marketing consent is invalid" do
    user_signup = UserSignup.new(
      user: @user,
      email: @user.email,
      country_code: "US",
      marketing_consent: :not_a_valid_consent
    )

    refute user_signup.valid?
    assert_raises ActiveRecord::RecordInvalid do
      user_signup.save!
    end
  end

  test "user_signup saves when onboarding optout date is nil" do
    user_signup = UserSignup.new(
      user: @user,
      email: @user.email,
      country_code: "US",
      marketing_consent: :explicit_optin,
      onboarding_optout_date: nil
    )

    assert user_signup.valid?
    user_signup.save

    user_signup.reload
    assert user_signup.id != nil
    assert user_signup.user == @user
    assert user_signup.email == @user.email
    assert user_signup.country_code == "US"
    assert user_signup.marketing_consent_explicit_optin?
    assert user_signup.onboarding_optout_date.nil?
  end

  test "unable to save user_signup when onboarding optout date is invalid" do
    user_signup = UserSignup.new(
      user: @user,
      email: @user.email,
      country_code: "US",
      marketing_consent: :explicit_optin,
      onboarding_optout_date: 1000000.years.from_now
    )

    refute user_signup.valid?
    assert_raises ActiveRecord::RecordInvalid do
      user_signup.save!
    end
  end

  test "saves user_signup when onboarding optout date is valid" do
    time = Time.now.iso8601

    user_signup = UserSignup.new(
      user: @user,
      email: @user.email,
      country_code: "US",
      marketing_consent: :explicit_optin,
      onboarding_optout_date: time
    )

    assert user_signup.valid?
    user_signup.save

    user_signup.reload
    assert user_signup.id != nil
    assert user_signup.user == @user
    assert user_signup.email == @user.email
    assert user_signup.country_code == "US"
    assert user_signup.marketing_consent_explicit_optin?
    assert user_signup.onboarding_optout_date == time
  end
end
