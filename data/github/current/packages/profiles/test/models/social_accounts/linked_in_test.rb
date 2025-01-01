# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountsLinkedInTest < GitHub::TestCase
  VALID_PROFILE_URLS = %w(
    https://linkedin.com/in/monalisa
    https://www.linkedin.com/in/monalisa
    https://www.linkedin.com/in/trailing-slash-42/
    https://www.linkedin.com/in/escaped-%C3%A9-chars
    https://www.linkedin.com/company/github
  )

  INVALID_PROFILE_URLS = %w(
    http://linkedin.com/in/insecure
    https://linkedout.com/nope/monalisa
    https://www.linkedin.com/in/extra/path/sections
    https://www.linkedin.com/in/extra?query=string
  )

  context "valid?" do
    VALID_PROFILE_URLS.each do |url|
      test "recognizes valid LinkedIn profile #{url}" do
        assert_predicate create(:social_account_linkedin, url:), :valid?
      end
    end

    INVALID_PROFILE_URLS.each do |url|
      test "rejects invalid LinkedIn profile #{url}" do
        refute_predicate create(:social_account_linkedin, url:), :valid?
      end
    end
  end

  context "format_account_name" do
    test "trims the protocol and hostname" do
      url = "https://www.linkedin.com/in/monalisa/"
      assert_equal "in/monalisa", create(:social_account_linkedin, url:).format_account_name
    end

    test "trims company profiles" do
      url = "https://www.linkedin.com/company/github/"
      assert_equal "company/github", create(:social_account_linkedin, url:).format_account_name
    end

    test "trims without the www. subdomain" do
      url = "https://linkedin.com/in/monalisa"
      assert_equal "in/monalisa", create(:social_account_linkedin, url:).format_account_name
    end
  end
end
