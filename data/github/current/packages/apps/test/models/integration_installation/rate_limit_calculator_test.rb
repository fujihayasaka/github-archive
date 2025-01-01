# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationInstallationRateLimitCalculatorTest < GitHub::TestCase
  fixtures do
    @org  = create(:organization)
    @repo = create(:repository, :minimal, owner: @org)

    @default_rate_limit = GitHub.api_default_rate_limit
    @rate_limit_cap     = GitHub.api_tier_one_rate_limit

    @organization_member_count_threshold     = IntegrationInstallation::RateLimitCalculator::ORGANIZATION_MEMBER_COUNT_THRESHOLD
    @organization_member_rate_limit_addition = IntegrationInstallation::RateLimitCalculator::ORGANIZATION_MEMBER_RATE_LIMIT_ADDITION

    @repository_count_threshold     = IntegrationInstallation::RateLimitCalculator::REPOSITORY_COUNT_THRESHOLD
    @repository_rate_limit_addition = IntegrationInstallation::RateLimitCalculator::REPOSITORY_RATE_LIMIT_ADDITION
  end

  test "has a base rate limit" do
    installation = make_integration_installation(target: @org)
    assert_equal @default_rate_limit, IntegrationInstallation::RateLimitCalculator.calculate(installation)
  end

  test "returns a maximum rate limit, regardless of a higher calculation" do
    installation = make_integration_installation(target: @org)
    # Without the limit this would raise the rate limit to 65,000
    Organization.any_instance.stubs(:members_count).returns(250)
    assert_equal @rate_limit_cap, IntegrationInstallation::RateLimitCalculator.calculate(installation)
  end

  context "#calculate" do
    test "business installations do not get a special rate limit" do
      installation = make_integration_installation(target: create(:business), permissions: { Business::Resources.subject_types.first => "read" })
      assert_equal @default_rate_limit, IntegrationInstallation::RateLimitCalculator.calculate(installation)
    end

    # https://github.com/github/ecosystem-apps/issues/1814
    test "does not recalculate the rate limit for Apps that have been deleted" do
      installation = make_integration_installation(target: @org)
      installation.integration.delete
      installation.reload
      assert_nil installation.integration, "integration should have been deleted"

      assert_equal @default_rate_limit, IntegrationInstallation::RateLimitCalculator.calculate(installation)
    end

    context "rate limit based on the number of organization members" do
      test "having more than #{@organization_member_rate_limit_addition} members adds to the rate limit" do
        installation = make_integration_installation(target: @org)
        Organization.any_instance.stubs(:members_count).returns(@organization_member_count_threshold + 1)

        rate_limit = @default_rate_limit + @organization_member_rate_limit_addition
        assert_equal rate_limit, IntegrationInstallation::RateLimitCalculator.calculate(installation)
      end

      test "global apps always return the base limit" do
        integration = create_global_integration
        disable_feature_flag(:disabled_global_apps, integration)

        installation = make_integration_installation(integration: integration, target: @org)
        Organization.any_instance.stubs(:members_count).returns(@organization_member_count_threshold + 1)

        assert_equal @default_rate_limit, IntegrationInstallation::RateLimitCalculator.calculate(installation)
      end

      test "removing a member from the organization decreases the rate limit" do
        number_or_members = @organization_member_count_threshold + 1
        installation      = make_integration_installation(target: @org)

        enable_feature_flag(:installation_dynamic_rate_limiting, installation.integration)
        Organization.any_instance.stubs(:members_count).returns(number_or_members)

        installation.recalculate_rate_limit

        rate_limit = @default_rate_limit + @organization_member_rate_limit_addition
        assert_equal rate_limit, installation.reload.rate_limit

        Organization.any_instance.stubs(:members_count).returns(number_or_members - 1)

        installation.recalculate_rate_limit
        assert_equal @default_rate_limit, installation.reload.rate_limit
      end
    end

    context "rate limit based on the number of repositories" do
      test "having more than #{@repository_count_threshold} repos adds to the rate limit" do
        installation = make_integration_installation(target: @org, permissions: { "metadata" => "read" })
        assert_equal 1, installation.repositories.count
        IntegrationInstallation::RateLimitCalculator.stub_const(:REPOSITORY_COUNT_THRESHOLD, 0) do
          expected_rate_limit = @default_rate_limit + @repository_rate_limit_addition
          assert_equal expected_rate_limit, IntegrationInstallation::RateLimitCalculator.calculate(installation)
        end
      end

      test "global apps always return the base limit" do
        integration = create_global_integration
        disable_feature_flag(:disabled_global_apps, integration)

        installation = make_integration_installation(integration: integration, target: @org)
        installation.stubs(:repository_ids).returns((1..(@repository_count_threshold + 1)).to_a)

        assert_equal @default_rate_limit, IntegrationInstallation::RateLimitCalculator.calculate(installation)
      end

      test "global apps with rate limit override" do
        integration = create_unlimited_global_integration(capabilities: { global_app_overrides_rate_limit: true })
        disable_feature_flag(:disabled_global_apps, integration)

        installation = make_site_scoped_integration_installation(
          integration: integration, target: @org, repositories: [@repo],
        )

        assert_equal 1, installation.repositories.count
        IntegrationInstallation::RateLimitCalculator.stub_const(:REPOSITORY_COUNT_THRESHOLD, 0) do
          expected_rate_limit = @default_rate_limit + @repository_rate_limit_addition
          assert_equal expected_rate_limit, IntegrationInstallation::RateLimitCalculator.calculate(installation)
        end
      end

      test "removing a repository decreases the rate limit" do
        installation = make_integration_installation(target: @org, permissions: { "metadata" => "read" })
        enable_feature_flag(:installation_dynamic_rate_limiting, installation.integration)

        assert_equal 1, installation.repositories.count
        IntegrationInstallation::RateLimitCalculator.stub_const(:REPOSITORY_COUNT_THRESHOLD, 0) do
          expected_rate_limit = @default_rate_limit + @repository_rate_limit_addition
          installation.recalculate_rate_limit
          assert_equal expected_rate_limit, installation.reload.rate_limit

          @repo.destroy!

          installation.recalculate_rate_limit
          assert_equal @default_rate_limit, installation.reload.rate_limit
        end
      end
    end
  end
end
