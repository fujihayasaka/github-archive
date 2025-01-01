# typed: true
# frozen_string_literal: true

require "test_helper"

class UserEmailMarketingDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @email = @user.primary_user_email
    @email.verify!
  end

  context "#should_be_subscribed_in_mailchimp?" do
    test "false if email isn't primary" do
      email = @user.add_email "secondary@gmail.com"
      email.verify!
      refute email.primary?

      refute email.should_be_subscribed_in_mailchimp?
    end

    test "false if email isn't verified" do
      @email.update_column(:state, "unverified")
      refute @email.verified?
      refute @email.should_be_subscribed_in_mailchimp?
    end

    test "false if user has transactional email preference" do
      NewsletterPreference.set_to_transactional(user: @user)
      refute @email.should_be_subscribed_in_mailchimp?
    end

    test "false if domain is considered invalid by Mailchimp" do
      @email.update_column(:email, "janedoe@mailinator.com")
      refute @email.should_be_subscribed_in_mailchimp?
    end

    test "false if user has no email preference" do
      refute @email.should_be_subscribed_in_mailchimp?
    end

    test "true if user has marketing email preference" do
      NewsletterPreference.set_to_marketing(user: @user)
      assert @email.should_be_subscribed_in_mailchimp?
    end
  end

  context "GDC integration" do
    test "Valid email matches marketing email validation regex" do
      email = "monalisa123+test@github.com"
      assert email.match?(UserEmail::MarketingDependency::EMAIL_REGEX)
    end

    test "Marketing email regex requires top level domain" do
      email = "test@github"
      refute email.match?(UserEmail::MarketingDependency::EMAIL_REGEX)
    end

    test "Marketing personal email domain regex does not allow personal domains" do
      email = "monalisa@gmail.com"
      refute email.match?(UserEmail::MarketingDependency::EMAIL_PERSONAL_DOMAIN_REGEX)
    end

    test "Marketing personal email domain regex does not allow personal domains with other TLDs" do
      email = "test@hotmail.co.uk"
      refute email.match?(UserEmail::MarketingDependency::EMAIL_PERSONAL_DOMAIN_REGEX)
    end
  end
end
