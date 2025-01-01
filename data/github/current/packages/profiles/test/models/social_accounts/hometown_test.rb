# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountsHometownTest < GitHub::TestCase
  VALID_PROFILE_URLS = %w(
    https://digipres.club/@monalisa
    http://arbitrary.lol/@monalisa
  )

  INVALID_PROFILE_URLS = %w(
    https://facebook.com/nope
    https://digipres.club/no-at-sign
    https://digipres.club/@extra/path/sections
    https://digipres.club/@extra?query=string
  )

  context "valid?" do
    VALID_PROFILE_URLS.each do |url|
      test "recognizes valid Hometown profile #{url}" do
        assert_predicate create(:social_account_hometown, url:), :valid?
      end
    end

    INVALID_PROFILE_URLS.each do |url|
      test "rejects invalid Hometown profile #{url}" do
        refute_predicate create(:social_account_hometown, url:), :valid?
      end
    end
  end

  test "formats an account name as @user@host" do
    url = "https://digipres.club/@monalisa"
    assert_equal "@monalisa@digipres.club", create(:social_account_hometown, url:).format_account_name
  end
end
