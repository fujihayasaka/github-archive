# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class EnterpriseUpdateSecurityConfigurationApplicationsJobTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include JobTestHelper
  include AuditLog::IntegrationTestHelpers
  include SecurityProductsEnablement::EnterpriseTestHelpers

  fixtures do
    @user = create(:verified_user)
    @business = create(:global_business)
    @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
    @org = create(:business_plus_organization, business: @business, admin: @user)
  end

  setup do
    @job = EnterpriseUpdateSecurityConfigurationApplicationsJob.new

    @custom_config_with_dg = create(
      :security_configuration,
      target: @org,
      enable_ghas: true,
      code_scanning: :not_set,
      dependabot_alerts: :not_set,
      dependabot_security_updates: :not_set,
      dependency_graph: :enabled,
      dependency_graph_autosubmit_action: :disabled,
      private_vulnerability_reporting: :disabled,
      secret_scanning: :not_set,
      secret_scanning_push_protection: :not_set,
      secret_scanning_validity_checks: GitHub.secret_scanning_validity_checks_available_on_instance? ? :not_set : :disabled,
    )
    @repo_configs_with_dg = create_list :repository_security_configuration, 2,
      user: @org,
      security_configuration: @custom_config_with_dg,
      state: :attached

    # Create repo configs that aren't applied to validate we don't enqueue jobs for them:
    %i[removed attaching failed updating removed_by_enterprise detached].each do |state|
      create :repository_security_configuration,
        user: @org,
        security_configuration: @custom_config_with_dg,
        state: state
    end

    @custom_config_without_dg = create(
      :security_configuration,
      target: @org,
      enable_ghas: true,
      code_scanning: :not_set,
      dependabot_alerts: :disabled,
      dependabot_security_updates: :disabled,
      dependency_graph: :disabled,
      dependency_graph_autosubmit_action: :disabled,
      private_vulnerability_reporting: :disabled,
      secret_scanning: :not_set,
      secret_scanning_push_protection: :not_set,
      secret_scanning_validity_checks: GitHub.secret_scanning_validity_checks_available_on_instance? ? :not_set : :disabled,
    )
    @repo_configs_without_dg = create_list :repository_security_configuration, 2,
      user: @org,
      security_configuration: @custom_config_without_dg,
      state: :attached

    @custom_config_with_cs_ss = create(
      :security_configuration,
      target: @org,
      enable_ghas: true,
      code_scanning: :enabled,
      dependabot_alerts: :not_set,
      dependabot_security_updates: :not_set,
      dependency_graph: :not_set,
      dependency_graph_autosubmit_action: :disabled,
      private_vulnerability_reporting: :disabled,
      secret_scanning: :enabled,
      secret_scanning_push_protection: :enabled,
      secret_scanning_validity_checks: GitHub.secret_scanning_validity_checks_available_on_instance? ? :enabled : :disabled,
    )

    # Create repo configs that aren't applied to validate we don't enqueue jobs for them:
    %i[removed attaching failed updating removed_by_enterprise detached].each do |state|
      create :repository_security_configuration,
        user: @org,
        security_configuration: @custom_config_with_cs_ss,
        state: state
    end
  end

  context "retries" do
    test "retries on dirty exit" do
      assert_retry_on_dirty_exit job: EnterpriseUpdateSecurityConfigurationApplicationsJob
    end

    test "retries on recoverable exceptions" do
      assert_retry_on_recoverable_exceptions job: EnterpriseUpdateSecurityConfigurationApplicationsJob
    end
  end

  context "#perform" do
    test "exits early if there are no product enablement changes" do
      assert_logged(Body: "No product enablement changes, skipping job run.") do
        perform_job
      end
    end

    test "finds RepositorySecurityConfigurations associated with products that were enabled" do
      # Pretend that Dependency Graph was previously disabled:
      SecurityProductsEnablement::KV.set(@job.key_for_product("dependency_graph"), "false")

      # But now it's been enabled:
      SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(dependency_graph_enabled?: true)

      perform_job

      # 2 for repo_configs_with_dg and 2 for repo_configs_without_dg:
      assert_enqueued_jobs 4

      # We expect to enqueue jobs for repo configs with *and* without Dependency Graph:
      [@repo_configs_with_dg, @repo_configs_without_dg].flatten.each do |rsc|
        assert_enqueued_with(
          job: ApplySecurityConfigurationToRepositoryJob,
          args: [{
            actor_id: User.ghost.id,
            repository_id: rsc.repository.id,
            security_configuration_id: rsc.security_configuration_id,
          }]
        )
      end
    end

    test "does not enqueue apply jobs for RepositorySecurityConfigurations that aren't applied" do
      # Pretend that Code Scanning was previously disabled:
      SecurityProductsEnablement::KV.set(@job.key_for_product("code_scanning"), "false")

      # But now it's been enabled:
      SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(code_scanning_default_setup_enabled?: true)

      # Expect no jobs to be enqueued because there are no applied RepositorySecurityConfigs:
      assert_enqueued_jobs 0 do
        perform_job
      end
    end

    test "does nothing if a product was disabled" do
      # Pretend that Dependency Graph was previously enabled:
      SecurityProductsEnablement::KV.set(@job.key_for_product("dependency_graph"), "true")

      # But now it's been disabled:
      SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(dependency_graph_enabled?: false)

      assert_logged(Body: "No SecurityConfigurations matching the enabled security product were found. Exiting!") do
        assert_enqueued_jobs(0) do
          perform_job
        end
      end
    end

    context "handles Dependency Graph not supporting per-repo enablement" do
      test "enables Dependency Graph on all configurations when it's installed" do
        # Pretend that Dependency Graph was previously disabled:
        SecurityProductsEnablement::KV.set(@job.key_for_product("dependency_graph"), "false")

        # But now it's been enabled:
        SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(dependency_graph_enabled?: true)

        perform_job

        assert @custom_config_without_dg.reload.dependency_graph_enabled?, "expected dependency graph to be enabled"
        assert @custom_config_with_dg.reload.dependency_graph_enabled?, "expected dependency graph to still be enabled"
      end

      test "does nothing when it's disabled" do
        # Pretend that Dependency Graph was previously enabled:
        SecurityProductsEnablement::KV.set(@job.key_for_product("dependency_graph"), "true")

        # But now it's been enabled:
        SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(dependency_graph_enabled?: false)

        perform_job

        assert @custom_config_without_dg.reload.dependency_graph_disabled?, "expected dependency graph to still be disabled"
        assert @custom_config_with_dg.reload.dependency_graph_enabled?, "expected dependency graph to still be enabled"
      end

      test "gracefully handles a config refusing to save" do
        # Pretend that Dependency Graph was previously disabled:
        SecurityProductsEnablement::KV.set(@job.key_for_product("dependency_graph"), "false")

        # But now it's been enabled:
        SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(dependency_graph_enabled?: true)

        # update config to fail validations
        @custom_config_without_dg.update_column(:name, " ")

        assert_logged(Body: "Failed to update SecurityConfiguration to enable Dependency Graph") do
          perform_job
        end

        assert @custom_config_without_dg.reload.dependency_graph_disabled?, "expected dependency graph to still be disabled"
        assert @custom_config_with_dg.reload.dependency_graph_enabled?, "expected dependency graph to still be enabled"
      end
    end
  end

  context "#initialize_enablement_cache!" do
    test "writes values that are missing to KV" do
      refute SecurityProductsEnablement::KV.exists(@job.key_for_product("dependency_graph")).value!,
        "Expected enablement cache value to be missing!"

      @job.initialize_enablement_cache!

      assert SecurityProductsEnablement::KV.exists(@job.key_for_product("dependency_graph")).value!,
        "Expected enablement cache value to be present!"
    end

    test "does not overwrite existing values" do
      # Set a key, as if it were already populated:
      SecurityProductsEnablement::KV.set(@job.key_for_product("dependency_graph"), "false")

      # Ensure that the new value won't match the cached value (false):
      SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(dependency_graph_enabled?: true)

      @job.initialize_enablement_cache!

      assert_equal "false", SecurityProductsEnablement::KV.get(@job.key_for_product("dependency_graph")).value!
    end
  end

  context "#product_enablement_changes" do
    test "detects changes between current enablement and cached state" do
      # Set a key, as if it were already populated:
      SecurityProductsEnablement::KV.set(@job.key_for_product("dependency_graph"), "false")

      # Ensure that the new value won't match the cached value (false):
      SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(dependency_graph_enabled?: true)

      # Initialize the rest of the cache:
      @job.initialize_enablement_cache!

      changes = @job.product_enablement_changes
      refute_empty changes
      assert_equal({ dependency_graph: { before: false, after: true } }, changes)
    end

    test "returns nothing when there are no differences" do
      @job.initialize_enablement_cache!

      changes = @job.product_enablement_changes
      assert_empty changes
    end

    test "audit logs when product enablement changes from disabled to enabled" do
      events = assert_performed_audit_entries(count: 3, only: "security_configuration.update") do
        # Pretend that Dependency Graph was previously disabled:
        SecurityProductsEnablement::KV.set(@job.key_for_product("dependency_graph"), "false")

        # But now it's been enabled:
        SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(dependency_graph_enabled?: true)

        perform_job
      end

      assert events.all? { |event| event[:action] == "security_configuration.update" }
      assert events.all? { |event| event[:org_id] == @org.id }

      grouped_events = events.group_by { |event| event[:security_configuration_id] }

      # For @custom_config_with_dg, we expect one event marking that DG was installed
      with_dg_event = grouped_events[@custom_config_with_dg.id]&.sole
      assert_equal :dependency_graph, with_dg_event[:security_feature]
      assert_equal :installed, with_dg_event[:security_feature_state]

      # For @custom_config_without_dg, we expect two events, one for updating DG to be enabled
      # and one for marking that DG was installed

      without_dg_events = T.must(grouped_events[@custom_config_without_dg.id])
      assert_equal 2, without_dg_events.size

      # assert there is an event for updating DG to be enabled
      assert without_dg_events.detect { |event| !event.keys.include?(:security_feature) && event[:security_configuration_dependency_graph] == "enabled" }.present?

      # assert there is an event for marking DG as installed
      assert without_dg_events.detect { |event| event[:security_feature] == :dependency_graph && event[:security_feature_state] == :installed }.present?
    end

    test "audit logs when product enablement changes from enabled to disabled" do
      # We expect one audit log event for @custom_config_with_dg

      event = assert_performed_audit_entries(count: 1, only: "security_configuration.update") do
        # Pretend that Dependency Graph was previously enabled:
        SecurityProductsEnablement::KV.set(@job.key_for_product("dependency_graph"), "true")

        # But now it's been disabled:
        SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(dependency_graph_enabled?: false)

        perform_job
      end.sole

      assert_equal "security_configuration.update", event[:action]
      assert_equal :dependency_graph, event[:security_feature]
      assert_equal @custom_config_with_dg.id, event[:security_configuration_id]
      assert_equal @org.id, event[:org_id]
    end

    test "does not audit log when a config setting for the product is not_set" do
      events = assert_performed_audit_entries(count: 1, only: "security_configuration.update") do
        SecurityProductsEnablement::KV.set(@job.key_for_product("code_scanning"), "true")
        SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(code_scanning_default_setup_enabled?: false)

        perform_job
      end
      refute events.all? { |event| [@custom_config_with_dg.id, @custom_config_without_dg.id].include?(event[:security_configuration_id]) }
    end
  end

  def perform_job
    # Jobs are run inside of a default connection
    ActiveRecord::Base.connected_to(role: :reading) { @job.perform }
  end
end if GitHub.enterprise?
