# typed: true
# frozen_string_literal: true

require "test_helper"

class Organizations::Settings::SecurityConfiguration::RepositoriesControllerTest < GitHub::IntegrationTestCase
  include SecurityProductsEnablement::EnterpriseTestHelpers
  include TurboghasHelpers
  include AuditLog::IntegrationTestHelpers
  include SecurityProductsEnablementHelpers
  include HydroMessageJobTestHelpers

  EVENTS = %w[
    repository_security_configuration.applied
    repository_security_configuration.removed
  ]

  fixtures do
    @random_user = create(:user, name: "random-user")
    @owner = create(:user, name: "org-owner")
    @org = create(:organization, admin: @owner)
    @member = create(:user, name: "org-member")
    @org.add_member(@member)
    @security_manager = create(:user, name: "org-security-manager")
    @org.add_member(@security_manager)
    @security_manager_team = create(:security_manager_team, organization: @org)
    @security_manager_team.add_member(@security_manager)
  end

  setup do
    @configuration = create(:security_configuration, target: @org)
  end

  context "#update" do
    test "allows security manager to apply configs" do
      as @security_manager
      put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{@configuration.id}/repositories"

      assert_response :created
    end

    test "renders 404 for users who are not a memeber of the organization" do
      as @random_user
      put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{@configuration.id}/repositories"

      assert_response :not_found
    end

    test "renders 404 for org members who don't have access" do
      as @member
      put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{@configuration.id}/repositories"

      assert_response :not_found
    end

    test "returns 422 if security configurations are being applied on the org" do
      # Pretend configurations are being applied to the org:
      job_progress_tracker = SecurityProductsEnablement::JobProgressTracker.new(@org.id)
      job_progress_tracker.start

      as @owner
      put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{@configuration.id}/repositories"

      assert_response :unprocessable_entity
    end

    test "returns 422 if BlockedSettings are active for the org" do
      # Pretend configurations are being blocked:
      job_status = JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :auto_codeql_enable_all) })

      as @owner
      put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{@configuration.id}/repositories"

      assert_response :unprocessable_entity
    end

    test "applies the configuration to a repository" do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

      repo = create(:private_repository, owner: @org)
      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
        code_scanning: :not_set,
        secret_scanning: :not_set,
        secret_scanning_push_protection: :not_set,
      )

      assert_changes("RepositorySecurityConfiguration.count", from: 0, to: 1) do
        perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
          as @owner
          put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{security_configuration.id}/repositories",
            params: { repository_ids: [repo.id] }, as: :json
          assert_response :created
        end
      end

      repo_config = RepositorySecurityConfiguration.find_by!(repository: repo)
      assert_equal "attached", repo_config.state
    end

    test "applies the recommended configuration to all public repositories without configuration in the organization", skip_with_all_emus: true, skip_enterprise: true do
      repo_ids = []
      10.times do
        repo = create(:repository, owner: @org)
        repo_ids << repo.id
      end
      security_configuration = SecurityConfiguration.github_recommended_configuration

      CodeScanning::AutoCodeql.any_instance.stubs(:enabled_with_options?).returns(true)

      assert_changes("RepositorySecurityConfiguration.count", from: 0, to: 10) do
        perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
          as @owner
          put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{security_configuration&.id}/repositories",
            params: { repository_ids: [] }, as: :json

          assert_response :created
        end
      end

      assert_equal 10, RepositorySecurityConfiguration.where(security_configuration: security_configuration, repository_id: repo_ids).count
    end

    test "applies the free features of recommended config to all private repos without a config in the organization", skip_enterprise: true do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled_with_options?).returns(true)

      repo_ids = []
      10.times do
        repo = create(:private_repository, owner: @org)
        repo_ids << repo.id
      end
      security_configuration = SecurityConfiguration.github_recommended_configuration

      assert_changes("RepositorySecurityConfiguration.count", from: 0, to: 10) do
        perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
          as @owner
          put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{security_configuration&.id}/repositories",
            params: { repository_ids: [] }, as: :json

          assert_response :created
        end
      end

      # Enable free features and update the state to failed
      assert_equal 10, RepositorySecurityConfiguration.where(security_configuration:, repository_id: repo_ids, state: :attached).count
    end

    test "when applying the recommended configuration to a specific repo, it doesn't modify the existing recommended defaults", skip_with_all_emus: true, skip_enterprise: true do
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled_with_options?).returns(true)
      security_configuration = SecurityConfiguration.github_recommended_configuration
      repo = create(:repository, owner: @org)

      SecurityConfigurationDefault.create_or_update_defaults(target: @org, default_for_new_public_repos: true, default_for_new_private_repos: true, security_configuration: T.must(security_configuration))
      default = SecurityConfigurationDefault.for_target(@org).sole
      assert_equal security_configuration, default.security_configuration
      assert default.default_for_new_public_repos
      assert default.default_for_new_private_repos

      perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
        as @owner
        put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{security_configuration&.id}/repositories",
          params: { repository_ids: [repo.id] }, as: :json

        assert_response :created

        default = SecurityConfigurationDefault.for_target(@org).sole
        assert_equal security_configuration, default.security_configuration
        assert default.default_for_new_public_repos
        assert default.default_for_new_private_repos

        repo.reload
        assert_equal security_configuration, repo.repository_security_configuration.security_configuration
      end
    end

    test "applies recommended configuration to repositories that already have a configuration if override_existing_config is true", skip_enterprise: true do
      repo1 = create(:private_repository, owner: @org)
      repo2 = create(:private_repository, owner: @org)
      repo3 = create(:private_repository, owner: @org)

      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
      )

      repo1_config = RepositorySecurityConfiguration.create!(repository: repo1, organization: @org, security_configuration: security_configuration, state: :attached)
      repo2_config = RepositorySecurityConfiguration.create!(repository: repo2, organization: @org, security_configuration: security_configuration, state: :attached)
      repo3_config = RepositorySecurityConfiguration.create!(repository: repo3, organization: @org, security_configuration: security_configuration, state: :attached)

      github_recommended_configuration = SecurityConfiguration.github_recommended_configuration

      perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob]) do
        assert_no_changes(RepositorySecurityConfiguration.count) do
          as @owner
          put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{T.must(github_recommended_configuration).id}/repositories",
            params: { repository_ids: [], override_existing_config: true }, as: :json

          assert_response :created
        end
      end

      assert_enqueued_jobs(3, only: ApplySecurityConfigurationToRepositoryJob)
    end

    test "does not apply new configuration to repository if there is another configuration in attaching state" do
      repo = create(:private_repository, owner: @org)
      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
      )

      new_security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
        dependabot_security_updates: :enabled,
      )

      RepositorySecurityConfiguration.create!(repository: repo, organization: @org, security_configuration: security_configuration, state: :attaching)

      assert_no_changes(RepositorySecurityConfiguration.count) do
        perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
          as @owner
          put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{new_security_configuration.id}/repositories",
            params: { repository_ids: [repo.id] }, as: :json
        end
      end

      assert_response :created

      repo_config = RepositorySecurityConfiguration.find_by!(repository: repo)
      assert_equal "attaching", repo_config.state
      assert_equal security_configuration, repo_config.security_configuration
    end

    test "does not apply the recommended configuration to repositories that already have an attached configuration if override_existing_config is false", skip_enterprise: true do
      repo1 = create(:private_repository, owner: @org)
      repo2 = create(:private_repository, owner: @org)
      repo3 = create(:private_repository, owner: @org)

      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
      )

      repo1_config = RepositorySecurityConfiguration.create!(repository: repo1, organization: @org, security_configuration: security_configuration, state: :attached)
      repo2_config = RepositorySecurityConfiguration.create!(repository: repo2, organization: @org, security_configuration: security_configuration, state: :failed)
      repo3_config = RepositorySecurityConfiguration.create!(repository: repo3, organization: @org, security_configuration: security_configuration, state: :removed)

      github_recommended_configuration = SecurityConfiguration.github_recommended_configuration

      assert_no_changes(RepositorySecurityConfiguration.count) do
        perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob]) do
          as @owner
          put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{github_recommended_configuration&.id}/repositories",
            params: { repository_ids: [], override_existing_config: false }, as: :json
          assert_response :created
        end
      end

      assert_equal security_configuration, repo1_config.reload.security_configuration
      assert_nil RepositorySecurityConfiguration.find_by(id: repo2_config.id)
      assert_nil RepositorySecurityConfiguration.find_by(id: repo3_config.id)
      assert_enqueued_jobs 2, only: ApplySecurityConfigurationToRepositoryJob
    end

    test "applies recommended config and sets it as default config for new public repos when default options are passed", skip_with_all_emus: true, skip_enterprise: true do
      repo_ids = []
      10.times do
        repo = create(:repository, owner: @org)
        repo_ids << repo.id
      end
      security_configuration = SecurityConfiguration.github_recommended_configuration

      CodeScanning::AutoCodeql.any_instance.stubs(:enabled_with_options?).returns(true)

      assert_changes("RepositorySecurityConfiguration.count", from: 0, to: 10) do
        perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
          as @owner
          put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{security_configuration&.id}/repositories",
            params: {
              repository_ids: [],
              default_for_new_public_repos: true,
              default_for_new_private_repos: false
            }, as: :json

          assert_response :created
        end
      end

      assert_equal 10, RepositorySecurityConfiguration.where(security_configuration: security_configuration, repository_id: repo_ids).count
      assert_equal 1, SecurityConfigurationDefault.count

      default = SecurityConfigurationDefault.last
      assert_equal security_configuration, default&.security_configuration
      assert default&.default_for_new_public_repos
      refute default&.default_for_new_private_repos
    end

    test "applies recommended config and sets it as default config for new private repos when default options are passed", skip_enterprise: true do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled_with_options?).returns(true)

      repo_ids = []
      10.times do
        repo = create(:private_repository, owner: @org)
        repo_ids << repo.id
      end
      security_configuration = SecurityConfiguration.github_recommended_configuration

      assert_changes("RepositorySecurityConfiguration.count", from: 0, to: 10) do
        perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
          as @owner
          put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{security_configuration&.id}/repositories",
            params: {
              repository_ids: [],
              default_for_new_public_repos: true,
              default_for_new_private_repos: false
            }, as: :json

          assert_response :created
        end
      end

      assert_equal 10, RepositorySecurityConfiguration.where(security_configuration:, repository_id: repo_ids, state: :attached).count
      assert_equal 1, SecurityConfigurationDefault.count

      default = SecurityConfigurationDefault.last
      assert_equal security_configuration, default&.security_configuration
      assert default&.default_for_new_public_repos
      refute default&.default_for_new_private_repos
    end

    test "applies the configuration to a repository but will not set it as a default config if default options are not passed" do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

      repo = create(:private_repository, owner: @org)
      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
        code_scanning: :not_set,
        secret_scanning: :not_set,
        secret_scanning_push_protection: :not_set,
      )

      assert_changes("RepositorySecurityConfiguration.count", from: 0, to: 1) do
        perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
          as @owner
          put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{security_configuration.id}/repositories",
            params: { repository_ids: [repo.id] }, as: :json
          assert_response :created
        end
      end

      repo_config = RepositorySecurityConfiguration.find_by!(repository: repo)
      assert_equal "attached", repo_config.state

      assert_empty SecurityConfigurationDefault.all
    end

    test "applies GHAS enabled config to a private repository in non-GHAS org and update repository security configurations as failed" do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)

      repo = create(:private_repository, owner: @org)
      security_configuration = create(:security_configuration, target: @org, code_scanning: :not_set)

      assert_changes("RepositorySecurityConfiguration.count", from: 0, to: 1) do
        perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
          as @owner
          put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{security_configuration.id}/repositories",
            params: { repository_ids: [repo.id] }, as: :json
          assert_response :created
        end
      end

      assert_equal 1, RepositorySecurityConfiguration.where(security_configuration:, repository_id: [repo.id], state: :failed).count
      assert_empty SecurityConfigurationDefault.all
    end

    test "creates an audit log entry when applying a security configuration to a repository" do
      repo = create(:private_repository, owner: @org)
      security_configuration = create(:security_configuration, :non_ghas, target: @org)

      as @owner
      events = assert_performed_audit_entries(count: 1, only: "repository_security_configuration.applied") do
        assert_changes("RepositorySecurityConfiguration.count", from: 0, to: 1) do
          perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
            as @owner
            put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{security_configuration.id}/repositories",
              params: { repository_ids: [repo.id] }, as: :json
            assert_response :created
          end
        end
      end

      repository_security_configuration = RepositorySecurityConfiguration.find_by!(repository: repo)
      event = events.sole

      assert_equal "repository_security_configuration.applied", event[:action]
      assert_equal @owner.display_login, event[:actor]
      assert_equal @org.display_login, event[:org]
      assert_equal repository_security_configuration.state, event[:repository_security_configuration_state]
      assert_equal repository_security_configuration.repository_id, event[:repo_id]
      assert_equal repository_security_configuration.security_configuration_id, event[:security_configuration_id]
      assert_nil event[:security_configuration_failure_reason]
    end

    test "creates an audit log when a configuration is enforced for a repository" do
      repo = create(:private_repository, owner: @org)
      security_configuration = create(:security_configuration, :non_ghas, :enforced, target: @org)

      as @owner
      events = assert_performed_audit_entries(count: 1, only: "repository_security_configuration.applied") do
        assert_changes("RepositorySecurityConfiguration.count", from: 0, to: 1) do
          perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
            as @owner
            put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{security_configuration.id}/repositories",
              params: { repository_ids: [repo.id] }, as: :json
            assert_response :created
          end
        end
      end

      repository_security_configuration = RepositorySecurityConfiguration.find_by!(repository: repo)
      assert_equal "enforced", repository_security_configuration.state
      event = events.sole

      assert_equal "repository_security_configuration.applied", event[:action]
      assert_equal @owner.display_login, event[:actor]
      assert_equal @org.display_login, event[:org]
      assert_equal repository_security_configuration.state, event[:repository_security_configuration_state]
      assert_equal repository_security_configuration.repository_id, event[:repo_id]
      assert_equal repository_security_configuration.security_configuration_id, event[:security_configuration_id]
      assert_nil event[:security_configuration_failure_reason]
    end

    test "creates audit logs when a configuration replaces another for a repository" do
      repo = create(:private_repository, owner: @org)
      repo_security_configuration = create(:repository_security_configuration, :attached, repository: repo, security_configuration: @configuration)
      security_configuration = create(:security_configuration, :non_ghas, :enforced, target: @org)

      as @owner
      events = assert_performed_audit_entries(count: 2, only: EVENTS) do
        assert_no_changes("RepositorySecurityConfiguration.count") do
          perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
            as @owner
            put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{security_configuration.id}/repositories",
              params: { repository_ids: [repo.id], override_existing_config: true }, as: :json
            assert_response :created
          end
        end
      end

      repository_security_configuration = RepositorySecurityConfiguration.find_by!(repository: repo)
      assert_equal "enforced", repository_security_configuration.state
    end

    test "creates an audit log entry when a configuration fails to apply to a repository" do
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(true)

      ApplySecurityConfigurationToRepositoryJob.any_instance.stubs(:perform)
        .raises(ApplySecurityConfigurationToRepositoryJob::FatalError, "boom")

      repo = create(:private_repository, owner: @org)

      as @owner
      events = assert_performed_audit_entries(count: 1, only: "repository_security_configuration.failed") do
        assert_changes("RepositorySecurityConfiguration.count", from: 0, to: 1) do
          perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
            as @owner
            put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{@configuration.id}/repositories",
              params: { repository_ids: [repo.id] }, as: :json
            assert_response :created
          end
        end
      end

      repository_security_configuration = RepositorySecurityConfiguration.find_by!(repository: repo)
      event = events.find { |e| e[:action] == "repository_security_configuration.failed" }

      refute_nil event
      assert_equal @owner.display_login, event[:actor]
      assert_equal @org.display_login, event[:org]
      assert_equal repository_security_configuration.repository_id, event[:repo_id]
      assert_equal repository_security_configuration.security_configuration_id, event[:security_configuration_id]
      assert_equal "Failed to enable.", event[:repository_security_configuration_failure_reason]
    end
  end

  context "#destroy" do
    test "returns 200" do
      repo = create(:private_repository, owner: @org)
      as @owner
      delete "/organizations/#{@org.display_login}/settings/security_products/configuration/repositories",
        params: { repository_ids: [repo.id] }, as: :json

      assert_response :ok
    end

    test "renders 404 for users who are not a memeber of the organization" do
      repo = create(:private_repository, owner: @org)

      as @random_user
      delete "/organizations/#{@org.display_login}/settings/security_products/configuration/repositories",
        params: { repository_ids: [repo.id] }, as: :json

      assert_response :not_found
    end

    test "renders 404 for org members who don't have access" do
      repo = create(:private_repository, owner: @org)

      as @member
      delete "/organizations/#{@org.display_login}/settings/security_products/configuration/repositories",
        params: { repository_ids: [repo.id] }, as: :json

      assert_response :not_found
    end

    test "deletes the repository configuration" do
      repo = create(:private_repository, owner: @org)
      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
        code_scanning: :not_set,
        secret_scanning: :not_set,
        secret_scanning_push_protection: :not_set,
      )
      security_configuration.apply_to_repository(@owner, repo, @org)

      # Stub this to return false so that the job enqueued (but not run) above doesn't block our request:
      Organization.any_instance.stubs(:security_configurations_applying_or_blocked?).returns(false)

      assert_changes("RepositorySecurityConfiguration.count", from: 1, to: 0) do
        perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob]) do
          as @owner
          delete "/organizations/#{@org.display_login}/settings/security_products/configuration/repositories",
          params: { repository_ids: [repo.id] }, as: :json
          assert_response :ok
        end
      end
    end

    test "creates an audit log entry when a repository configuration is deleted" do
      repo = create(:private_repository, owner: @org)
      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
        code_scanning: :not_set,
        secret_scanning: :not_set,
        secret_scanning_push_protection: :not_set,
      )
      security_configuration.apply_to_repository(@owner, repo, @org)

      # Stub this to return false so that the job enqueued (but not run) above doesn't block our request:
      Organization.any_instance.stubs(:security_configurations_applying_or_blocked?).returns(false)

      events = assert_performed_audit_entries(count: 1, only: "repository_security_configuration.removed") do
        assert_changes("RepositorySecurityConfiguration.count", from: 1, to: 0) do
          perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob]) do
            as @owner
            delete "/organizations/#{@org.display_login}/settings/security_products/configuration/repositories",
            params: { repository_ids: [repo.id] }, as: :json
            assert_response :ok
          end
        end
      end

      assert_empty(RepositorySecurityConfiguration.where(repository: repo))

      event = events.find { |e| e[:action] == "repository_security_configuration.removed" }

      assert_equal "repository_security_configuration.removed", event[:action]
      assert_equal @owner.display_login, event[:actor]
      assert_equal @org.display_login, event[:org]
      assert_nil event[:repository_security_configuration_state]
      assert_equal repo.id, event[:repo_id]
      assert_equal security_configuration.id, event[:security_configuration_id]
    end
  end
end
