# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountsTwitterTest < GitHub::TestCase
  VALID_PROFILE_URLS = %w(
    https://twitter.com/monalisa
    https://twitter.com/@monalisa
    https://www.twitter.com/dubdubdub
    https://twitter.com/trailing-slash/
    https://x.com/alternate-host
    https://www.x.com/althost_www
  )

  INVALID_PROFILE_URLS = %w(
    https://twitter.com/
    http://twitter.com/insecure
    https://twitter.com/extra/path/sections
    https://twitter.com/extra?query=string
  )

  context "valid?" do
    VALID_PROFILE_URLS.each do |url|
      test "recognizes valid Twitter profile #{url}" do
        assert_predicate create(:social_account_twitter, url:), :valid?
      end
    end

    INVALID_PROFILE_URLS.each do |url|
      test "rejects invalid Twitter profile #{url}" do
        refute_predicate create(:social_account_twitter, url: "https://linkedin.com/in/nope"), :valid?
      end
    end
  end

  test "formats an account name as @user" do
    url = "https://twitter.com/monalisa"
    assert_equal "@monalisa", create(:social_account_twitter, url:).format_account_name
  end

  test "formats an account name as @user does not include the @ twice" do
    url = "https://twitter.com/@monalisa"
    assert_equal "@monalisa", create(:social_account_twitter, url:).format_account_name
  end
end
