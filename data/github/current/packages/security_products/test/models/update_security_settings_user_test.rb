# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdateSecuritySettingsUserTest < GitHub::TestCase
  include SecretScanning::Features::FeatureFlagHelper
  include HydroTestHelpers


  fixtures do
    @admin = create(:user)
    @private_repo = create(:private_repository, owner: @admin)
  end

  setup do
    GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
    enable_feature_flag(FeatureFlags::PUSH_PROTECTION_FOR_FPR)
    enable_feature_flag(FeatureFlags::USER_SCOPED_ANCESTOR_SCAN, @admin)

    if GitHub.enterprise?
      ::AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:feature_available?).returns(true)
    end

    SecretScanning::Features::Owner::WikiScanning.any_instance.stubs(:enabled?).returns(true)
  end

  context "Dependency graph" do
    context "when dependency graph is being enabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { dependency_graph: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependency graph is being disabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { dependency_graph: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependency graph is being enabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { dependency_graph_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert(@admin.dependency_graph_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependency graph is being disabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { dependency_graph_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        refute(@admin.dependency_graph_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end
  end

  context "Dependabot alerts" do
    context "when dependabot alerts is being enabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { security_alerts: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot alerts is being disabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { security_alerts: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot alerts is being enabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { security_alerts_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert(@admin.security_alerts_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot alerts is being disabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { security_alerts_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        refute(@admin.security_alerts_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end
  end

  context "Dependabot security updates" do
    context "when dependabot security updates is being enabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { vulnerability_updates: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot security updates is being disabled on all repositories" do
      test "it enqueues an update job and returns nil" do
        params = { vulnerability_updates: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot security updates is being enabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { vulnerability_updates_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert(@admin.vulnerability_updates_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot security updates is being disabled on new repositories" do
      test "it configures the organization and returns nil" do
        params = { vulnerability_updates_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        refute(@admin.vulnerability_updates_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when grouped security updates is being enabled on all repositories" do
      test "it enqueues an update job and returns nil with the feature flag turned on" do
        params = { vulnerability_updates_grouping: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when grouped security updates is being disabled on all repositories" do
      test "it enqueues an update job and returns nil with the feature flag turned on" do
        params = { vulnerability_updates_grouping: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when grouped security updates is being enabled on new repositories" do
      test "it configures the organization and returns nil with the feature flag turned on" do
        params = { vulnerability_updates_grouping_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert(@admin.vulnerability_updates_grouping_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when grouped security updates is being disabled on new repositories" do
      test "it configures the organization and returns nil with the feature flag turned on" do
        params = { vulnerability_updates_grouping_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        refute(@admin.vulnerability_updates_grouping_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot on actions is being enabled on all repositories" do
      test "it enqueues an update job and returns nil with the feature flag turned on" do
        enable_feature_flag(:dependabot_on_actions)
        params = { dependabot_on_actions: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      test "it does not enqueue an update job with the feature flag turned off" do
        disable_feature_flag(:dependabot_on_actions)
        params = { dependabot_on_actions: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_no_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot on actions is being disabled on all repositories" do
      test "it enqueues an update job and returns nil with the feature flag turned on" do
        enable_feature_flag(:dependabot_on_actions)
        params = { dependabot_on_actions: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      test "it does not enqueue an update job with the feature flag turned off" do
        disable_feature_flag(:dependabot_on_actions)
        params = { dependabot_on_actions: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_no_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot on actions is being enabled on new repositories" do
      test "it configures the user and returns nil with the feature flag turned on" do
        enable_feature_flag(:dependabot_on_actions)
        params = { dependabot_on_actions: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert(@admin.dependabot_on_actions_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      test "it does not configure the user with the feature flag turned off" do
        disable_feature_flag(:dependabot_on_actions)
        params = { dependabot_on_actions: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        refute(@admin.dependabot_on_actions_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot on actions is being disabled on new repositories" do
      test "it configures the user and returns nil with the feature flag turned on" do
        enable_feature_flag(:dependabot_on_actions)
        params = { dependabot_on_actions: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        refute(@admin.dependabot_on_actions_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      test "it does not configure the user with the feature flag turned off" do
        disable_feature_flag(:dependabot_on_actions)
        params = { dependabot_on_actions: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        refute(@admin.dependabot_on_actions_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot self-hosted is being enabled on all repositories" do
      test "it enqueues an update job and returns nil with the feature flag turned on" do
        enable_feature_flag(:dependabot_on_actions)
        enable_feature_flag(:dependabot_self_hosted)
        params = { dependabot_self_hosted: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      test "it does not enqueue an update job with the feature flag turned off" do
        disable_feature_flag(:dependabot_self_hosted)
        params = { dependabot_self_hosted: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_no_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot self-hosted is being disabled on all repositories" do
      test "it enqueues an update job and returns nil with the feature flag turned on" do
        enable_feature_flag(:dependabot_on_actions)
        enable_feature_flag(:dependabot_self_hosted)
        params = { dependabot_self_hosted: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      test "it does not enqueue an update job with the feature flag turned off" do
        disable_feature_flag(:dependabot_self_hosted)
        params = { dependabot_self_hosted: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_no_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot self-hosted is being enabled on new repositories" do
      test "it configures the organization and returns nil with the feature flag turned on" do
        enable_feature_flag(:dependabot_on_actions)
        enable_feature_flag(:dependabot_self_hosted)
        params = { dependabot_self_hosted_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert(@admin.dependabot_self_hosted_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      test "it does not configure the organization with the feature flag turned off" do
        disable_feature_flag(:dependabot_self_hosted)
        params = { dependabot_selfe_hosted_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        refute(@admin.dependabot_self_hosted_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot self-hosted is being disabled on new repositories" do
      test "it configures the organization and returns nil with the feature flag turned on" do
        enable_feature_flag(:dependabot_on_actions)
        enable_feature_flag(:dependabot_self_hosted)
        params = { dependabot_self_hosted_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        refute(@admin.dependabot_self_hosted_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      test "it does not configure the organization with the feature flag turned off" do
        disable_feature_flag(:dependabot_self_hosted)
        params = { dependabot_self_hosted_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        refute(@admin.dependabot_self_hosted_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot autofix is being enabled on all repositories" do
      test "it enqueues an update job and returns nil with the feature flag turned on" do
        enable_feature_flag(:dependabot_on_actions)
        enable_feature_flag(:dependabot_autofix)
        params = { dependabot_autofix: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      test "it does not enqueue an update job with the feature flag turned off" do
        disable_feature_flag(:dependabot_autofix)
        params = { dependabot_autofix: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_no_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot autofix is being disabled on all repositories" do
      test "it enqueues an update job and returns nil with the feature flag turned on" do
        enable_feature_flag(:dependabot_on_actions)
        enable_feature_flag(:dependabot_autofix)
        params = { dependabot_autofix: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end

      test "it does not enqueue an update job with the feature flag turned off" do
        disable_feature_flag(:dependabot_autofix)
        params = { dependabot_autofix: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert_no_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob)
        assert_nil(err_msg)
      end
    end

    context "when dependabot autofix is being enabled on new repositories" do
      test "it configures the organization and returns nil with the feature flag turned on" do
        enable_feature_flag(:dependabot_on_actions)
        enable_feature_flag(:dependabot_autofix)
        params = { dependabot_autofix_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        assert(@admin.dependabot_autofix_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      test "it does not configure the organization with the feature flag turned off" do
        disable_feature_flag(:dependabot_autofix)
        params = { dependabot_autofix_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        refute(@admin.dependabot_autofix_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end

    context "when dependabot autofix is being disabled on new repositories" do
      test "it configures the organization and returns nil with the feature flag turned on" do
        enable_feature_flag(:dependabot_on_actions)
        enable_feature_flag(:dependabot_autofix)
        params = { dependabot_autofix_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        refute(@admin.dependabot_autofix_enabled_for_new_repos?)
        assert_nil(err_msg)
      end

      test "it does not configure the organization with the feature flag turned off" do
        disable_feature_flag(:dependabot_autofix)
        params = { dependabot_autofix_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)

        refute(@admin.dependabot_autofix_enabled_for_new_repos?)
        assert_nil(err_msg)
      end
    end
  end

  context "Push protection" do
    context "When push protection is enabled for a user" do
      test "it sets the user-level configuration and emits a Hydro BackfillGroupRequest message for an ancestor scan" do
        reset_hydro
        params = { push_protection_user: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)
        user_push_protection = SecretScanning::Features::User::PushProtection.new(@admin)
        assert_nil(err_msg)
        assert user_push_protection.enabled?

        assert_hydro_published_partial({
          owner_id: @admin.id,
          owner_scope: :USER_SCOPE,
          action: :START,
          backfill_type: :FULL,
          feature_flags: [
            SecretScanning::Instrumentation::ServiceFlags::CONTENT_BACKFILL_SCAN,
            SecretScanning::Instrumentation::ServiceFlags::WIKI_INCREMENTAL_SCANS,
            SecretScanning::Instrumentation::ServiceFlags::WIKI_BACKFILL_SCANS,
            FeatureFlags::USER_SCOPED_ANCESTOR_SCAN,
          ],
          security_configuration_id: nil,
        }, schema: "token_scanning_service.v0.BackfillGroupRequest")
      end

      test "it sets the user-level configuration and emits a Hydro BackfillGroupRequest msg for a backfill scan" do
        reset_hydro
        disable_feature_flag(FeatureFlags::USER_SCOPED_ANCESTOR_SCAN)
        params = { push_protection_user: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)
        user_push_protection = SecretScanning::Features::User::PushProtection.new(@admin)
        assert_nil(err_msg)
        assert user_push_protection.enabled?

        assert_hydro_published_partial({
          owner_id: @admin.id,
          owner_scope: :USER_SCOPE,
          action: :START,
          backfill_type: :FULL,
          feature_flags: [
            SecretScanning::Instrumentation::ServiceFlags::CONTENT_BACKFILL_SCAN,
            SecretScanning::Instrumentation::ServiceFlags::WIKI_INCREMENTAL_SCANS,
            SecretScanning::Instrumentation::ServiceFlags::WIKI_BACKFILL_SCANS,
          ],
          security_configuration_id: nil,
        }, schema: "token_scanning_service.v0.BackfillGroupRequest")
      end
    end

    context "When push protection is disabled for a user" do
      test "it sets the user-level configuration and emits a Hydro BackfillGroupRequest message for an ancestor scan" do
        reset_hydro
        params = { push_protection_user: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)
        user_push_protection = SecretScanning::Features::User::PushProtection.new(@admin)
        assert_nil(err_msg)
        refute user_push_protection.enabled?

        assert_hydro_published_partial({
          owner_id: @admin.id,
          owner_scope: :USER_SCOPE,
          action: :CANCEL,
          backfill_type: :FULL,
          feature_flags: [
            SecretScanning::Instrumentation::ServiceFlags::CONTENT_BACKFILL_SCAN,
            SecretScanning::Instrumentation::ServiceFlags::WIKI_INCREMENTAL_SCANS,
            SecretScanning::Instrumentation::ServiceFlags::WIKI_BACKFILL_SCANS,
            FeatureFlags::USER_SCOPED_ANCESTOR_SCAN,
          ],
          security_configuration_id: nil,
        }, schema: "token_scanning_service.v0.BackfillGroupRequest")
      end

      test "it sets the user-level configuration and emits a Hydro BackfillGroupRequest message for a backfill scan" do
        disable_feature_flag(FeatureFlags::USER_SCOPED_ANCESTOR_SCAN)
        reset_hydro
        params = { push_protection_user: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@admin, params).try(:fetch, :error, nil)
        user_push_protection = SecretScanning::Features::User::PushProtection.new(@admin)
        assert_nil(err_msg)
        refute user_push_protection.enabled?

        assert_hydro_published_partial({
          owner_id: @admin.id,
          owner_scope: :USER_SCOPE,
          action: :CANCEL,
          backfill_type: :FULL,
          feature_flags: [
            SecretScanning::Instrumentation::ServiceFlags::CONTENT_BACKFILL_SCAN,
            SecretScanning::Instrumentation::ServiceFlags::WIKI_INCREMENTAL_SCANS,
            SecretScanning::Instrumentation::ServiceFlags::WIKI_BACKFILL_SCANS,
          ],
          security_configuration_id: nil,
        }, schema: "token_scanning_service.v0.BackfillGroupRequest")
      end
    end
  end
end
