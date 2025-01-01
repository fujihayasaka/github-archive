# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountsMastodonTest < GitHub::TestCase
  VALID_PROFILE_URLS = %w(
    https://mastodon.social/@monalisa
    http://arbitrary.lol/@monalisa
  )

  INVALID_PROFILE_URLS = %w(
    https://facebook.com/nope
    https://mastodon.social/no-at-sign
    https://mastodon.social/@extra/path/sections
    https://mastodon.social/@extra?query=string
  )

  context "valid?" do
    VALID_PROFILE_URLS.each do |url|
      test "recognizes valid Mastodon profile #{url}" do
        assert_predicate create(:social_account_mastodon, url:), :valid?
      end
    end

    INVALID_PROFILE_URLS.each do |url|
      test "rejects invalid Mastodon profile #{url}" do
        refute_predicate create(:social_account_mastodon, url:), :valid?
      end
    end
  end

  test "formats an account name as @user@host" do
    url = "https://hackyderm.io/@monalisa"
    assert_equal "@monalisa@hackyderm.io", create(:social_account_mastodon, url:).format_account_name
  end
end
