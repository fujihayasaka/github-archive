# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdateSecuritySettingsBusinessTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include TurboghasHelpers

  fixtures do
    # Users

    # Businesses
    if GitHub.enterprise?
      @biz = create(:global_business)
      @admin = create(:user)
    else
      @biz = create(:business, :enterprise_managed)
      @admin = create(:emu, business: @biz)
    end

    # Organizations
    @org = create(:business_plus_organization, business: @biz).tap { |org| org.add_admin(@admin) }
    @org2 = create(:business_plus_organization, business: @biz).tap { |org| org.add_admin(@admin) }
    @org3 = create(:business_plus_organization, business: @biz).tap { |org| org.add_admin(@admin) }

    # Repositories
    @private_repo = create(:private_repository, owner: @org)

    # Enterprise managed business
    unless GitHub.enterprise?
      @emu_user = create(:emu, business: @biz)
      @emu_user2 = create(:emu, business: @biz)
      @private_emu_repo = create(:private_repository, owner: @emu_user)
    end

    create(:billing_product_uuid, :advanced_security)
  end

  setup do
    GitHub.flipper[:advanced_security_circuit_breaker].disable

    if GitHub.enterprise?
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
    else
      @biz.mark_advanced_security_as_purchased_for_entity(actor: @admin)
      @biz.set_advanced_security_seats_for_entity(actor: @admin, seats: 10)

      @biz.mark_advanced_security_as_purchased_for_entity(actor: @admin)
      @biz.set_advanced_security_seats_for_entity(actor: @admin, seats: 10)
    end

    GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::PUSH_PROTECTION_FOR_FPR].enable
  end

  context "GHAS for organizations" do
    context "when GHAS is being enabled on all repositories" do
      test "it enqueues a SecurityAnalysisSettingsBatchUpdateBusinessJob and returns nil" do
        params = { advanced_security: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsBatchUpdateBusinessJob)
        assert_nil(err_msg)
      end

      context "when a business policy does not allow GHAS enablement" do
        test "it returns an error message" do
          @biz.stubs(:policy_allows_advanced_security_enablement?).returns(false)

          params = { advanced_security: "enable_all" }
          err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

          assert_equal(
            "GitHub Advanced Security could not be enabled because of a policy setting for the organization",
            err_msg
          )
        end
      end

      context "when enterprise security managers are enabled" do
        test "it returns an error message" do
          EnterpriseTeam.expects(:enabled_for_organization_security_manager?).at_least_once.returns(true)

          params = { advanced_security: "enable_all" }
          err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

          assert_equal(
            "GitHub Advanced Security could not be bulk enabled because the enterprise security managers feature is enabled",
            err_msg
          )
        end
      end

      context "when a blocking security product toggling is in progress" do
        test "it returns an error message" do
          JobStatus.create({
            id: SecurityAnalysisSettingsUpdateJob.job_id(
              @org,
              :secret_scanning_enable_all
            )
          })

          params = { advanced_security: "enable_all" }
          err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

          assert_equal(
            "A change has been made to a configuration at either the enterprise or organization level. Some features under GitHub Advanced Security cannot be enabled or disabled until changes are propagated to all organizations in this enterprise.",
            err_msg
          )
        end
      end

      context "when enabling GHAS would exceed the GHAS license's seat limit" do
        test "it returns an error message" do
          AdvancedSecurityLicense.any_instance.stubs(:seats).returns(15)
          AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(20)

          params = { advanced_security: "enable_all" }
          err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

          assert_equal(
            "GitHub Advanced Security could not be enabled because the parent enterprise #{@biz.name} is using 5 more GitHub Advanced Security licenses than they have purchased.",
            err_msg
          )
        end
      end
    end

    context "when GHAS is being disabled on all repositories" do
      test "it enqueues a SecurityAnalysisSettingsBatchUpdateBusinessJob and returns nil" do
        params = { advanced_security: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsBatchUpdateBusinessJob)
        assert_nil(err_msg)
      end
    end

    context "when GHAS is being enabled on new repositories" do
      test "it configures the business' organizations and returns nil" do
        params = { advanced_security_enabled_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)

        @biz.organizations.each { |org| assert(org.advanced_security_enabled_on_new_repos?) }
        assert_nil(err_msg)
      end

      test "a business policy does not allow GHAS enablement" do
        @biz.stubs(:policy_allows_advanced_security_enablement?).returns(false)

        params = { advanced_security_enabled_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

        assert_equal(
          "GitHub Advanced Security could not be enabled for new repositories because of a policy setting for the organization",
          err_msg
        )
      end

      test "it configures the business' organizations and emits business audit log" do
        assert_performed_audit_entries(count: 1, only: "business_advanced_security.enabled_for_new_repos") do
          params = { advanced_security_enabled_new_repos: "enabled" }
          err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
          perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)
        end
      end

      test "it configures the business' organizations and emits org audit logs" do
        assert_performed_audit_entries(count: @biz.organizations.count, only: "org.advanced_security_enabled_for_new_repos") do
          params = { advanced_security_enabled_new_repos: "enabled" }
          err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
          perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)
        end
      end
    end

    context "when GHAS is being disabled on new repositories" do
      test "it configures the business' organizations and returns nil" do
        # enable first so we can verify the disable actions actually occur
        params = { advanced_security_enabled_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)

        params = { advanced_security_enabled_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)

        @biz.organizations.each { |org| assert(!org.advanced_security_enabled_on_new_repos?) }
        assert_nil(err_msg)
      end
    end

    test "it configures the business' organizations and emits business audit log" do
      params = { advanced_security_enabled_new_repos: "enabled" }
      err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
      perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)

      params = { advanced_security_enabled_new_repos: "disabled" }

      assert_performed_audit_entries(count: 1, only: "business_advanced_security.disabled_for_new_repos") do
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)
      end
    end

    test "it configures the business' organizations and emits org audit logs" do
      params = { advanced_security_enabled_new_repos: "enabled" }
      err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
      perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)

      params = { advanced_security_enabled_new_repos: "disabled" }
      assert_performed_audit_entries(count: @biz.organizations.count, only: "org.advanced_security_disabled_for_new_repos") do
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)
      end
    end
  end

  context "GHAS for enterprise managed users" do
    context "when GHAS is being enabled on all repositories" do
      test "it enqueues a SecurityAnalysisSettingsBatchUpdateBusinessJob and returns nil" do
        params = { advanced_security_user_namespace: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_with(
          job: SecurityAnalysisSettingsBatchUpdateBusinessJob,
          args: [owner: @biz, update_type: :advanced_security_enable_all, actor_id: @admin.id, entity_type: :user],
        )
        assert_nil(err_msg)
      end

      test "it emits business audit log" do
        assert_performed_audit_entries(count: 1, only: "business_advanced_security.user_namespace_repos_enabled") do
          params = { advanced_security_user_namespace: "enable_all" }
          err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
          assert_nil(err_msg)
          perform_enqueued_jobs(only: SecurityAnalysisSettingsBatchUpdateBusinessJob)
        end
      end

      context "when a business policy does not allow GHAS enablement" do
        test "it returns an error message" do
          @biz.stubs(:policy_allows_advanced_security_enablement?).returns(false)

          params = { advanced_security_user_namespace: "enable_all" }
          err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

          assert_equal(
            "GitHub Advanced Security could not be enabled because of a policy setting for the organization",
            err_msg
          )
        end
      end

      context "when a blocking security product toggling is in progress", skip_enterprise: true do
        test "it returns an error message" do
          [:advanced_security_user_namespace_enable_all, :advanced_security_user_namespace_disable_all].each do |blocking_feature|
            j = JobStatus.create({
              id: SecurityAnalysisSettingsUpdateJob.job_id(
                @emu_user,
                blocking_feature
              )
            })

            params = { advanced_security_user_namespace: "enable_all" }
            err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

            assert_equal(
              "A change has been made to a configuration at either the enterprise or organization level. Some features under GitHub Advanced Security cannot be enabled or disabled until changes are propagated to all organizations in this enterprise.",
              err_msg,
              "not equal for #{blocking_feature}"
            )

            j.destroy
          end
        end
      end

      context "when enabling GHAS would exceed the GHAS license's seat limit" do
        test "it returns an error message" do
          AdvancedSecurityLicense.any_instance.stubs(:seats).returns(15)
          AdvancedSecurityLicense.any_instance.stubs(:consumed_seats).returns(20)

          params = { advanced_security_user_namespace: "enable_all" }
          err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

          assert_equal(
            "GitHub Advanced Security could not be enabled because the parent enterprise #{@biz.name} is using 5 more GitHub Advanced Security licenses than they have purchased.",
            err_msg
          )
        end
      end
    end

    context "when GHAS is being disabled on all repositories" do
      test "it enqueues a SecurityAnalysisSettingsBatchUpdateBusinessJob and returns nil" do
        params = { advanced_security_user_namespace: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_jobs(1, only: SecurityAnalysisSettingsBatchUpdateBusinessJob)
        assert_nil(err_msg)
      end

      test "it emits business audit log" do
        assert_performed_audit_entries(count: 1, only: "business_advanced_security.user_namespace_repos_disabled") do
          params = { advanced_security_user_namespace: "disable_all" }
          err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
          assert_nil(err_msg)
          perform_enqueued_jobs(only: SecurityAnalysisSettingsBatchUpdateBusinessJob)
        end
      end
    end

    context "when GHAS is being enabled or disabled for new user namespace repos" do
      test "enabled emits business audit log" do
        assert_performed_audit_entries(count: 1, only: "business_advanced_security.enabled_for_new_user_namespace_repos") do
          params = { advanced_security_enabled_new_user_namespace_repos: "enabled" }
          err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
          assert_nil(err_msg)
          perform_enqueued_jobs(only: SecurityAnalysisSettingsBatchUpdateBusinessJob)
        end
      end

      test "disabled emits business audit log" do
        assert_performed_audit_entries(count: 1, only: "business_advanced_security.disabled_for_new_user_namespace_repos") do
          params = { advanced_security_enabled_new_user_namespace_repos: "disabled" }
          err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
          assert_nil(err_msg)
          perform_enqueued_jobs(only: SecurityAnalysisSettingsBatchUpdateBusinessJob)
        end
      end
    end
  end

  context "Dependabot Alerts" do
    context "when alerts are being enabled on all repositories" do
      test "it configures the business' organizations and returns nil" do
        params = { security_alerts_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)

        assert @biz.security_alerts_enabled_for_new_repos?
        @biz.organizations.each { |org| assert(org.security_alerts_enabled_for_new_repos?) }
        assert_nil(err_msg)
      end
    end

    context "when alerts are being disabled on all repositories" do
      test "it configures the business' organizations and returns nil" do
        @biz.enable_security_alerts_for_new_repos(actor: @admin)
        @biz.organizations.each { |org| org.enable_security_alerts_for_new_repos(actor: @admin) }

        assert @biz.security_alerts_enabled_for_new_repos?
        @biz.organizations.each { |org| assert org.security_alerts_enabled_for_new_repos? }

        params = { security_alerts_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)

        refute @biz.reload.security_alerts_enabled_for_new_repos?
        @biz.organizations.each { |org| refute(org.security_alerts_enabled_for_new_repos?) }
        assert_nil(err_msg)
      end
    end
  end

  context "Secret scanning" do
    context "when secret scanning is being enabled on all repositories" do
      test "it enqueues a SecurityAnalysisSettingsBatchUpdateBusinessJob and returns nil" do
        params = { secret_scanning: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_with(
          job: SecurityAnalysisSettingsBatchUpdateBusinessJob,
          args: [owner: @biz, update_type: :secret_scanning_enable_all, actor_id: @admin.id, entity_type: :organization],
        )
        assert_enqueued_with(
          job: SecurityAnalysisSettingsBatchUpdateBusinessJob,
          args: [owner: @biz, update_type: :secret_scanning_enable_all, actor_id: @admin.id, entity_type: :user],
        )
        assert_nil(err_msg)
      end
    end

    context "when secret scanning is being disabled on all repositories" do
      test "it enqueues a SecurityAnalysisSettingsBatchUpdateBusinessJob and returns nil" do
        params = { secret_scanning: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_with(
          job: SecurityAnalysisSettingsBatchUpdateBusinessJob,
          args: [owner: @biz, update_type: :secret_scanning_disable_all, actor_id: @admin.id, entity_type: :organization],
        )
        assert_enqueued_with(
          job: SecurityAnalysisSettingsBatchUpdateBusinessJob,
          args: [owner: @biz, update_type: :secret_scanning_disable_all, actor_id: @admin.id, entity_type: :user],
        )
        assert_nil(err_msg)
      end
    end

    context "when secret scanning is being enabled on new repositories" do
      test "it configures the business, the business' organizations, and returns nil" do
        params = { secret_scanning_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)
        assert_nil(err_msg)

        assert(SecretScanning::Features::Business::TokenScanning.new(@biz).secret_scanning_enabled_for_new_repos?)
        @biz.organizations.each do |org|
          assert(SecretScanning::Features::Org::TokenScanning.new(org).secret_scanning_enabled_for_new_repos?)
        end

        unless GitHub.enterprise?
          assert(SecretScanning::Features::User::TokenScanning.new(@emu_user).secret_scanning_enabled_for_new_repos?)
          assert(SecretScanning::Features::User::TokenScanning.new(@emu_user2).secret_scanning_enabled_for_new_repos?)
        end
      end

      context "when a business policy does not allow GHAS enablement" do
        test "it still allows enabling secret scanning on new repos" do
          @biz.stubs(:policy_allows_advanced_security_enablement?).returns(false)

          params = { secret_scanning_new_repos: "enabled" }
          err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

          assert_enqueued_jobs(1, only: UpdateBusinessSecurityFeatureForNewReposJob)
          assert_nil err_msg
        end
      end
    end

    context "when secret scanning is being disabled on new repositories" do
      test "it configures the business, the business' organizations, and returns nil" do
        # first turn everything on
        params = { secret_scanning_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)
        assert_nil(err_msg)

        params = { secret_scanning_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)
        assert_nil(err_msg)

        refute SecretScanning::Features::Business::TokenScanning.new(@biz).secret_scanning_enabled_for_new_repos?
        @biz.organizations.each do |org|
          refute SecretScanning::Features::Org::TokenScanning.new(org).secret_scanning_enabled_for_new_repos?
        end

        unless GitHub.enterprise?
          refute SecretScanning::Features::User::TokenScanning.new(@emu_user).secret_scanning_enabled_for_new_repos?
          refute SecretScanning::Features::User::TokenScanning.new(@emu_user2).secret_scanning_enabled_for_new_repos?
        end
      end
    end
  end

  context "Secret scanning validity checks" do
    context "when secret scanning validity checks is being enabled on all repositories" do
      test "it enqueues a SecurityAnalysisSettingsBatchUpdateBusinessJob and returns nil" do
        SecretScanning::Features::Business::ValidityChecks.any_instance.stubs(:feature_available?).returns(true)
        SecretScanning::Features::Org::ValidityChecks.any_instance.stubs(:feature_available?).returns(true)

        params = { secret_scanning_validity_checks: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_with(
          job: SecurityAnalysisSettingsBatchUpdateBusinessJob,
          args: [owner: @biz, update_type: :secret_scanning_validity_checks_enable_all, actor_id: @admin.id, entity_type: :organization],
        )
        assert_enqueued_with(
          job: SecurityAnalysisSettingsBatchUpdateBusinessJob,
          args: [owner: @biz, update_type: :secret_scanning_validity_checks_enable_all, actor_id: @admin.id, entity_type: :user],
        )

        assert_nil(err_msg)
      end
    end

    context "when secret scanning validity checks is being disabled on all repositories" do
      test "it enqueues a SecurityAnalysisSettingsBatchUpdateBusinessJob and returns nil" do
        params = { secret_scanning_validity_checks: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_with(
          job: SecurityAnalysisSettingsBatchUpdateBusinessJob,
          args: [owner: @biz, update_type: :secret_scanning_validity_checks_disable_all, actor_id: @admin.id, entity_type: :organization],
        )
        assert_enqueued_with(
          job: SecurityAnalysisSettingsBatchUpdateBusinessJob,
          args: [owner: @biz, update_type: :secret_scanning_validity_checks_disable_all, actor_id: @admin.id, entity_type: :user],
        )

        assert_nil(err_msg)
      end
    end

    context "when secret scanning validity checks is being enabled on new repositories" do
      test "it configures the business, the business' organizations, and returns nil" do
        SecretScanning::Features::Business::ValidityChecks.any_instance.stubs(:feature_available?).returns(true)
        SecretScanning::Features::Org::ValidityChecks.any_instance.stubs(:feature_available?).returns(true)

        params = { secret_scanning_validity_checks_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)
        assert_nil(err_msg)

        assert(SecretScanning::Features::Business::ValidityChecks.new(@biz).enabled_for_new_repos?)
        @biz.organizations.each { |org| assert(SecretScanning::Features::Org::ValidityChecks.new(org).enabled_for_new_repos?) }

        SecretScanning::Features::User::ValidityChecks.any_instance.stubs(:feature_available?).returns(true)
        unless GitHub.enterprise?
          assert(SecretScanning::Features::User::ValidityChecks.new(@emu_user).enabled_for_new_repos?)
          assert(SecretScanning::Features::User::ValidityChecks.new(@emu_user2).enabled_for_new_repos?)
        end
      end
    end

    context "when secret scanning validity checks is being disabled on new repositories" do
      test "it configures the business, the business' organizations, and returns nil" do
        # Enable it first
        params = { secret_scanning_validity_checks_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)
        assert_nil(err_msg)

        params = { secret_scanning_validity_checks_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)

        refute SecretScanning::Features::Business::ValidityChecks.new(@biz).enabled_for_new_repos?
        @biz.organizations.each { |org| refute SecretScanning::Features::Org::ValidityChecks.new(org).enabled_for_new_repos? }
        assert_nil(err_msg)

        unless GitHub.enterprise?
          refute SecretScanning::Features::User::ValidityChecks.new(@emu_user).enabled_for_new_repos?
          refute SecretScanning::Features::User::ValidityChecks.new(@emu_user2).enabled_for_new_repos?
        end
      end
    end
  end

  context "Secret scanning push protection" do
    context "when secret scanning push protection is being enabled on all repositories" do
      test "it enqueues a SecurityAnalysisSettingsBatchUpdateBusinessJob and returns nil" do
        params = { secret_scanning_push_protection: "enable_all" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_with(
          job: SecurityAnalysisSettingsBatchUpdateBusinessJob,
          args: [owner: @biz, update_type: :secret_scanning_push_protection_enable_all, actor_id: @admin.id, entity_type: :organization],
        )
        assert_enqueued_with(
          job: SecurityAnalysisSettingsBatchUpdateBusinessJob,
          args: [owner: @biz, update_type: :secret_scanning_push_protection_enable_all, actor_id: @admin.id, entity_type: :user],
        )

        assert_nil(err_msg)
      end
    end

    context "when secret scanning push protection is being disabled on all repositories" do
      test "it enqueues a SecurityAnalysisSettingsBatchUpdateBusinessJob and returns nil" do
        params = { secret_scanning_push_protection: "disable_all" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

        assert_enqueued_with(
          job: SecurityAnalysisSettingsBatchUpdateBusinessJob,
          args: [owner: @biz, update_type: :secret_scanning_push_protection_disable_all, actor_id: @admin.id, entity_type: :organization],
        )
        assert_enqueued_with(
          job: SecurityAnalysisSettingsBatchUpdateBusinessJob,
          args: [owner: @biz, update_type: :secret_scanning_push_protection_disable_all, actor_id: @admin.id, entity_type: :user],
        )

        assert_nil(err_msg)
      end
    end

    context "when secret scanning push protection is being enabled on new repositories" do
      test "it configures the business, the business' organizations, and returns nil" do
        params = { secret_scanning_push_protection_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)
        assert_nil(err_msg)

        assert(SecretScanning::Features::Business::PushProtection.new(@biz).enabled_for_new_repos?)
        @biz.organizations.each { |org| assert(SecretScanning::Features::Org::PushProtection.new(org).enabled_for_new_repos?) }

        unless GitHub.enterprise?
          assert(SecretScanning::Features::User::PushProtection.new(@emu_user).enabled_for_new_repos?)
          assert(SecretScanning::Features::User::PushProtection.new(@emu_user2).enabled_for_new_repos?)
        end
      end
    end

    context "when secret scanning push protection is being disabled on new repositories" do
      test "it configures the business, the business' organizations, and returns nil" do
        # Enable it first
        params = { secret_scanning_push_protection_new_repos: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)
        assert_nil(err_msg)

        params = { secret_scanning_push_protection_new_repos: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)

        refute SecretScanning::Features::Business::PushProtection.new(@biz).enabled_for_new_repos?
        @biz.organizations.each { |org| refute SecretScanning::Features::Org::PushProtection.new(org).enabled_for_new_repos? }
        assert_nil(err_msg)

        unless GitHub.enterprise?
          refute SecretScanning::Features::User::PushProtection.new(@emu_user).enabled_for_new_repos?
          refute SecretScanning::Features::User::PushProtection.new(@emu_user2).enabled_for_new_repos?
        end
      end
    end

    context "when secret scanning push protection custom message status is being enabled" do
      test "it configures the business and returns nil" do
        params = { push_protection_custom_message_status: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

        assert(SecretScanning::Features::Business::PushProtection.new(@biz).custom_message_enabled?)
        assert_nil(err_msg)
      end

      test "it enables custom message for all orgs under the business" do
        params = { push_protection_custom_message_status: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)

        assert(SecretScanning::Features::Business::PushProtection.new(@biz).custom_message_enabled?)
        assert(SecretScanning::Features::Org::PushProtection.new(@org).custom_message_enabled?)
        assert(SecretScanning::Features::Org::PushProtection.new(@org2).custom_message_enabled?)
        assert_nil(err_msg)
      end

      test "it updates the custom message for all orgs under the business when enabled" do
        biz_settings = SecretScanning::Features::Business::PushProtection.new(@biz)
        org_settings = SecretScanning::Features::Org::PushProtection.new(@org)
        org2_settings = SecretScanning::Features::Org::PushProtection.new(@org2)
        biz_settings.disable_custom_message(actor: @admin)
        org_settings.disable_custom_message(actor: @admin)
        org2_settings.disable_custom_message(actor: @admin)
        biz_link = "https://mycustommessage.com"
        org_different_link = "https://myorganizationcustommessage.com"
        @biz.set_push_protection_custom_message(biz_link, @admin)
        @org.set_push_protection_custom_message(biz_link, @admin)
        @org2.set_push_protection_custom_message(org_different_link, @admin)

        params = { push_protection_custom_message_status: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)

        assert biz_settings.custom_message_enabled?
        assert org_settings.custom_message_enabled?
        assert org2_settings.custom_message_enabled?
        assert_equal biz_link, @biz.get_push_protection_custom_message
        assert_equal biz_link, @org.get_push_protection_custom_message
        assert_equal org_different_link, @org2.get_push_protection_custom_message
        assert_nil(err_msg)
      end
    end

    context "when secret scanning push protection custom message status is being disabled" do
      test "it configures the business and returns nil" do
        params = { push_protection_custom_message_status: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

        assert(!SecretScanning::Features::Business::PushProtection.new(@biz).custom_message_enabled?)
        assert_nil(err_msg)
      end

      test "it disables custom messages for all orgs under the business that had the same message as the business" do
        biz_settings = SecretScanning::Features::Business::PushProtection.new(@biz)
        org_settings = SecretScanning::Features::Org::PushProtection.new(@org)
        org2_settings = SecretScanning::Features::Org::PushProtection.new(@org2)
        biz_settings.enable_custom_message(actor: @admin)
        org_settings.enable_custom_message(actor: @admin)
        org2_settings.enable_custom_message(actor: @admin)
        biz_link = "https://mycustommessage.com"
        org_different_link = "https://myorganizationcustommessage.com"
        @biz.set_push_protection_custom_message(biz_link, @admin)
        @org.set_push_protection_custom_message(biz_link, @admin)
        @org2.set_push_protection_custom_message(org_different_link, @admin)

        params = { push_protection_custom_message_status: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)

        refute biz_settings.custom_message_enabled?
        refute org_settings.custom_message_enabled?
        assert org2_settings.custom_message_enabled?
        assert_equal biz_link, @biz.get_push_protection_custom_message
        assert_equal biz_link, @org.get_push_protection_custom_message
        assert_equal org_different_link, @org2.get_push_protection_custom_message
        assert_nil(err_msg)
      end
    end

    context "when secret scanning push protection custom message status is being modified" do
      test "it sets the custom message and returns nil" do
        expected = "https://example.com"
        params = { push_protection_custom_message: expected }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)
        @biz.reload

        assert_equal(expected, @biz.get_push_protection_custom_message)
        assert_nil(err_msg)
      end

      context "when the custom message is not a URL" do
        test "it returns an error message" do
          params = { push_protection_custom_message: "This is not a URL." }
          err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
          perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)

          assert_equal("Input should be a URL", err_msg)
        end
      end

      test "it updates the url for orgs that had the same previous message" do
        biz_settings = SecretScanning::Features::Business::PushProtection.new(@biz)
        org_settings = SecretScanning::Features::Org::PushProtection.new(@org)
        org2_settings = SecretScanning::Features::Org::PushProtection.new(@org2)
        biz_settings.enable_custom_message(actor: @admin)
        org_settings.disable_custom_message(actor: @admin)
        org2_settings.disable_custom_message(actor: @admin)
        biz_link = "https://mycustommessage.com"
        org_different_link = "https://myorganizationcustommessage.com"
        @biz.set_push_protection_custom_message(biz_link, @admin)
        @org.set_push_protection_custom_message(biz_link, @admin)
        @org2.set_push_protection_custom_message(org_different_link, @admin)

        new_biz_link = "https://example.com"
        params = { push_protection_custom_message: new_biz_link }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: UpdateBusinessSecurityFeatureForNewReposJob)
        @biz.reload

        assert biz_settings.custom_message_enabled?
        refute org_settings.custom_message_enabled?
        refute org2_settings.custom_message_enabled?
        assert_equal new_biz_link, @biz.get_push_protection_custom_message
        assert_equal new_biz_link, @org.get_push_protection_custom_message
        assert_equal org_different_link, @org2.get_push_protection_custom_message
        assert_nil(err_msg)
      end
    end
  end

  context "Secret scanning validity checks" do
    test "it enqueues a job when validity checks are enabled" do
      params = { secret_scanning_validity_checks: "enabled" }
      err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

      num_queued = GitHub.enterprise? ? 0 : 1
      assert_enqueued_jobs(num_queued, only: PublishSecretScanningEnablementChangeJob)
      assert_nil(err_msg)
    end
    test "it enqueues a job when validity checks are disabled" do
      params = { secret_scanning_validity_checks: "disabled" }
      err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

      num_queued = GitHub.enterprise? ? 0 : 1
      assert_enqueued_jobs(num_queued, only: PublishSecretScanningEnablementChangeJob)
      assert_nil(err_msg)
    end
    test "it does not enqueue a job if the param for validity checks is nil" do
      params = { secret_scanning_validity_checks: nil }
      err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

      assert_enqueued_jobs(0, only: PublishSecretScanningEnablementChangeJob)
      assert_nil(err_msg)
    end

    test "instruments an audit log event when validity checks are enabled", skip_enterprise: true do
      event_name = "business_secret_scanning_automatic_validity_checks.enabled"

      events = assert_performed_audit_entries(count: 1, only: event_name) do
        params = { secret_scanning_validity_checks: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: PublishSecretScanningEnablementChangeJob)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: event_name,
        user: @admin.login,
        business: @biz.name
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instuments an audit log event when automatic validity checks are disabled", skip_enterprise: true do
      event_name = "business_secret_scanning_automatic_validity_checks.disabled"
      events = assert_performed_audit_entries(count: 1, only: event_name) do
        params = { secret_scanning_validity_checks: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: PublishSecretScanningEnablementChangeJob)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: event_name,
        user: @admin.login,
        business: @biz.name
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  context "Secret scanning generic secrets", skip_enterprise: true do
    test "it enqueues a job when generic_secrets are enabled" do
      params = { secret_scanning_generic_secrets: "enabled" }
      err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

      num_queued = GitHub.enterprise? ? 0 : 1
      assert_enqueued_jobs(num_queued, only: PublishSecretScanningEnablementChangeJob)
      assert_nil(err_msg)
    end
    test "it enqueues a job when generic secrets are disabled" do
      params = { secret_scanning_generic_secrets: "disabled" }
      err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

      num_queued = GitHub.enterprise? ? 0 : 1
      assert_enqueued_jobs(num_queued, only: PublishSecretScanningEnablementChangeJob)
      assert_nil(err_msg)
    end
    test "it does not enqueue a job if the param for generic secrets is nil" do
      params = { secret_scanning_generic_secrets: nil }
      err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

      assert_enqueued_jobs(0, only: PublishSecretScanningEnablementChangeJob)
      assert_nil(err_msg)
    end

    test "instruments an audit log event when generic secrets are enabled", skip_enterprise: true do
      event_name = "business_secret_scanning_generic_secrets.enabled"

      events = assert_performed_audit_entries(count: 1, only: event_name) do
        params = { secret_scanning_generic_secrets: "enabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: PublishSecretScanningEnablementChangeJob)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: event_name,
        user: @admin.login,
        business: @biz.name
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instuments an audit log event when generic secrets are disabled", skip_enterprise: true do
      event_name = "business_secret_scanning_generic_secrets.disabled"
      events = assert_performed_audit_entries(count: 1, only: event_name) do
        params = { secret_scanning_generic_secrets: "disabled" }
        err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
        perform_enqueued_jobs(only: PublishSecretScanningEnablementChangeJob)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: event_name,
        user: @admin.login,
        business: @biz.name
      }

      assert_subset_hash expected_payload, events.first
    end
  end
end
