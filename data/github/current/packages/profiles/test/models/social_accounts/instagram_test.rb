# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountsInstagramTest < GitHub::TestCase
  VALID_PROFILE_URLS = %w(
    https://instagram.com/monalisa
    https://instagram.com/monalisa/
    https://instagram.com/with.special_chars7
  )

  INVALID_PROFILE_URLS = %w(
    https://example.com/
    http://instagram.com/insecure
    https://instagram.com/
    https://instagram.com/extra/path/sections
    https://instagram.com/extra?query=string
  )

  context "valid?" do
    VALID_PROFILE_URLS.each do |url|
      test "recognizes valid profile #{url}" do
        assert_predicate create(:social_account_instagram, url:), :valid?
      end
    end

    INVALID_PROFILE_URLS.each do |url|
      test "rejects invalid Instagram profile #{url}" do
        refute_predicate create(:social_account_instagram, url:), :valid?
      end
    end
  end

  context "#format_account_name" do
    test "trims the protocol and hostname" do
      url = "https://instagram.com/monalisa"
      assert_equal "monalisa", create(:social_account_instagram, url:).format_account_name
    end

    test "trims a www. subdomain" do
      url = "https://www.instagram.com/someone"
      assert_equal "someone", create(:social_account_instagram, url:).format_account_name
    end

    test "trims a trailing slash" do
      url = "https://instagram.com/monalisa/"
      assert_equal "monalisa", create(:social_account_instagram, url:).format_account_name
    end
  end
end
