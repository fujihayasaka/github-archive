# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  module Filters
    class SecurityConfigurationTest < GitHub::TestCase
      include SecurityProductsEnablement::EnterpriseTestHelpers

      setup do
        @business = create(:global_business)
        @org = create(:organization, business: @business)

        @repo1 = create(:repository, owner: @org)
        @repo2 = create(:private_repository, owner: @org)
        @repo3 = create(:internal_repository, owner: @org)
        @repo4 = create(:repository, owner: @org)
        @repo5 = create(:private_repository, owner: @org)
        @repo_without_config = create(:repository, owner: @org)

        @config1 = create(:security_configuration, target: @org)
        @config2 = create(:security_configuration, target: @org)
        @config3 = create(:security_configuration, target: @org)
        @config4 = create(:security_configuration, :enforced, target: @org)

        # There is no GitHub recommended configuration in GHES
        @gh_config = GitHub.enterprise? ? create(:security_configuration, target: @org) : ::SecurityConfiguration.github_recommended_configuration

        create(:repository_security_configuration, repository: @repo1, security_configuration: @config1, state: :attached)
        @repo_config2 = create(:repository_security_configuration, repository: @repo2, security_configuration: @config2, state: :removed)
        @repo_config3 = create(:repository_security_configuration, repository: @repo3, security_configuration: @config3, state: :failed)
        @repo_config4 = create(:repository_security_configuration, repository: @repo4, security_configuration: @gh_config, state: :removed)
        create(:repository_security_configuration, repository: @repo5, security_configuration: @config4, state: :enforced)

        # Set up another org
        other_org = create(:organization, business: create(:global_business))
        other_repo1 = create(:repository, owner: other_org)
        other_repo2 = create(:repository, owner: other_org)

        @other_config = create(:security_configuration, target: other_org)
        create(:repository_security_configuration, repository: other_repo1, security_configuration: @other_config, state: :attached)
        create(:repository_security_configuration, repository: other_repo2, security_configuration: @gh_config, state: :attached)
      end

      context "#apply" do
        test "returns an empty array when no filter is supported by the class" do
          filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
            @org, @org.admin, { "team" => ["github/code-names"] }
          )
          assert_empty filter.apply
        end

        context "filtering by configuration name" do
          test "returns repo IDs that match a configuration name" do
            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "configuration" => [@config1.name] }
            )
            assert_equal [@repo1.id], filter.apply

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "configuration" => [@gh_config.name] }
            )
            assert_equal [@repo4.id], filter.apply

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "configuration" => [@config1.name, @config2.name, @gh_config.name] }
            )
            assert_same_elements [@repo1.id, @repo2.id, @repo4.id], filter.apply
          end

          test "returns repo IDs of repos that are attached to an enterprise security configuration" do
            enterprise_security_configuration = create(:security_configuration, target: @business)

            repo6 = create(:private_repository, owner: @org)
            repo7 = create(:private_repository, owner: @org)

            create(:repository_security_configuration, repository: repo6, security_configuration: enterprise_security_configuration, state: :attached)
            create(:repository_security_configuration, repository: repo7, security_configuration: enterprise_security_configuration, state: :attached)

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "configuration" => [enterprise_security_configuration.name] }
            )
            assert_equal [repo6.id, repo7.id], filter.apply

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "configuration" => [enterprise_security_configuration.name, @config4.name] }
            )
            assert_same_elements [@repo5.id, repo6.id, repo7.id], filter.apply
          end

          test "returns an empty array when no repos match the configuration name" do
            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "configuration" => ["not real", "non-existent"] }
            )
            assert_empty filter.apply
          end

          test "accounts for typos when filtering by GitHub recommended config", skip_enterprise: true do
            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "configuration" => ["github Recommended"] }
            )
            assert_equal [@repo4.id], filter.apply
          end

          test "returns repo IDs that match the negated configuration names" do
            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "-configuration" => [@config1.name] }
            )
            assert_same_elements [@repo2.id, @repo3.id, @repo4.id, @repo5.id], filter.apply
          end

          test "returns only repo IDs that have a configuration status" do
            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "-configuration" => ["None"] }
            )
            assert_same_elements [@repo1.id, @repo2.id, @repo3.id, @repo4.id, @repo5.id], filter.apply
          end

          test "returns repo IDs that match the negated config names and have a configuration status" do
            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "-configuration" => [@config1.name, "None"] }
            )
            assert_same_elements [@repo2.id, @repo3.id, @repo4.id, @repo5.id], filter.apply
          end
        end

        context "when filtering for repos that do not have a configuration" do
          test "return repo IDs that do not have a configuration" do
            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "configuration" => [SecurityProductsEnablement::Filters::SecurityConfiguration::NO_CONFIG_KEYWORD] }
            )
            assert_equal [@repo2.id, @repo3.id, @repo4.id, @repo_without_config.id], filter.apply
          end

          test "return repo IDs that match a config name or do not have a configuration" do
            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "configuration" => [@config1.name, @gh_config.name, SecurityProductsEnablement::Filters::SecurityConfiguration::NO_CONFIG_KEYWORD] }
            )
            assert_same_elements [@repo1.id, @repo2.id, @repo3.id, @repo4.id, @repo_without_config.id], filter.apply
          end

          test "return an empty array when filtering for repos that match a config status and do not have any config" do
            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "configuration" => [SecurityProductsEnablement::Filters::SecurityConfiguration::NO_CONFIG_KEYWORD], "config-status" => ["attached"] }
            )
            assert_empty filter.apply
          end

          test "return repo IDs that match a config name or do not have a config, and match a config status" do
            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org,
              @org.admin,
              {
                "configuration" => [@config1.name, @gh_config.name, SecurityProductsEnablement::Filters::SecurityConfiguration::NO_CONFIG_KEYWORD],
                "config-status" => %w(attached removed)
              }
            )
            assert_same_elements [@repo1.id, @repo4.id], filter.apply
          end
        end

        test "returns only repo IDs that belong to the current org" do
          filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
            @org, @org.admin, { "configuration" => [@config1.name, @other_config.name, @gh_config.name] }
          )
          assert_same_elements [@repo1.id, @repo4.id], filter.apply
        end

        context "when filtering by configuration status" do
          test "returns repo IDs that match a configuration status" do
            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "config-status" => %w(attached failed) }
            )
            assert_equal [@repo1.id, @repo3.id, @repo5.id], filter.apply

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "config-status" => %w(enforced failed) }
            )
            assert_equal [@repo3.id, @repo5.id], filter.apply
          end

          test "returns repo IDs that match a configuration status and a configuration name" do
            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin,
              {
                "configuration" => [@config1.name, @config2.name, @gh_config.name],
                "config-status" => %w(removed)
              }
            )
            assert_same_elements [@repo2.id, @repo4.id], filter.apply
          end

          test "returns repo IDs that match the negated configuration status" do
            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "-config-status" => %w(failed) }
            )
            assert_same_elements [@repo1.id, @repo2.id, @repo4.id, @repo5.id], filter.apply
          end

          test "includes repo IDs that are enforced when filtering for repos that are attached" do
            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "config-status" => %w(attached) }
            )
            assert_equal [@repo1.id, @repo5.id], filter.apply

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "-config-status" => %w(attached) }
            )
            assert_same_elements [@repo2.id, @repo3.id, @repo4.id], filter.apply
          end
        end

        context "filtering by failure reason" do
          test "returns an empty array when no repos match the failure reason" do
            assert_same_elements [nil], RepositorySecurityConfiguration.distinct.pluck(:failure_reason)

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "failure-reason" => ["not_enough_licenses"] }
            )
            assert_empty filter.apply
          end

          test "returns repos that match unknown (nil) failure reasons" do
            assert_same_elements [nil], RepositorySecurityConfiguration.distinct.pluck(:failure_reason)

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "failure-reason" => ["unknown"] }
            )
            assert_equal [@repo3.id], filter.apply
          end

          test "returns repos that match unknown (internal) failure reasons" do
            reason = "actor_not_found"
            @repo_config3.update_attribute(:failure_reason, reason)
            assert_same_elements [reason, nil], RepositorySecurityConfiguration.distinct.pluck(:failure_reason)

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "failure-reason" => ["unknown"] }
            )
            assert_equal [@repo3.id], filter.apply
          end

          test "returns repos that match action_disabled failure reasons" do
            reason = "Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is disabled on this repository, please enable it."
            @repo_config3.update_attribute(:failure_reason, reason)
            assert_same_elements [reason, nil], RepositorySecurityConfiguration.distinct.pluck(:failure_reason)

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "failure-reason" => ["actions_disabled"] }
            )
            assert_equal [@repo_config3.repository_id], filter.apply
          end

          test "returns repos that match code_scanning failure reasons" do
            reason = "Code scanning default setup can only be enabled if no manual workflow is configured."
            @repo_config3.update_attribute(:failure_reason, reason)
            assert_same_elements [reason, nil], RepositorySecurityConfiguration.distinct.pluck(:failure_reason)

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "failure-reason" => ["code_scanning"] }
            )
            assert_equal [@repo_config3.repository_id], filter.apply
          end

          test "returns repos that match enterprise_policy failure reasons" do
            reason = "Enabling advanced security is restricted by a policy."
            @repo_config3.update_attribute(:failure_reason, reason)
            assert_same_elements [reason, nil], RepositorySecurityConfiguration.distinct.pluck(:failure_reason)

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "failure-reason" => ["enterprise_policy"] }
            )
            assert_equal [@repo_config3.repository_id], filter.apply
          end

          test "returns repos that match license failure reasons" do
            reason = "Advanced security has not been purchased."
            @repo_config3.update_attribute(:failure_reason, reason)
            assert_same_elements [reason, nil], RepositorySecurityConfiguration.distinct.pluck(:failure_reason)

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "failure-reason" => ["not_purchased"] }
            )
            assert_equal [@repo_config3.repository_id], filter.apply
          end

          test "negating values returns unknown failure reasons" do
            # Add a config we'd like to *not* include in our results:
            @repo_config2.update(state: :failed, failure_reason: "Enabling advanced security is restricted by a policy.")

            # Ensure we have one unknown failure reason:
            assert_equal "failed", @repo_config3.state
            assert_nil @repo_config3.failure_reason

            # And a config we'd like to include in our results with a known failure_reason:
            @repo_config4.update(state: :failed, failure_reason: "Advanced security has not been purchased.")

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "-failure-reason" => ["enterprise_policy"] }
            )
            assert_same_elements [@repo_config3.repository_id, @repo_config4.repository_id], filter.apply
          end

          test "negating unknown failures returns failures with reasons" do
            # Add a config we'd like to *not* include in our results:
            @repo_config2.update(state: :failed, failure_reason: "Enabling advanced security is restricted by a policy.")

            # Ensure we have one unknown failure reason:
            assert_equal "failed", @repo_config3.state
            assert_nil @repo_config3.failure_reason

            # And a config we'd like to include in our results with a known failure_reason:
            @repo_config4.update(state: :failed, failure_reason: "Advanced security has not been purchased.")

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "-failure-reason" => ["unknown"] }
            )
            assert_same_elements [@repo_config2.repository_id, @repo_config4.repository_id], filter.apply
          end

          test "supports multiple failure reasons" do
            @repo_config2.update(state: :failed, failure_reason: "Advanced security has not been purchased.")
            @repo_config3.update(failure_reason: "Enabling advanced security is restricted by a policy.")

            filter = SecurityProductsEnablement::Filters::SecurityConfiguration.new(
              @org, @org.admin, { "failure-reason" => %w(not_purchased enterprise_policy) }
            )
            assert_same_elements [@repo_config2.repository_id, @repo_config3.repository_id], filter.apply
          end
        end
      end
    end
  end
end
