# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesFollowVsoRedirects < GitHub::TestCase
  class FakeApp
    def call(env); end
  end

  fixtures do
    @from_url = "http://example.com"
    @middleware = Codespaces::FollowVsoRedirects.new(FakeApp.new, {}).freeze
  end

  test "it rejects redirects with our domain in a query param" do
    @to_url = "http://evil-example.net/?x=#{Codespaces::FollowVsoRedirects::ALLOWED_REDIRECT_ORIGIN}"
    refute @middleware.redirect_to_same_host?(@from_url, @to_url)
  end

  test "it rejects redirects with our domain as a subdomain" do
    @to_url = "http://#{Codespaces::FollowVsoRedirects::ALLOWED_REDIRECT_ORIGIN}.evil-example.net"
    refute @middleware.redirect_to_same_host?(@from_url, @to_url)
  end

  test "it rejects redirects with our domain appended to another domain" do
    @to_url = "http://evil-example#{Codespaces::FollowVsoRedirects::ALLOWED_REDIRECT_ORIGIN}"
    refute @middleware.redirect_to_same_host?(@from_url, @to_url)
  end

  test "it allows redirects to 'visualstudio.com'" do
    @to_url = "http://#{Codespaces::FollowVsoRedirects::ALLOWED_REDIRECT_ORIGIN}"
    assert @middleware.redirect_to_same_host?(@from_url, @to_url)
  end

  test "it allows redirects to subdomains of 'visualstudio.com'" do
    @to_url = "http://foo.#{Codespaces::FollowVsoRedirects::ALLOWED_REDIRECT_ORIGIN}"
    assert @middleware.redirect_to_same_host?(@from_url, @to_url)
  end

  test "it allows redirects to the same host" do
    assert @middleware.redirect_to_same_host?(@from_url, @from_url)
  end

  test "it allows redirects to subdomains of the original host" do
    @to_url = "http://foo.example.com"
    assert @middleware.redirect_to_same_host?(@from_url, @to_url)
  end
end
