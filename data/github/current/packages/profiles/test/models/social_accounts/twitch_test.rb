# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountsTwitchTest < GitHub::TestCase
  VALID_PROFILE_URLS = %w(
    https://twitch.tv/monalisa
    https://twitch.tv/trailingslash_123/
    https://www.twitch.tv/dubdubdub
  )

  INVALID_PROFILE_URLS = %w(
    https://example.com
    http://twitch.tv/insecure
    https://twitch.tv/
    https://www.twitch.tv/extra/path/sections
    https://www.twitch.tv/extra?query=string
  )

  context "valid?" do
    VALID_PROFILE_URLS.each do |url|
      test "recognizes valid Twitch profile #{url}" do
        assert_predicate create(:social_account_twitch, url: "https://twitch.tv/monalisa"), :valid?
      end
    end

    INVALID_PROFILE_URLS.each do |url|
      test "rejects invalid Twitch profile #{url}" do
        refute_predicate create(:social_account_twitch, url:), :valid?
      end
    end
  end

  context "#format_account_name" do
    test "removes the protocol and hostname" do
      url = "https://twitch.tv/monalisa"
      assert_equal "monalisa", create(:social_account_twitch, url: url).format_account_name
    end

    test "removes a www. subdomain" do
      url = "https://www.twitch.tv/monalisa"
      assert_equal "monalisa", create(:social_account_twitch, url: url).format_account_name
    end

    test "removes a trailing slash" do
      url = "https://twitch.tv/monalisa/"
      assert_equal "monalisa", create(:social_account_twitch, url: url).format_account_name
    end
  end
end
