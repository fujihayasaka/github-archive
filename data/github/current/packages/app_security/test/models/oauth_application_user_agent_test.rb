# typed: true
# frozen_string_literal: true

require "test_helper"

class OauthApplicationUserAgentTest < GitHub::TestCase
  test "detects outdated GitHub Desktop" do
    matching_app = OauthApplicationUserAgent.from_user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) GitHubDesktop/2.5.2 Chrome/78.0.3904.130 Electron/7.1.8 Safari/537.36")
    assert matching_app, "expected user agent string to detect GitHub Desktop"
    assert_predicate matching_app, :outdated?
  end

  test "GitHub Desktop does not affect current sessions" do
    matching_app = OauthApplicationUserAgent.from_user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) GitHubDesktop/2.5.2 Chrome/78.0.3904.130 Electron/7.1.8 Safari/537.36")
    refute matching_app.current_sessions_affected, "GitHub Desktop does not require an upgrade to continue functioning for existing sessions"
  end
end
