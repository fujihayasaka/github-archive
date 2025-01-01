# typed: true
# frozen_string_literal: true

require "test_helper"

class FakeConfig
  include GitHub::Config
  include GitHub::Config::DependencyGraph
  include GitHub::Config::FirstPartyApps
  include GitHub::Config::ProximaSyncedThirdPartyApps
  include GitHub::Config::MultiTenantEnterprise
  include GitHub::Config::S3
  include GitHub::Config::Metadata
  include GitHub::Config::Smtp
  include GitHub::Version
end

class GitHubConfigModelTest < GitHub::TestCase
  include EnvironmentTestHelper

  setup do
    @config = FakeConfig.new

    if GitHub.instance_variable_defined? :@gravatar_url
      GitHub.send :remove_instance_variable, :@gravatar_url
    end
  end

  context "gravatar_url" do
    test "defaults to 0 as subdomain" do
      assert_equal "https://0.gravatar.com", GitHub.gravatar_url
    end

    test "can set a different subdomain from the string passed" do
      assert_equal "https://0.gravatar.com", GitHub.gravatar_url("test@example.com")
    end

    test "returns correct value when set explicitly" do
      GitHub.gravatar_url = "http://fake-gravatar.example.com"
      assert_equal "http://fake-gravatar.example.com", GitHub.gravatar_url
    end
  end

  test "url_origin parses out the scheme, host, and port (if explicitly provided)" do
    assert_equal "http://foo.com", GitHub.url_origin("http://foo.com/abc")
    assert_equal "http://foo.com:8000", GitHub.url_origin("http://foo.com:8000")
    assert_equal "https://foo.com", GitHub.url_origin("https://foo.com")
  end
end
