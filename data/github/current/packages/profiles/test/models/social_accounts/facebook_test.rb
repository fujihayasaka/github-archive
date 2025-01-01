# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountsFacebookTest < GitHub::TestCase
  VALID_PROFILE_URLS = %w(
    https://www.facebook.com/monalisa
    https://facebook.com/someone
    https://www.facebook.com/with.a.dot
    https://www.facebook.com/numbers123
    https://m.facebook.com/iusemobile
    https://www.facebook.com/profile.php?id=1234567890
    https://www.facebook.com/trailing.slash/
  )

  INVALID_PROFILE_URLS = %w(
    https://notbook.com/someone
    http://facebook.com/insecure
    https://www.facebook.com/extra.path/after/username
    https://www.facebook.com/extra.args?doBadThings=true
  )

  context "valid?" do
    VALID_PROFILE_URLS.each do |profile_url|
      test "recognizes valid Facebook profile #{profile_url}" do
        assert_predicate create(:social_account_facebook, url: profile_url), :valid?
      end
    end

    INVALID_PROFILE_URLS.each do |profile_url|
      test "rejects an invalid Facebook profile #{profile_url}" do
        refute_predicate create(:social_account_facebook, url: profile_url), :valid?
      end
    end
  end

  context "formatted account name" do
    test "trims the protocol and hostname" do
      url = "https://facebook.com/monalisa"
      assert_equal "monalisa", create(:social_account_facebook, url:).format_account_name
    end

    test "trims common subdomains" do
      url = "https://web.facebook.com/username"
      assert_equal "username", create(:social_account_facebook, url:).format_account_name
    end

    test "trims trailing slash" do
      url = "https://facebook.com/monalisa/"
      assert_equal "monalisa", create(:social_account_facebook, url:).format_account_name
    end

    test "leaves uncommon subdomains" do
      url = "https://developer.facebook.com/username"
      assert_equal url, create(:social_account_facebook, url:).format_account_name
    end
  end
end
