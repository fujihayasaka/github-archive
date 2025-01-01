# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountsBlueskyTest < GitHub::TestCase
  VALID_PROFILE_URLS = %w(
    https://bsky.app/profile/github.com
    https://bsky.app/profile/mona.net
    https://bsky.app/profile/mona.bsky.social
    https://bsky.app/profile/trailing-slash.com/
  )

  INVALID_PROFILE_URLS = %w(
    https://bsky.app/github.com
    https://bsky.app/profile/@mona.net
  )

  context "valid?" do
    VALID_PROFILE_URLS.each do |url|
      test "recognizes valid Bluesky profile #{url}" do
        assert_predicate create(:social_account_bluesky, url:), :valid?
      end
    end

    INVALID_PROFILE_URLS.each do |url|
      test "rejects invalid Bluesky profile #{url}" do
        refute_predicate create(:social_account_bluesky, url:), :valid?
      end
    end
  end

  test "formats an account name as @user" do
    url = "https://bsky.app/profile/monalisa.com"
    assert_equal "@monalisa.com", create(:social_account_bluesky, url:).format_account_name
  end
end
