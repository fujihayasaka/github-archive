# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountsYouTubeTest < GitHub::TestCase
  VALID_PROFILE_URLS = %w(
    https://youtube.com/user/legacy
    https://youtube.com/c/oldcanonicalform
    https://youtube.com/channel/UCW1Sql-M7QTRH7fQ8vU1ZSQ
    https://youtube.com/@GitHub
    https://youtube.com/@TrailingSlash/
    https://www.youtube.com/@Whatever
  )

  INVALID_PROFILE_URLS = %w(
    https://example.com/
    http://youtube.com/@Insecure
    https://youtube.com/@Extra/Path/Sections
    https://www.youtube.com/@Extra?Query=String
  )

  context "valid?" do
    VALID_PROFILE_URLS.each do |url|
      test "recognizes valid YouTube URL #{url}" do
        assert_predicate create(:social_account_youtube, url:), :valid?
      end
    end

    INVALID_PROFILE_URLS.each do |url|
      test "rejects invalid YouTube URL #{url}" do
        refute_predicate create(:social_account_youtube, url:), :valid?
      end
    end
  end

  context "#format_account_name" do
    test "trims the protocol and hostname" do
      url = "https://youtube.com/c/monalisa"
      assert_equal "c/monalisa", create(:social_account_youtube, url: url).format_account_name
    end

    test "trims a www. subdomain" do
      url = "https://www.youtube.com/@monalisa"
      assert_equal "@monalisa", create(:social_account_youtube, url: url).format_account_name
    end

    test "trims a trailing slash" do
      url = "https://youtube.com/user/legacy/"
      assert_equal "user/legacy", create(:social_account_youtube, url: url).format_account_name
    end
  end
end
