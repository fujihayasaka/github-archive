# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositorySecurityConfigurationTest < GitHub::IntegrationTestCase
  include AuditLog::IntegrationTestHelpers
  include SecurityProductsEnablement::EnterpriseTestHelpers
  include HydroTestHelpers
  include HydroMessageJobTestHelpers

  fixtures do
    @org = create(:organization)
    @private_repo = create(:private_repository, owner: @org)
    @public_repo = create(:repository, owner: @org)
  end

  setup do
    @security_configuration = create(:security_configuration, target: @org)
  end

  context "instrumentation" do
    SecurityProductsEnablement.enablement_failures_map.keys.each do |failure_reason|
      # Do not attempt to test mappings with audit logging disabled:
      next if SecurityProductsEnablement.enablement_failures_map.dig(failure_reason, "audit_log_allowed") == false

      test "failure is instrumented and audit logged for `#{failure_reason}`" do
        repository_security_configuration = create(
          :repository_security_configuration,
          security_configuration: @security_configuration,
          repository: @private_repo,
          state: "attached",
        )

        audit_entries = assert_performed_audit_entries(count: 1, only: "repository_security_configuration.failed") do
          repository_security_configuration.update!(state: "failed", failure_reason:)
        end

        expected_payload = {
          target: @org.name,
          repo_id: @private_repo.id,
          repo: @private_repo.name_with_owner,
          security_configuration_id: @security_configuration.id,
          security_configuration_name: @security_configuration.name,
          repository_security_configuration_failure_reason: SecurityProductsEnablement.enablement_failures_map[failure_reason]["audit_log_message"],
        }

        audit_entry = audit_entries.sole
        assert_equal "repository_security_configuration.failed", audit_entry[:action]
        assert_subset_hash expected_payload, audit_entry
      end
    end

    test "unknown failures are instrumented and audit logged" do
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration: @security_configuration,
        repository: @private_repo,
        state: "attached",
      )

      audit_entries = assert_performed_audit_entries(count: 1, only: "repository_security_configuration.failed") do
        repository_security_configuration.update!(state: "failed", failure_reason: "Failed to toggle dependabot self hosted runners.")
      end

      expected_payload = {
        target: @org.name,
        repo_id: @private_repo.id,
        repo: @private_repo.name_with_owner,
        security_configuration_id: @security_configuration.id,
        security_configuration_name: @security_configuration.name,
        repository_security_configuration_failure_reason: "Failed to enable.",
      }

      audit_entry = audit_entries.sole
      assert_equal "repository_security_configuration.failed", audit_entry[:action]
      assert_subset_hash expected_payload, audit_entry
    end

    test "does not audit log when state is not updated to `failed`" do
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration: @security_configuration,
        repository: @private_repo,
        state: "attached",
      )

      assert_performed_audit_entries(count: 0, only: "repository_security_configuration.failed") do
        repository_security_configuration.update!(state: "attaching", failure_reason: "Failed to toggle dependabot self hosted runners.")
      end
    end

    test "does not audit log removed events when repository is unarchived" do
      created_by_user = create(:user)
      unarchived_repo = create(
        :private_repository,
        owner: @org,
        name: "unarchived-repo",
        created_by_user_id: created_by_user.id)
      security_configuration = create(
        :security_configuration,
        :not_set,
        target: @org,
        secret_scanning: :enabled,
        enable_ghas: true,
      )
      create(
        :repository_security_configuration,
        repository: unarchived_repo,
        user: @org,
        security_configuration:,
        state: "attached"
      )

      assert_performed_audit_entries(count: 0, only: ["repository_security_configuration.removed"]) do
        perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob do
          perform_hydro_message_job(
            { repository_id: unarchived_repo.id, actor_id: unarchived_repo.created_by_user.id, request_id: SecureRandom.uuid },
            schema: "github.repositories.v1.Unarchived",
            queue: SecurityProductsEnablement::HydroRepositoryUnarchivedJob.queue_name
          )
        end
      end
    end

    test "creates an audit log entry when the configuration is removed by a settings change" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true, code_scanning: "disabled")
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "attached"
      )

      assert_performed_audit_entries(count: 1, only: "repository_security_configuration.removed_by_settings_change") do
        repository_security_configuration.remove_if_possible(action: "enabled", feature: :auto_codeql, owner: @org)
      end
    end

    test "creates an audit log entry when the configuration is removed by enterprise" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true)
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "attached"
      )

      assert_performed_audit_entries(count: 1, only: "repository_security_configuration.removed_by_settings_change") do
        repository_security_configuration.remove_if_possible(action: "disabled", feature: :advanced_security, owner: @org, action_source: "enterprise_bulk_enablement")
      end
    end

    # This case handles disabling services that also disable dependent services (e.g. disabling Dep graph also disables alerts)
    test "create only one audit log when a configuration is removed" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true)
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "attached"
      )

      @private_repo.enable_dependency_graph(actor: @private_repo.owner)
      @private_repo.enable_vulnerability_alerts(actor: @private_repo.owner)

      assert_performed_audit_entries(count: 1, only: "repository_security_configuration.removed_by_settings_change") do
        SecurityProduct::ServiceManager.new(@private_repo).toggle_services(@org, services_to_disable: [:dependency_graph])
      end
    end

    test "creates an audit log entry when the configuration is attached" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true)
      repo_security_config = create(:repository_security_configuration,
        security_configuration: security_configuration,
        repository: @public_repo,
        state: "attaching"
      )

      events = assert_performed_audit_entries(count: 1, only: "repository_security_configuration.applied") do
        repo_security_config.update(state: :attached)
      end

      assert_equal last_performed_audit_entries, events
      expected_payload = {
        security_configuration_id: security_configuration&.id,
        security_configuration_name: security_configuration&.name,
        repo_id: @public_repo&.id,
        repo: @public_repo&.name_with_owner,
        repository_security_configuration_state: repo_security_config&.state,
      }

      assert_subset_hash expected_payload, events.first
    end

    test "creates an audit log entry when the configuration is enforced" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true)
      create(:security_configuration_policy, security_configuration: security_configuration, target: @org, enforcement: :enforced)
      repo_security_config = create(:repository_security_configuration,
        security_configuration: security_configuration,
        repository: @public_repo,
        state: "attaching"
      )

      events = assert_performed_audit_entries(count: 1, only: "repository_security_configuration.applied") do
        repo_security_config.update(state: :enforced)
      end

      assert_equal last_performed_audit_entries, events
      expected_payload = {
        security_configuration_id: security_configuration&.id,
        security_configuration_name: security_configuration&.name,
        repo_id: @public_repo&.id,
        repo: @public_repo&.name_with_owner,
        repository_security_configuration_state: repo_security_config&.state,
      }

      assert_subset_hash expected_payload, events.first
    end

    test "creates an audit log entry when the configuration is detached" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true)
      repo_security_config = create(:repository_security_configuration,
        security_configuration: security_configuration,
        repository: @public_repo,
        state: "attached"
      )

      events = assert_performed_audit_entries(count: 1, only: "repository_security_configuration.removed") do
        repo_security_config.destroy!
      end

      assert_equal last_performed_audit_entries, events
      expected_payload = {
        security_configuration_id: security_configuration&.id,
        security_configuration_name: security_configuration&.name,
        repo_id: @public_repo&.id,
        repo: @public_repo&.name_with_owner,
        repository_security_configuration_state: nil,
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  context "#remove_if_possible" do
    test "sets the configuration to removed when the repository setting does not match the configuration" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true, code_scanning: "disabled")
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "attached"
      )

      repository_security_configuration.remove_if_possible(action: "enabled", feature: :auto_codeql, owner: @org)

      assert_equal "removed", repository_security_configuration.reload.state
    end

    test "sets the configuration to removed when the GHAS setting of the repository does not match the configuration" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true)
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "attached"
      )

      repository_security_configuration.remove_if_possible(action: "disabled", feature: :advanced_security, owner: @org)

      assert_equal "removed", repository_security_configuration.reload.state
    end

    test "sets the configuration to removed when the code scanning setting of the repository does not match the configuration options" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true, code_scanning: :enabled, code_scanning_options: { "runner_type" => "labeled", "runner_label" => "custom-label" })
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "attached",
      )

      GitHub.stubs(:actions_enabled?).returns(true)
      CodeScanning::Status.stubs(:mac_os_runner?).returns(true)
      CodeScanning::Status.stubs(:validate_prerequisites)
      SecurityProductsEnablement::Actions::RunnerChecker.any_instance.stubs(:labelled_runners_available?).returns(true)

      body_params_matcher = lambda do |actual, _|
        Turboscan::Proto::EnableRequest.decode_json(actual.body).runner_label == "different-custom-label"
      end

      VCR.use_cassette("code-scanning/managed-analyses-enable", persist_with: :turboscan, match_requests_on: [:method, :uri, body_params_matcher]) do
        assert_nil SecurityProduct::ServiceManager.new(@private_repo).toggle_services(User.ghost, services_to_enable: [[:auto_codeql, { action: :enable, runner_type: "labeled", runner_label: "different-custom-label", skip_ghas_check?: true }]]).error
      end

      assert_equal "removed", repository_security_configuration.reload.state
    end

    test "returns an error when the code scanning setting of the repository does not match the configuration options and the configuration is enforced" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true, code_scanning: :enabled, code_scanning_options: { "runner_type" => "labeled", "runner_label" => "custom-label" })
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "enforced",
      )

      GitHub.stubs(:actions_enabled?).returns(true)
      CodeScanning::Status.stubs(:mac_os_runner?).returns(true)
      CodeScanning::Status.stubs(:validate_prerequisites)
      CodeScanning::AutoCodeql.any_instance.expects(:enabled?).at_least_once.returns(true)
      SecurityProductsEnablement::Actions::RunnerChecker.any_instance.stubs(:labelled_runners_available?).returns(true)

      assert_equal :security_configuration_enforced, SecurityProduct::ServiceManager.new(@private_repo).toggle_services(User.ghost, services_to_enable: [[:auto_codeql, { action: :enable, runner_type: "labeled", runner_label: "different-custom-label", skip_ghas_check?: true }]]).error
      assert_equal "enforced", repository_security_configuration.reload.state
    end

    test "returns no error when the code scanning setting of the repository do match the configuration options and the configuration is enforced" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true, code_scanning: :enabled, code_scanning_options: { "runner_type" => "labeled", "runner_label" => "custom-label" })
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "enforced",
      )

      GitHub.stubs(:actions_enabled?).returns(true)
      CodeScanning::Status.stubs(:mac_os_runner?).returns(true)
      CodeScanning::Status.stubs(:validate_prerequisites)
      CodeScanning::AutoCodeql.any_instance.expects(:enabled?).at_least_once.returns(true)
      SecurityProductsEnablement::Actions::RunnerChecker.any_instance.stubs(:labelled_runners_available?).returns(true)

      body_params_matcher = lambda do |actual, _|
        actual_body = Turboscan::Proto::UpdateRequest.decode_json(actual.body)
        actual_body.runner_type == :RUNNER_TYPE_LABELED && actual_body.runner_label == "custom-label"
      end

      VCR.use_cassette("code-scanning/managed-analyses-update", persist_with: :turboscan, match_requests_on: [:method, :uri, body_params_matcher]) do
        assert_nil SecurityProduct::ServiceManager.new(@private_repo).toggle_services(User.ghost, services_to_enable: [[:auto_codeql, { action: :update, runner_type: "labeled", runner_label: "custom-label", skip_ghas_check?: true }]]).error
      end
      assert_equal "enforced", repository_security_configuration.reload.state
    end

    test "allows you to change a code scanning label if a security configuration does not set it" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true, code_scanning: :enabled, code_scanning_options: { "runner_type" => "not_set", "runner_label" => nil })
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "enforced",
      )

      GitHub.stubs(:actions_enabled?).returns(true)
      CodeScanning::Status.stubs(:mac_os_runner?).returns(true)
      CodeScanning::Status.stubs(:validate_prerequisites)
      CodeScanning::AutoCodeql.any_instance.expects(:enabled?).at_least_once.returns(true)
      SecurityProductsEnablement::Actions::RunnerChecker.any_instance.stubs(:labelled_runners_available?).returns(true)

      body_params_matcher = lambda do |actual, _|
        actual_body = Turboscan::Proto::UpdateRequest.decode_json(actual.body)
        actual_body.runner_type == :RUNNER_TYPE_LABELED && actual_body.runner_label == "custom-label"
      end

      VCR.use_cassette("code-scanning/managed-analyses-update", persist_with: :turboscan, match_requests_on: [:method, :uri, body_params_matcher]) do
        assert_nil SecurityProduct::ServiceManager.new(@private_repo).toggle_services(User.ghost, services_to_enable: [[:auto_codeql, { action: :update, runner_type: "labeled", runner_label: "custom-label", skip_ghas_check?: true }]]).error
      end
      assert_equal "enforced", repository_security_configuration.reload.state
    end

    test "sets the configuration to removed when the repository setting changes and the configuration is in failed state" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true, code_scanning: "disabled")
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "failed"
      )

      repository_security_configuration.remove_if_possible(action: "enabled", feature: :auto_codeql, owner: @org)

      assert_equal "removed", repository_security_configuration.reload.state
    end

    test "does not detach the configuration when the repository setting matches the configuration" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true, code_scanning: "disabled")
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "attached"
      )

      repository_security_configuration.remove_if_possible(action: "disabled", feature: :auto_codeql, owner: @org)

      assert_equal "attached", repository_security_configuration.reload.state
    end

    test "sets the configuration to removed even when the repository setting matches the configuration if forced" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true, code_scanning: "disabled")
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "attached"
      )

      repository_security_configuration.remove_if_possible(
        action: "disabled",
        feature: :auto_codeql,
        owner: @org,
        force: true,
      )

      assert_equal "removed", repository_security_configuration.reload.state
    end

    test "does not detach the configuration when the GHAS setting of the repository matches the configuration" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true)
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "attached"
      )

      repository_security_configuration.remove_if_possible(action: "enabled", feature: :advanced_security, owner: @org)

      assert_equal "attached", repository_security_configuration.reload.state
    end

    test "does not detach the configuration when the configuration allows the setting to be changed" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true, code_scanning: "not_set")
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "attached"
      )

      repository_security_configuration.remove_if_possible(action: "disabled", feature: :auto_codeql, owner: @org)

      assert_equal "attached", repository_security_configuration.reload.state
    end

    test "does not detach the configuration when the configuration allows the setting to be changed if forced" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true, code_scanning: "not_set")
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "attached"
      )

      repository_security_configuration.remove_if_possible(
        action: "disabled",
        feature: :auto_codeql,
        owner: @org,
        force: true,
      )

      assert_equal "attached", repository_security_configuration.reload.state
    end

    test "does not detach the configuration when it is not attached or failed" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true, code_scanning: "enabled")
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "attaching"
      )

      repository_security_configuration.remove_if_possible(action: "disabled", feature: :auto_codeql, owner: @org)

      assert_equal "attaching", repository_security_configuration.reload.state
    end

    test "marks the configuration as removed by enterprise when the action source is enterprise_bulk_enablement" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true)
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @private_repo,
        state: "attached"
      )

      repository_security_configuration.remove_if_possible(action: "disabled", feature: :advanced_security, owner: @org, action_source: "enterprise_bulk_enablement")

      assert_predicate repository_security_configuration.reload, :removed_by_enterprise?
    end
  end
end
