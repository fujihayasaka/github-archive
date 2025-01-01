# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats
  class RateLimitTest < GitHub::TestCase
    fixtures do
      @owner = create(:user)
      @org = create(:business_plus_organization, admin: @owner)
      @integration  = create(:integration, :with_marketplace_listing)
      @installation = create(:integration_installation, integration: @integration, target: @org)
      @oauth = create :oauth_application
      @oauth_access = create(:oauth_access, application: @oauth, user: @owner)
    end

    test "for_installation returns correct rate limit for GHEC installations" do
      rate_limit = RateLimit.new("core").for_installation(@installation)
      assert_equal GitHub::Config::RateLimits::API_ENTERPRISE_CLOUD_SOFT_RATE_LIMIT, rate_limit
    end

    test "for_installation returns correct rate limit for installation with overridden limit" do
      expected_rate_limit = 50_000

      another_integration  = create(:integration, :with_marketplace_listing)

      overridden_limit_installation = T.must(T.let(create(:integration_installation, integration: another_integration, target: @org), IntegrationInstallation))
      overridden_limit_installation.rate_limit = expected_rate_limit
      overridden_limit_installation.save!

      rate_limit = RateLimit.new("core").for_installation(overridden_limit_installation)
      assert_equal expected_rate_limit, rate_limit
    end

    test "for_oauth_application returns correct rate limit" do
      rate_limit = RateLimit.new("core").for_oauth_application(@oauth_access)
      assert_equal GitHub.api_default_rate_limit, rate_limit
    end

    test "for_oauth_application returns correct rate limit for installation with overridden limit" do
      expected_rate_limit = 50_000

      another_oauth_application = T.must(T.let(create(:oauth_application), OauthApplication))
      another_oauth_application.rate_limit = expected_rate_limit
      another_oauth_application.save!

      another_oauth_access = create(:oauth_access, application: another_oauth_application, user: @owner)

      rate_limit = RateLimit.new("core").for_oauth_application(another_oauth_access)
      assert_equal expected_rate_limit, rate_limit
    end

    test "for_integration returns correct rate limit" do
      rate_limit = RateLimit.new("core").for_integration(@integration)
      assert_equal GitHub.api_default_rate_limit, rate_limit
    end

    test "for_integration returns correct rate limit for business+ owner" do
      business_plus_org = create(:business_plus_organization, admin: @owner)
      integration = create(:integration, :with_marketplace_listing, owner: business_plus_org)

      rate_limit = RateLimit.new("core").for_integration(integration)
      assert_equal GitHub.api_enterprise_cloud_soft_rate_limit, rate_limit
    end
  end
end
