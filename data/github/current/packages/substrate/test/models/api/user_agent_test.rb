# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiUserAgentTest < GitHub::TestCase

  test "handles garbage user agent strings" do
    [nil, "", "THX1138"].each do |garbage|
      ua = Api::UserAgent.new(garbage)

      refute ua.github_desktop?
      refute ua.cli?
      refute ua.browser?
    end
  end

  test "detects GitHub desktop clients" do
    ua = Api::UserAgent.new \
      "Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36"
    refute ua.github_desktop?
  end

  test "detects GitHub Issues version" do
    ua = Api::UserAgent.new \
      "GitHubIssues/0.93"
    assert ua.github_issues?
    refute ua.github_desktop?

    assert_equal 0, ua.github_app_version.major
    assert_equal 93, ua.github_app_version.minor
  end

  test "detects GitHub Android version" do
    ua = Api::UserAgent.new \
      "GitHubAndroid/1.9"
    assert ua.github_android?
    refute ua.github_desktop?

    assert_equal 1, ua.github_app_version.major
    assert_equal 9, ua.github_app_version.minor
  end

  test "detects GitHub VisualStudio version" do
    ua = Api::UserAgent.new \
      "GitHubVisualStudio/1.0.5.3 (Win32NT 6.3.9600; amd64; sv-SE; Octokit 0.10.0)"
    assert ua.github_visual_studio?
    refute ua.github_desktop?

    assert_equal 1, ua.github_app_version.major
    assert_equal 0, ua.github_app_version.minor
    assert_equal 5, ua.github_app_version.patch
  end

  test "detects cli agents" do
    ua = Api::UserAgent.new("curl/7.37.1")
    assert ua.cli?
    refute ua.browser?
    refute ua.github_desktop?
  end

  test "detects browser agents" do
    ua = Api::UserAgent.new \
      "Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36"
    assert ua.browser?
    refute ua.github_desktop?
    refute ua.cli?
  end

  test "detects GitHub Desktop clients" do
    ua = Api::UserAgent.new \
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_5) AppleWebKit/537.36 (KHTML, like Gecko) GitHubDesktop/0.5.8 Chrome/56.0.2924.87 Electron/1.6.7 Safari/537.36"
    assert ua.github_desktop?
  end

  test "detects the correct platform" do
    ua = Api::UserAgent.new \
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_5) AppleWebKit/537.36 (KHTML, like Gecko) GitHubDesktop/0.5.8 Chrome/56.0.2924.87 Electron/1.6.7 Safari/537.36"
    assert ua.running_mac_platform?

    ua = Api::UserAgent.new \
      "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) GitHubDesktop/0.5.8 Chrome/56.0.2924.87 Electron/1.6.7 Safari/537.36"
    assert ua.running_windows_platform?

    ua = Api::UserAgent.new \
      "Mozilla/5.0 (X11; CrOS x86_64) AppleWebKit/537.36 (KHTML, like Gecko) GitHubDesktop/0.5.8 Chrome/56.0.2924.87 Electron/1.6.7 Safari/537.36"
    refute ua.running_mac_platform?
    refute ua.running_windows_platform?
  end

  test "detects group-syncer" do
    ua = Api::UserAgent.new("group-syncer/255b323")
    assert ua.group_syncer?
  end
end
