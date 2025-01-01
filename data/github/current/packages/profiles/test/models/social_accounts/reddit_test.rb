# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountsRedditTest < GitHub::TestCase
  VALID_PROFILE_URLS = %w(
    https://reddit.com/user/monalisa
    https://www.reddit.com/user/monalisa
    https://reddit.com/u/monalisa
    https://reddit.com/u/trailing-slash-100/
  )

  INVALID_PROFILE_URLS = %w(
    https://monalisa.livejournal.com
    http://reddit.com/u/insecure
    https://reddit.com/user/
  )

  context "valid?" do
    VALID_PROFILE_URLS.each do |url|
      test "recognizes valid Reddit URL #{url}" do
        assert_predicate create(:social_account_reddit, url:), :valid?
      end
    end

    INVALID_PROFILE_URLS.each do |url|
      test "rejects invalid Reddit profile #{url}" do
        refute_predicate create(:social_account_reddit, url:), :valid?
      end
    end
  end

  context "#format_account_name" do
    test "uses the u/account form" do
      account = create(:social_account_reddit, url: "https://reddit.com/user/monalisa")
      assert_equal "u/monalisa", account.format_account_name
    end
  end
end
