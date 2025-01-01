# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountsNpmTest < GitHub::TestCase
  VALID_PROFILE_URLS = %w(
    https://npmjs.com/~monalisa
    https://npmjs.com/~monalisa/
    https://www.npmjs.com/~monalisa/
  )

  INVALID_PROFILE_URLS = %w(
    https://example.com
    https://npmjs.com/monalisa
    https://npmjs.com/
    https://npmjs.com/~
    https://npmjs.com/hello/world
    https://npmjs.com?~monalisa
  )

  context "valid?" do
    VALID_PROFILE_URLS.each do |url|
      test "recognizes valid npm profile #{url}" do
        assert_predicate create(:social_account_npm, url: url), :valid?
      end
    end

    INVALID_PROFILE_URLS.each do |url|
      test "rejects invalid npm profile #{url}" do
        refute_predicate create(:social_account_npm, url: url), :valid?
      end
    end
  end

  context "#format_account_name" do
    test "removes the protocol and hostname" do
      url = "https://npmjs.com/~monalisa"
      assert_equal "monalisa", create(:social_account_npm, url: url).format_account_name
    end

    test "removes a www. subdomain" do
      url = "https://www.npmjs.com/~monalisa"
      assert_equal "monalisa", create(:social_account_npm, url: url).format_account_name
    end

    test "removes a trailing slash" do
      url = "https://npmjs.com/~monalisa/"
      assert_equal "monalisa", create(:social_account_npm, url: url).format_account_name
    end
  end
end
