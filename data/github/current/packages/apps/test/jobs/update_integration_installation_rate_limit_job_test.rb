# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class UpdateIntegrationInstallationRateLimitJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @integration  = create(:integration, default_permissions: { "metadata" => :read })
    @org          = create(:organization)
    @installation = make_integration_installation(integration: @integration, target: @org)

    @default_rate_limit                      = GitHub.api_default_rate_limit
    @organization_member_rate_limit_addition = IntegrationInstallation::RateLimitCalculator::ORGANIZATION_MEMBER_RATE_LIMIT_ADDITION
    @organization_member_count_threshold     = IntegrationInstallation::RateLimitCalculator::ORGANIZATION_MEMBER_COUNT_THRESHOLD
  end

  test "updates an installations rate limit" do
    assert_equal @default_rate_limit, @installation.rate_limit

    Organization.any_instance.stubs(:members_count).returns(@organization_member_count_threshold + 1)

    UpdateIntegrationInstallationRateLimitJob.perform_now(@installation.id)

    rate_limit = @default_rate_limit + @organization_member_rate_limit_addition
    assert_equal rate_limit, @installation.reload.rate_limit
  end

  test "does not raise when target is missing" do
    @org.delete # Simulate a recent target deletion

    assert_nothing_raised do
      UpdateIntegrationInstallationRateLimitJob.perform_now(@installation.id)
    end
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: UpdateIntegrationInstallationRateLimitJob, args: [@installation.id]
  end
end
