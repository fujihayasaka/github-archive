# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdateSecuritySettingsOrganizationTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include TurboghasHelpers
  include HydroTestHelpers

  fixtures do
    # Users
    @admin = create(:user)

    # Businesses
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
    @biz = create(:global_business)
    @biz.add_owner(@admin, actor: @admin)

    # Organizations
    @org = create(:business_plus_organization, business: @biz).tap { |org| org.add_admin(@admin) }

    # Repositories
    @private_repo = create(:private_repository, owner: @org)

    create(:billing_product_uuid, :advanced_security)
  end

  setup do
    GitHub.flipper[:advanced_security_circuit_breaker].disable

    if GitHub.enterprise?
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)
    else
      @biz.mark_advanced_security_as_purchased_for_entity(actor: @admin)
      @biz.set_advanced_security_seats_for_entity(actor: @admin, seats: 10)
    end

    GitHub.stubs(:code_scanning_enabled?).returns(true)
    CodeScanning::Autofix.stubs(:available_in_environment?).returns(true)
  end

  context "GHAS" do
    context "when GHAS is being enabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { advanced_security: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      context "when a business policy does not allow GHAS enablement" do
        test "it returns an error message" do
          @org.stubs(:policy_allows_advanced_security_enablement?).returns(false)

          params = { advanced_security: "enable_all" }
          err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

          assert_equal(
            "GitHub Advanced Security could not be enabled because of a policy setting for the organization",
            err_msg
          )
        end
      end

      context "when a blocking security product toggling is in progress" do
        test "it returns an error message" do
          JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :secret_scanning_disable_all) })

          params = { advanced_security: "enable_all" }
          err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

          assert_equal(
            "Secret scanning is being disabled. Some features under GitHub Advanced Security cannot be enabled or disabled until changes are propagated to all repositories in this organization.",
            err_msg
          )
        end
      end

      context "when enabling GHAS would exceed the GHAS license's seat limit" do
        test "it returns an error message" do
          AdvancedSecurityLicense.any_instance.stubs(:seats).returns(15)
          AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(20)
          AdvancedSecurityLicense.stubs(:seat_usage_increase_if_advanced_security_enabled_for_repos).returns(0)

          params = { advanced_security: "enable_all" }
          err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

          expected =
            if GitHub.enterprise?
              "GitHub Advanced Security could not be enabled because #{@biz.name} is using 5 more GitHub Advanced Security licenses than they have purchased."
            else
              "GitHub Advanced Security could not be enabled because the parent enterprise #{@biz.name} is using 5 more GitHub Advanced Security licenses than they have purchased."
            end

          assert_equal(expected, err_msg)
        end
      end
    end

    context "when GHAS is being disabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { advanced_security: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when GHAS is being enabled on new repositories" do
      test "it configures the organization and returns nil" do
        assert_performed_audit_entries(count: 1, only: "org.advanced_security_enabled_for_new_repos") do
          params = { advanced_security_enabled_new_repos: "enabled" }
          err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

          assert(@org.advanced_security_enabled_on_new_repos?)
          assert_nil(err_msg)
          @org.enable_advanced_security_on_new_repos(actor: @user)
        end
      end

      test "a business policy does not allow GHAS enablement" do
        @org.stubs(:policy_allows_advanced_security_enablement?).returns(false)

        params = { advanced_security_enabled_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_equal(
          "GitHub Advanced Security could not be enabled for new repositories because of a policy setting for the organization",
          err_msg
        )
      end
    end

    context "when GHAS is being disabled on new repositories" do
      test "it configures the organization and returns nil" do
        # turn configuration on so turning off is not a no-op
        params = { advanced_security_enabled_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)
        assert(@org.advanced_security_enabled_on_new_repos?)
        assert_nil(err_msg)

        params = { advanced_security_enabled_new_repos: "disabled" }
        assert_performed_audit_entries(count: 1, only: "org.advanced_security_disabled_for_new_repos") do
          err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)
          refute(@org.advanced_security_enabled_on_new_repos?)
          assert_nil(err_msg)
        end
      end
    end
  end

  context "Dependency graph" do
    context "when dependency graph is being enabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { dependency_graph: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependency graph is being disabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { dependency_graph: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependency graph is being enabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { dependency_graph_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert(@org.dependency_graph_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependency graph is being disabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { dependency_graph_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.dependency_graph_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end
  end

  context "Dependabot alerts" do
    context "when dependabot alerts is being enabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { security_alerts: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot alerts is being disabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { security_alerts: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot alerts is being enabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { security_alerts_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert(@org.security_alerts_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot alerts is being disabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { security_alerts_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.security_alerts_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end
  end

  context "Dependabot security updates" do
    context "when dependabot security updates is being enabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { vulnerability_updates: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot security updates is being disabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { vulnerability_updates: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot security updates is being enabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { vulnerability_updates_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert(@org.vulnerability_updates_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot security updates is being disabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { vulnerability_updates_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.vulnerability_updates_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when grouped security updates is being enabled on all repositories with the feature enabled" do
      test "it enqueues an update job and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_grouped_security_updates].enable
        params = { vulnerability_updates_grouping: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      test "it does not enqueue an update job  with the feature flag disabled" do
        GitHub.flipper[:dependabot_grouped_security_updates].disable
        params = { vulnerability_updates_grouping: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_no_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when grouped security updates is being disabled on all repositories with the feature enabled" do
      test "it enqueues an update job and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_grouped_security_updates].enable
        params = { vulnerability_updates_grouping: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      test "it does not enqueue an update job  with the feature flag disabled" do
        GitHub.flipper[:dependabot_grouped_security_updates].disable
        params = { vulnerability_updates_grouping: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_no_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when grouped security updates is being enabled on new repositories with the feature enabled" do
      test "it configures the organization and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_grouped_security_updates].enable
        params = { vulnerability_updates_grouping_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert(@org.vulnerability_updates_grouping_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      test "it does not configure the organization with the feature flag disabled" do
        GitHub.flipper[:dependabot_grouped_security_updates].disable
        params = { vulnerability_updates_grouping_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.vulnerability_updates_grouping_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when grouped security updates is being disabled on new repositories with the feature enabled" do
      test "it configures the organization and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_grouped_security_updates].enable
        params = { vulnerability_updates_grouping_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.vulnerability_updates_grouping_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      test "it does not configure the organization with the feature flag disabled" do
        GitHub.flipper[:dependabot_grouped_security_updates].disable
        params = { vulnerability_updates_grouping_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.vulnerability_updates_grouping_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when grouped security updates is being enabled with security_configurations enabled" do
      test "it configures the organization and returns nil" do
        GitHub.flipper[:dependabot_grouped_security_updates].enable
        params = { vulnerability_updates_grouping: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

    end

    context "when grouped security updates is being disabled with security_configurations enabled" do
      test "it configures the organization and returns nil" do
        GitHub.flipper[:dependabot_grouped_security_updates].enable
        params = { vulnerability_updates_grouping: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

    end

    context "when dependabot on actions is being enabled on all repositories with the feature enabled" do
      test "it enqueues an update job and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_on_actions].enable
        params = { dependabot_on_actions: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      test "it does not enqueue an update job  with the feature flag disabled" do
        GitHub.flipper[:dependabot_on_actions].disable
        params = { dependabot_on_actions: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_no_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot on actions is being disabled on all repositories with the feature enabled" do
      test "it enqueues an update job and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_on_actions].enable
        params = { dependabot_on_actions: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      test "it does not enqueue an update job  with the feature flag disabled" do
        GitHub.flipper[:dependabot_on_actions].disable
        params = { dependabot_on_actions: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_no_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot on actions is being enabled on new repositories with the feature enabled" do
      test "it configures the organization and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_on_actions].enable
        params = { dependabot_on_actions: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert(@org.dependabot_on_actions_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      test "it does not configure the organization with the feature flag disabled" do
        GitHub.flipper[:dependabot_on_actions].disable
        params = { dependabot_on_actions: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.dependabot_on_actions_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot on actions is being disabled on new repositories with the feature enabled" do
      test "it configures the organization and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_on_actions].enable
        params = { dependabot_on_actions: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.dependabot_on_actions_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      test "it does not configure the organization with the feature flag disabled" do
        GitHub.flipper[:dependabot_on_actions].disable
        params = { dependabot_on_actions: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.dependabot_on_actions_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot self-hosted is being enabled on all repositories with the feature enabled" do
      test "it enqueues an update job and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_on_actions].enable
        GitHub.flipper[:dependabot_self_hosted].enable
        params = { dependabot_self_hosted: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      test "it does not enqueue an update job  with the feature flag disabled" do
        GitHub.flipper[:dependabot_on_actions].disable
        GitHub.flipper[:dependabot_self_hosted].disable
        params = { dependabot_self_hosted: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_no_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot self-hosted is being disabled on all repositories with the feature enabled" do
      test "it enqueues an update job and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_on_actions].enable
        GitHub.flipper[:dependabot_self_hosted].enable
        params = { dependabot_self_hosted: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      test "it does not enqueue an update job  with the feature flag disabled" do
        GitHub.flipper[:dependabot_self_hosted].disable
        params = { dependabot_self_hosted: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_no_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot self-hosted is being enabled on new repositories with the feature enabled" do
      test "it configures the organization and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_on_actions].enable
        GitHub.flipper[:dependabot_self_hosted].enable
        params = { dependabot_self_hosted_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert(@org.dependabot_self_hosted_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      test "it does not configure the organization with the feature flag disabled" do
        GitHub.flipper[:dependabot_self_hosted].disable
        params = { dependabot_self_hosted_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.dependabot_self_hosted_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot self-hosted is being disabled on new repositories with the feature enabled" do
      test "it configures the organization and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_on_actions].enable
        GitHub.flipper[:dependabot_self_hosted].enable
        params = { dependabot_self_hosted_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.dependabot_self_hosted_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      test "it does not configure the organization with the feature flag disabled" do
        GitHub.flipper[:dependabot_self_hosted].disable
        params = { dependabot_self_hosted_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.dependabot_self_hosted_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot autofix is being enabled on all repositories with the feature enabled" do
      test "it enqueues an update job and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_on_actions].enable
        GitHub.flipper[:dependabot_autofix].enable
        params = { dependabot_autofix: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      test "it does not enqueue an update job  with the feature flag disabled" do
        GitHub.flipper[:dependabot_on_actions].disable
        GitHub.flipper[:dependabot_autofix].disable
        params = { dependabot_autofix: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_no_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot autofix is being disabled on all repositories with the feature enabled" do
      test "it enqueues an update job and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_on_actions].enable
        GitHub.flipper[:dependabot_autofix].enable
        params = { dependabot_autofix: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      test "it does not enqueue an update job  with the feature flag disabled" do
        GitHub.flipper[:dependabot_autofix].disable
        params = { dependabot_autofix: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_no_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot autofix is being enabled on new repositories with the feature enabled" do
      test "it configures the organization and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_on_actions].enable
        GitHub.flipper[:dependabot_autofix].enable
        params = { dependabot_autofix_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert(@org.dependabot_autofix_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      test "it does not configure the organization with the feature flag disabled" do
        GitHub.flipper[:dependabot_autofix].disable
        params = { dependabot_autofix_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.dependabot_autofix_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot autofix is being disabled on new repositories with the feature enabled" do
      test "it configures the organization and returns nil with the feature flag enabled" do
        GitHub.flipper[:dependabot_on_actions].enable
        GitHub.flipper[:dependabot_autofix].enable
        params = { dependabot_autofix_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.dependabot_autofix_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      test "it does not configure the organization with the feature flag disabled" do
        GitHub.flipper[:dependabot_autofix].disable
        params = { dependabot_autofix_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.dependabot_autofix_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

  end

  context "Code scanning" do
    context "when code scanning is being enabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { code_scanning: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs 1, only: SecurityAnalysisSettingsUpdateJob
        assert_nil err_msg
      end

      test "when the query suite is extended it enqueues an update job and returns nil" do
        params = { code_scanning: "enable_all", config: { auto_codeql_query_suite: "extended" } }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs 1, only: SecurityAnalysisSettingsUpdateJob
        assert_nil err_msg
      end
    end

    context "when code scanning is being disabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { code_scanning: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs 1, only: SecurityAnalysisSettingsUpdateJob
        assert_nil err_msg
      end
    end

    context "when code scanning recommend extended query suite is being enabled" do
      test "it configures the organization and returns nil" do
        refute(@org.code_scanning_recommend_extended_query_suite?)

        params = { code_scanning_recommend_extended_query_suite: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert(@org.code_scanning_recommend_extended_query_suite?)
        assert_nil(err_msg)
      end
    end

    context "when code scanning recommend extended query suite is being disabled" do
      test "it configures the organization and returns nil" do
        @org.enable_code_scanning_recommend_extended_query_suite(actor: @admin)
        assert(@org.code_scanning_recommend_extended_query_suite?)

        params = { code_scanning_recommend_extended_query_suite: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(@org.code_scanning_recommend_extended_query_suite?)
        assert_nil(err_msg)
      end
    end

    context "autofix" do
      test "disabling" do
        CodeScanningOrganizationConfig.new(organization: @org).enable_code_scanning_autofix_settings(actor: @admin)
        assert(CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_settings_enabled?)

        params = { code_scanning_autofix: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_settings_enabled?)
        assert_nil(err_msg)
      end

      test "enabling" do
        CodeScanningOrganizationConfig.new(organization: @org).disable_code_scanning_autofix_settings(actor: @admin)
        refute(CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_settings_enabled?)

        params = { code_scanning_autofix: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert(CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_settings_enabled?)
        assert_nil(err_msg)
      end

      test "audit log events" do
        # Default
        assert CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_settings_enabled?

        events = assert_performed_audit_entries(count: 1, only: "org.code_scanning_autofix_disabled") do
          err_msg = UpdateSecuritySettings.perform(@org, { code_scanning_autofix: "disabled" }, actor: @admin).try(:fetch, :error, nil)
          assert_nil err_msg
        end

        assert_subset_hash(
          {
            org_id: @org.id,
            action: "org.code_scanning_autofix_disabled",
            user: @admin.login
          },
          events.first
        )

        refute CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_settings_enabled?

        events = assert_performed_audit_entries(count: 1, only: "org.code_scanning_autofix_enabled") do
          err_msg = UpdateSecuritySettings.perform(@org, { code_scanning_autofix: "enabled" }, actor: @admin).try(:fetch, :error, nil)
          assert_nil err_msg
        end

        assert_subset_hash(
          {
            org_id: @org.id,
            action: "org.code_scanning_autofix_enabled",
            user: @admin.login
          },
          events.first
        )

        assert CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_settings_enabled?
      end
    end

    context "autofix for third party tools", feature_enabled: :code_scanning_autofix_thirdparty do
      test "disabling" do
        CodeScanningOrganizationConfig.new(organization: @org).enable_code_scanning_autofix_third_party_tools_settings(actor: @admin)
        assert(CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_third_party_tools_settings_enabled?)

        params = { code_scanning_autofix_third_party_tools: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_third_party_tools_settings_enabled?)
        assert_nil(err_msg)
      end

      test "enabling" do
        CodeScanningOrganizationConfig.new(organization: @org).disable_code_scanning_autofix_third_party_tools_settings(actor: @admin)
        refute(CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_third_party_tools_settings_enabled?)

        params = { code_scanning_autofix_third_party_tools: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert(CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_third_party_tools_settings_enabled?)
        assert_nil(err_msg)
      end

      test "audit log events" do
        # Default
        assert CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_third_party_tools_settings_enabled?

        events = assert_performed_audit_entries(count: 1, only: "org.code_scanning_autofix_third_party_tools_disabled") do
          err_msg = UpdateSecuritySettings.perform(@org, { code_scanning_autofix_third_party_tools: "disabled" }, actor: @admin).try(:fetch, :error, nil)
          assert_nil err_msg
        end

        assert_subset_hash(
          {
            org_id: @org.id,
            action: "org.code_scanning_autofix_third_party_tools_disabled",
            user: @admin.login
          },
          events.first
        )

        refute CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_third_party_tools_settings_enabled?

        events = assert_performed_audit_entries(count: 1, only: "org.code_scanning_autofix_third_party_tools_enabled") do
          err_msg = UpdateSecuritySettings.perform(@org, { code_scanning_autofix_third_party_tools: "enabled" }, actor: @admin).try(:fetch, :error, nil)
          assert_nil err_msg
        end

        assert_subset_hash(
          {
            org_id: @org.id,
            action: "org.code_scanning_autofix_third_party_tools_enabled",
            user: @admin.login
          },
          events.first
        )

        assert CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_third_party_tools_settings_enabled?
      end
    end
  end

  context "Secret scanning" do
    context "when secret scanning is being enabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { secret_scanning: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      context "when a business policy does not allow GHAS enablement" do
        test "secret scanning can be enabled on eligible repos in an org" do
          @org.stubs(:policy_allows_advanced_security_enablement?).returns(false)

          params = { secret_scanning: "enable_all" }
          err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

          assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
          assert_nil(err_msg)
        end
      end
    end

    context "when secret scanning is being disabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { secret_scanning: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when secret scanning is being enabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { secret_scanning_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert(SecretScanning::Features::Org::TokenScanning.new(@org).secret_scanning_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      context "when a business policy does not allow GHAS enablement" do
        test "it returns an error message" do
          @org.stubs(:policy_allows_advanced_security_enablement?).returns(false)

          params = { secret_scanning_new_repos: "enabled" }
          err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

          assert(SecretScanning::Features::Org::TokenScanning.new(@org).secret_scanning_enabled_for_new_repos?)
          assert_nil err_msg
        end
      end
    end

    context "when secret scanning is being disabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { secret_scanning_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(SecretScanning::Features::Org::TokenScanning.new(@org).secret_scanning_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end
  end

  context "Secret scanning push protection" do
    context "when secret scanning push protection is being enabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { secret_scanning_push_protection: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when secret scanning push protection is being disabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { secret_scanning_push_protection: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when secret scanning push protection is being enabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { secret_scanning_push_protection_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert(SecretScanning::Features::Org::PushProtection.new(@org).enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when secret scanning push protection is being disabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { secret_scanning_push_protection_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(SecretScanning::Features::Org::PushProtection.new(@org).enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when secret scanning push protection custom message status is being enabled" do
      test "it configures the organization and returns nil" do
        params = { push_protection_custom_message_status: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert(SecretScanning::Features::Org::PushProtection.new(@org).custom_message_enabled?)
        assert_nil(err_msg)
      end
    end

    context "when secret scanning push protection custom message status is being disabled" do
      test "it configures the organization and returns nil" do
        params = { push_protection_custom_message_status: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        refute(SecretScanning::Features::Org::PushProtection.new(@org).custom_message_enabled?)
        assert_nil(err_msg)
      end
    end

    context "when secret scanning push protection custom message status is being modified" do
      test "it sets the custom message and returns nil" do
        expected = "https://example.com"
        params = { push_protection_custom_message: expected }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

        assert_equal(expected, @org.get_push_protection_custom_message)
        assert_nil(err_msg)
      end

      context "when the custom message is not a URL" do
        test "it returns an error message" do
          params = { push_protection_custom_message: "This is not a URL." }
          err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

          assert_equal("Input should be a URL", err_msg)
        end
      end
    end
  end

  context "Secret scanning validity checks" do
    test "it enqueues a job when validity checks are enabled" do
      params = { secret_scanning_validity_checks: "enabled" }
      err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

      num_queued = GitHub.enterprise? ? 0 : 1
      assert_enqueued_jobs(num_queued, only: PublishSecretScanningEnablementChangeJob)
      assert_nil(err_msg)
    end
    test "it enqueues a job when validity checks are disabled" do
      params = { secret_scanning_validity_checks: "disabled" }
      err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

      num_queued = GitHub.enterprise? ? 0 : 1
      assert_enqueued_jobs(num_queued, only: PublishSecretScanningEnablementChangeJob)
      assert_nil(err_msg)
    end
    test "it does not enqueue a job if the param for validity checks is nil" do
      params = { secret_scanning_validity_checks: nil }
      err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

      assert_enqueued_jobs(0, only: PublishSecretScanningEnablementChangeJob)
      assert_nil(err_msg)
    end

    test "emits event in audit log when automatic validity checks are enabled", skip_enterprise: true do
      event_name = "org_secret_scanning_automatic_validity_checks.enabled"
      events = assert_performed_audit_entries(count: 1, only: event_name) do
        params = { secret_scanning_validity_checks: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: event_name,
        user: @admin.login,
        org: @org.login
      }

      assert_subset_hash expected_payload, events.first
    end

    test "emits event in audit log when automatic validity checks are disabled", skip_enterprise: true do
      event_name = "org_secret_scanning_automatic_validity_checks.disabled"
      events = assert_performed_audit_entries(count: 1, only: event_name) do
        params = { secret_scanning_validity_checks: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: event_name,
        user: @admin.login,
        org: @org.login
      }

      assert_subset_hash expected_payload, events.first
    end

  end

  context "Secret scanning generic secrets" do
    test "it enqueues a job when generic secrets are enabled" do
      params = { secret_scanning_generic_secrets: "enabled" }
      err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

      num_queued = GitHub.enterprise? ? 0 : 1
      assert_enqueued_jobs(num_queued, only: PublishSecretScanningEnablementChangeJob)
      assert_nil(err_msg)
    end
    test "it enqueues a job when generic_secrets are disabled" do
      params = { secret_scanning_generic_secrets: "disabled" }
      err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

      num_queued = GitHub.enterprise? ? 0 : 1
      assert_enqueued_jobs(num_queued, only: PublishSecretScanningEnablementChangeJob)
      assert_nil(err_msg)
    end
    test "it does not enqueue a job if the param for generic secrets is nil" do
      params = { secret_scanning_generic_secrets: nil }
      err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

      assert_enqueued_jobs(0, only: PublishSecretScanningEnablementChangeJob)
      assert_nil(err_msg)
    end

    test "emits event in audit log when generic secrets are enabled", skip_enterprise: true do
      event_name = "org_secret_scanning_generic_secrets.enabled"
      events = assert_performed_audit_entries(count: 1, only: event_name) do
        params = { secret_scanning_generic_secrets: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: event_name,
        user: @admin.login,
        org: @org.login
      }

      assert_subset_hash expected_payload, events.first
    end

    test "emits event in audit log when generic secrets are disabled", skip_enterprise: true do
      event_name = "org_secret_scanning_generic_secrets.disabled"
      events = assert_performed_audit_entries(count: 1, only: event_name) do
        params = { secret_scanning_generic_secrets: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: event_name,
        user: @admin.login,
        org: @org.login
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  context "Secret scanning delegated alert closures" do
    test "emits Hydro event when delegated alert closures are enabled" do
      params = { token_scanning_delegated_closures_enabled: "enabled" }
      event_name = "org_secret_scanning_delegated_closures.enabled"
      err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

      assert_hydro_published_partial({
          event_name: event_name,
          owner_id: @org.id,
          owner_type: :ORGANIZATION,
        }, schema: "github.security_settings.v1.SecuritySettingsUpdate")
    end

    test "emits Hydro event when delegated alert closures are disabled" do
      params = { token_scanning_delegated_closures_enabled: "disabled" }
      event_name = "org_secret_scanning_delegated_closures.disabled"
      err_msg = UpdateSecuritySettings.perform(@org, params, actor: @admin).try(:fetch, :error, nil)

      assert_hydro_published_partial({
          event_name: event_name,
          owner_id: @org.id,
          owner_type: :ORGANIZATION,
        }, schema: "github.security_settings.v1.SecuritySettingsUpdate")
    end
  end
end
