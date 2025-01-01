# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependency_graph_helpers"
require "test_helpers/private_token_scanning_test_helper"

class RepositorySecurityCenterDependencyTest < GitHub::TestCase

  include PrivateTokenScanningTestHelper
  include HydroMessageJobTestHelpers
  include HydroTestHelpers
  include GitHub::LoggerHelper
  include DogstatsTestHelpers
  include DependabotAlertHelpers
  include DependencyGraphHelpers
  include DependabotAlertsEnterpriseEnablementHelper

  fixtures do
    @business = create(:business)

    @owner = create(:user)
    @org = create(:organization, admin: @owner, business: @business)
    @repo = create(:repository, owner: @org)
    @private_repo = create(:private_repository, owner: @org)
    # configure code scanning integration; we use it to query check_suites
    make_trusted_oauth_apps_owner
    @integration = create(:code_scanning_integration)
    @python = create(:language, language_name: create(:language_name, name: "Python"))
    @ruby = create(:language, language_name: create(:language_name, name: "Ruby"))
    @private_repo.update(languages: [@ruby])
    @repo.update(languages: [@python])
  end

  setup do
    GitHub.stubs(:code_scanning_enabled?).returns(true)
    SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(true)
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    @repo.enable_advanced_security!(actor: @owner) if GitHub.enterprise?
    GitHub::Turboscan.stubs(:severities_for_org).returns(Twirp::ClientResp.new(data: Turboscan::Proto::SeveritiesForOrgResponse.new))
    disable_feature_flag(:security_center_reconciliation_ignore_failure)

    RepositorySecurityCenterStatus.destroy_all
  end

  context "update_status_code_scanning" do
    test "Unknown feature type emits Failbot report" do
      assert_raises ::Repository::SecurityCenterDependency::UnknownSecurityFeatureStatusError do
        @private_repo.security_center_notify("not_a_feature", source_event: "security_center.test")
      end
      message = GitHub.enterprise? ? Failbot.reports.last["message"] : Failbot.reports.last["exception_detail"].first["value"]
      assert_equal "Could not update security center for feature not_a_feature", message
    end

    test "update unenrolled status for repo" do
      # Stub methods that code_scanning_security_center_status depends on
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(false)
      Repository.any_instance.stubs(:code_scanning_enabled?).returns(false)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)

      @repo.security_center_notify("code_scanning", source_event: "security_center.test")

      assert_equal "not_enrolled", T.must(RepositorySecurityCenterStatus.first).scanning_status
    end

    test "update enrolled status for repo" do
      # Stub methods that code_scanning_security_center_status depends on
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(true)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(true)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)

      @repo.security_center_notify("code_scanning", source_event: "security_center.test")

      assert_equal "enrolled", T.must(RepositorySecurityCenterStatus.first).scanning_status
    end

    test "update status for repo with existing status present" do
      create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: @repo)

      # Stub methods that code_scanning_security_center_status depends on
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(true)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(true)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)

      @repo.security_center_notify("code_scanning", source_event: "security_center.test")

      assert_equal "enrolled", T.must(RepositorySecurityCenterStatus.first).scanning_status
    end

    test "update status for repo with existing status missing latest" do
      create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: @repo)

      # Stub methods that code_scanning_security_center_status depends on
      Repository.any_instance.stubs(:code_scanning_analysis_exists_on_default_ref?).returns(true)
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(true)
      Repository.any_instance.stubs(:code_scanning_latest_analysis).returns(nil)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(true)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)

      @repo.security_center_notify("code_scanning", source_event: "security_center.test")

      assert_equal "enrolled", T.must(RepositorySecurityCenterStatus.first).scanning_status
    end

    test "update status for private repo with GHAS disabled" do
      create(:repository_security_center_status, :code_scanning, :enrolled, repository: @private_repo)

      @private_repo.disable_advanced_security!(actor: @owner)

      Turbocassette.use("code-scanning/counts-missing-latest") do
        @private_repo.security_center_notify("code_scanning", source_event: "security_center.test")
      end

      assert_equal "not_enrolled", T.must(RepositorySecurityCenterStatus.first).scanning_status
    end

    test "update status for public repo with GHAS disabled", enterprise_only: true do
      create(:repository_security_center_status, :code_scanning, :enrolled, repository: @repo)

      @repo.disable_advanced_security!(actor: @owner)

      Turbocassette.use("code-scanning/counts-present") do
        @repo.security_center_notify("code_scanning", source_event: "security_center.test")
      end

      # Code scanning is available for public repos in dotcom even if GHAS is disabled.
      # In GHES we treat public repos like private repos. GHAS is required.
      if GitHub.enterprise?
        assert_equal "not_enrolled", T.must(RepositorySecurityCenterStatus.first).scanning_status
      else
        assert_equal "enrolled", T.must(RepositorySecurityCenterStatus.first).scanning_status
      end
    end

    test "update status for repo that returns unexpected value" do
      Repository.any_instance.expects(:code_scanning_security_center_status).at_least_once.returns(nil)

      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(true)
      assert_raises ::Repository::SecurityCenterDependency::UnknownSecurityFeatureStatusError do
        @repo.security_center_notify("code_scanning", source_event: "security_center.test")
      end
      status = RepositorySecurityCenterStatus.find_by(feature_type: "code_scanning")
      assert_nil status
    end
  end

  context "update_status_secret_scanning" do
    test "status not set if gist" do
      assert_nil RepositorySecurityCenterStatus.first

      gist = GistHelpers.generate(user: @owner, contents: [{ name: "1", value: "random content" }], public: true)
      gist_oid = gist.files.first.oid
      assert_enqueued_jobs 1, only: GistPushJob do
        assert gist.update!(contents: [{ name: "1", value: "an update", oid: gist_oid }])
      end

      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_counts).returns(TokenScanningCount.new(1))

      assert_nil RepositorySecurityCenterStatus.first
      assert_nil RepositorySecurityCenterConfig.first
    end

    test "public non-enterprise repo without SS enabled creates a not_enrolled status", skip_enterprise: true do
      assert_nil RepositorySecurityCenterStatus.first
      repo = create(:public_repository, owner: @org)
      repo.security_center_notify("secret_scanning", source_event: "security_center.test")
      status = RepositorySecurityCenterStatus.first
      assert_equal "not_enrolled", T.must(status).scanning_status
    end

    test "repo toggle private to public updates status" do
      repo = create(:private_repository, owner: @org)
      create(:repository_security_center_config, repository: repo)
      create(:repository_security_center_status, :secret_scanning, :not_enrolled, repository: repo)

      reset_hydro
      perform_enqueued_hydro_jobs(only: [HydroSecretScanningRepositoryVisibilityJob], allowed_primary_query_count: 2) do
        perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { repo.toggle_visibility(actor: @owner) }
      end

      # stub this to 0 (its value throughout test) to prevent a flaky queries to GitHub.kv
      Repository::CodeScanningDependency::AnalysisRevision.any_instance.stubs(:count).returns(0)

      publish_and_consume_security_center_update_event(repo.id) do
        process_messages!(allowed_primary_query_count: 3)
      end

      status = RepositorySecurityCenterStatus.find_by(feature_type: "secret_scanning")
      refute_nil status
      assert_equal "not_enrolled", status&.scanning_status
    end

    test "repo toggle public to private with secret scanning enabled updates status", skip_enterprise: true do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)

      repo = create(:public_repository, owner: @org)

      token = create(:token_scan_result, repository: repo)
      location = create(:token_scan_result_location,
        repository_id: repo.id,
        token_scan_result_id: token.id,
      )
      token.update(first_location_id: location.id)
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_counts).returns(TokenScanningCount.new(1))

      reset_hydro
      perform_enqueued_hydro_jobs(only: [HydroSecretScanningRepositoryVisibilityJob], allowed_primary_query_count: 2) do
        perform_enqueued_hydro_jobs(publisher: GitHub.hydro_publisher, only: [SecurityCenter::HydroSecretScanningFeatureToggledJob]) do
          perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { repo.toggle_visibility(actor: @owner) }
        end
      end

      status = RepositorySecurityCenterStatus.find_by(feature_type: "secret_scanning")
      refute_nil status
      assert_equal "enrolled", status&.scanning_status
    end

    test "dependabot_alerts is updated for non-GHAS org repo" do
      SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)

      repo = create(:repository, owner: @org)

      repo.security_center_notify("dependabot_alerts", source_event: "security_center.test")
      refute_nil repo.repository_security_center_statuses.where(feature_type: "dependabot_alerts").first
    end
  end

  context "telemetry" do
    context "deviation tracking" do
      [
        SecurityCenter::OwnerReconciliationJob::RECONCILIATION_EVENT,
        SecurityCenter::BusinessReconciliationJob::RECONCILIATION_EVENT
      ].each do |event|
        test "logs deviation for repo config discrepancy with #{event} event" do
          create(:repository_security_center_config, repository: @repo, name: SecureRandom.uuid)
          config = @repo.repository_security_center_config

          deviations = GitHub.enterprise? ? %w(name) : %w(ghas_enabled name)

          assert_logged(
            Body: "Deviation detected in repository config",
            "gh.security_center.feature_type": "repository_configuration",
            "gh.security_center.deviations": deviations,
            "gh.repo.id": @repo.id,
            "gh.repo.name": @repo.name,
            "gh.owner.id": @repo.owner_id,
            "gh.owner.login": @repo.owner_display_login,
            "gh.owner.type": @repo.owner_type,
            "gh.business.id": @repo.business_id,
            "gh.org.id": @repo.owner_id,
            "gh.org.login": @repo.owner_display_login,
            "gh.security_center.source_event": event,
          ) do
            @repo.security_center_notify("repository_configuration", source_event: event)
          end

          assert_dogstats_increment("security_center.reconciliation.deviation.count", tags: [
            "feature_type:repository_configuration",
            "source_event:#{event}",
            "deviation:name",
            ("deviation:ghas_enabled" unless GitHub.enterprise?),
          ].compact)
        end

        test "logs deviation for missing repo config with #{event} event" do
          @repo.repository_security_center_config&.destroy

          assert_logged(
            Body: "Deviation detected in repository config",
            "gh.security_center.feature_type": "repository_configuration",
            "gh.security_center.deviations": %w(record_missing),
            "gh.repo.id": @repo.id,
            "gh.repo.name": @repo.name,
            "gh.owner.id": @repo.owner_id,
            "gh.owner.login": @repo.owner_display_login,
            "gh.owner.type": @repo.owner_type,
            "gh.business.id": @repo.business_id,
            "gh.org.id": @repo.owner_id,
            "gh.org.login": @repo.owner_display_login,
            "gh.security_center.source_event": event,
          ) do
            @repo.security_center_notify("repository_configuration", source_event: event)
          end

          assert_dogstats_increment("security_center.reconciliation.deviation.count", tags: [
            "feature_type:repository_configuration",
            "source_event:#{event}",
            "deviation:record_missing",
          ])
        end

        test "logs deviation for feature status discrepancy with #{event} event" do
          create(:repository_security_center_config, repository: @repo)

          create(:repository_security_center_status,
            repository: @repo, feature_type: "secret_scanning", scanning_status: "failed")
          status = @repo.security_center_status_for_feature("secret_scanning")
          @repo.stubs(:secret_scanning_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))

          assert_logged(
            Body: "Deviation detected in feature status",
            "gh.security_center.feature_type": "secret_scanning",
            "gh.security_center.deviations": %w(scanning_status),
            "gh.repo.id": @repo.id,
            "gh.repo.name": @repo.name,
            "gh.owner.id": @repo.owner_id,
            "gh.owner.login": @repo.owner_display_login,
            "gh.business.id": @repo.business_id,
            "gh.org.id": @repo.owner_id,
            "gh.org.login": @repo.owner_display_login,
            "gh.security_center.source_event": event,
          ) do
            @repo.security_center_notify("secret_scanning", source_event: event)
          end

          assert_dogstats_increment("security_center.reconciliation.deviation.count", tags: [
            "feature_type:secret_scanning",
            "source_event:#{event}",
            "deviation:scanning_status",
          ])
        end

        test "logs deviation for missing feature status with #{event} event" do
          create(:repository_security_center_config, repository: @repo)

          @repo.stubs(:secret_scanning_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))

          assert_logged(
            Body: "Deviation detected in feature status",
            "gh.security_center.feature_type": "secret_scanning",
            "gh.security_center.deviations": %w(record_missing),
            "gh.repo.id": @repo.id,
            "gh.repo.name": @repo.name,
            "gh.owner.id": @repo.owner_id,
            "gh.owner.login": @repo.owner_display_login,
            "gh.business.id": @repo.business_id,
            "gh.org.id": @repo.owner_id,
            "gh.org.login": @repo.owner_display_login,
            "gh.security_center.source_event": event,
          ) do
            @repo.security_center_notify("secret_scanning", source_event: event)
          end

          assert_dogstats_increment("security_center.reconciliation.deviation.count", tags: [
            "feature_type:secret_scanning",
            "source_event:#{event}",
            "deviation:record_missing",
          ])
        end

        test "logs deviation for subfeature status discrepancy with #{event} event" do
          create(:repository_security_center_config, repository: @repo)

          create(:repository_security_center_status, repository: @repo,
            feature_type: "secret_scanning", scanning_status: "enrolled")
          @repo.stubs(:secret_scanning_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))

          create(:repository_security_center_status, repository: @repo,
            feature_type: "secret_scanning_push_protection", scanning_status: "not_enrolled")
          status = @repo.security_center_status_for_feature("secret_scanning_push_protection")
          @repo.stubs(:push_protection_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))

          assert_logged(
            Body: "Deviation detected in feature status",
            "gh.security_center.feature_type": "secret_scanning_push_protection",
            "gh.security_center.deviations": %w(scanning_status),
            "gh.repo.id": @repo.id,
            "gh.repo.name": @repo.name,
            "gh.owner.id": @repo.owner_id,
            "gh.owner.login": @repo.owner_display_login,
            "gh.business.id": @repo.business_id,
            "gh.org.id": @repo.owner_id,
            "gh.org.login": @repo.owner_display_login,
            "gh.security_center.source_event": event,
          ) do
            @repo.security_center_notify("secret_scanning", source_event: event)
          end

          assert_dogstats_increment("security_center.reconciliation.deviation.count", tags: [
            "feature_type:secret_scanning_push_protection",
            "source_event:#{event}",
            "deviation:scanning_status",
          ])
        end

        test "logs deviation for missing subfeature status with #{event} event" do
          create(:repository_security_center_config, repository: @repo)

          create(:repository_security_center_status, repository: @repo,
            feature_type: "secret_scanning", scanning_status: "enrolled")
          @repo.stubs(:secret_scanning_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))

          @repo.stubs(:push_protection_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))

          assert_logged(
            Body: "Deviation detected in feature status",
            "gh.security_center.feature_type": "secret_scanning_push_protection",
            "gh.security_center.deviations": %w(record_missing),
            "gh.repo.id": @repo.id,
            "gh.repo.name": @repo.name,
            "gh.owner.id": @repo.owner_id,
            "gh.owner.login": @repo.owner_display_login,
            "gh.business.id": @repo.business_id,
            "gh.org.id": @repo.owner_id,
            "gh.org.login": @repo.owner_display_login,
            "gh.security_center.source_event": event,
          ) do
            @repo.security_center_notify("secret_scanning", source_event: event)
          end

          assert_dogstats_increment("security_center.reconciliation.deviation.count", tags: [
            "feature_type:secret_scanning_push_protection",
            "source_event:#{event}",
            "deviation:record_missing",
          ])
        end
      end

      test "does not log deviation on configs table for non reconciliation event" do
        @repo.repository_security_center_config&.destroy
        @repo.security_center_notify("repository_configuration", source_event: "random_event")
        refute_dogstats_increment("security_center.reconciliation.deviation.count")
      end

      test "does not log deviation on statuses table for non reconciliation event" do
        create(:repository_security_center_config, repository: @repo)
        @repo.stubs(:secret_scanning_security_center_status)
          .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))
        @repo.security_center_notify("secret_scanning", source_event: "random_event")
        refute_dogstats_increment("security_center.reconciliation.deviation.count")
      end
    end
  end

  context "dependabot subfeatures" do
    test "dependabot security updates are enabled" do
      GitHub.stubs(:ghe_content_analysis_enabled?).returns(true) if GitHub.enterprise?
      GitHub.stubs(:dependency_graph_enabled?).returns(true) if GitHub.enterprise?

      SecurityProduct::VulnerabilityUpdates.new(@repo).enable(actor: @owner)

      @repo.security_center_notify(SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS, source_event: "security_center.test")

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      assert statuses.any? { |s| s.feature_type == "dependabot_alerts" }
      assert statuses.any? { |s| s.feature_type == "dependabot_security_updates" && s.scanning_status == "enrolled" }
    end

    test "dependabot security updates are not enabled" do
      GitHub.stubs(:ghe_content_analysis_enabled?).returns(true) if GitHub.enterprise?
      GitHub.stubs(:dependency_graph_enabled?).returns(true) if GitHub.enterprise?

      SecurityProduct::VulnerabilityUpdates.new(@repo).disable(actor: @owner)

      @repo.security_center_notify(SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS, source_event: "security_center.test")

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      assert statuses.any? { |s| s.feature_type == "dependabot_alerts" }
      assert statuses.any? { |s| s.feature_type == "dependabot_security_updates" && s.scanning_status == "not_enrolled" }
    end

    test "update security updates only" do
      GitHub.stubs(:ghe_content_analysis_enabled?).returns(true) if GitHub.enterprise?
      GitHub.stubs(:dependency_graph_enabled?).returns(true) if GitHub.enterprise?

      SecurityProduct::VulnerabilityUpdates.new(@repo).enable(actor: @owner)

      @repo.security_center_notify(:dependabot_security_updates, source_event: "security_center.test")

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      refute statuses.any? { |s| s.feature_type == "dependabot_alerts" }
      assert statuses.any? { |s| s.feature_type == "dependabot_security_updates" && s.scanning_status == "enrolled" }
    end

    test "subfeatures are not updated if flag is false" do
      @repo.security_center_notify(SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS, source_event: "security_center.test", skip_subfeature_updates: true)

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      assert statuses.any? { |s| s.feature_type == "dependabot_alerts" }
      assert statuses.none? { |s| s.feature_type == "dependabot_security_updates" }
    end
  end

  context "code scanning subfeatures" do
    test "code scanning annotations is enabled" do
      check_suite = create(:check_suite, repository: @repo, github_app: @integration)
      code_scanning_check_suite = create(:code_scanning_check_suite, repository: @repo, check_suite: check_suite)

      # Stub methods that code_scanning_security_center_status depends on
      Repository.any_instance.stubs(:code_scanning_analysis_exists_on_default_ref?).returns(true)
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(true)
      Repository.any_instance.stubs(:code_scanning_open_alerts_count_by_severity).returns({ "critical" => 1 })
      Repository.any_instance.stubs(:code_scanning_latest_analysis).returns({ "seconds" => 0 })
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(true)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)

      @repo.security_center_notify("code_scanning", source_event: "security_center.test")

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      assert statuses.any? { |s| s.feature_type == "code_scanning" && s.scanning_status == "enrolled"  }
      assert statuses.any? { |s| s.feature_type == "code_scanning_pr_reviews" && s.scanning_status == "enrolled" }
      assert statuses.any? { |s| s.feature_type == "code_scanning_auto_codeql" && s.scanning_status == "enrolled" }
    end

    test "code scanning annotations is not enabled" do
      # Stub methods that code_scanning_security_center_status depends on
      Repository.any_instance.stubs(:code_scanning_analysis_exists_on_default_ref?).returns(false)
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(false)
      Repository.any_instance.stubs(:code_scanning_enabled?).returns(false)
      Repository.any_instance.stubs(:code_scanning_latest_analysis).returns({ "seconds" => 0 })
      Repository.any_instance.stubs(:code_scanning_analysis_exists_on_recent_pr?).returns(false)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)
      CodeScanning::Status.stubs(:validate_prerequisites).returns(nil)

      @repo.security_center_notify("code_scanning", source_event: "security_center.test")

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      assert statuses.any? { |s| s.feature_type == "code_scanning" && s.scanning_status == "not_enrolled"  }
      assert statuses.any? { |s| s.feature_type == "code_scanning_pr_reviews" && s.scanning_status == "not_enrolled" }
      assert statuses.any? { |s| s.feature_type == "code_scanning_auto_codeql" && s.scanning_status == "eligible" }
    end

    test "update code scanning annotations only" do
      check_suite = create(:check_suite, repository: @repo, github_app: @integration)
      code_scanning_check_suite = create(:code_scanning_check_suite, repository: @repo, check_suite: check_suite)

      # Stub methods that code_scanning_security_center_status depends on
      Repository.any_instance.stubs(:code_scanning_analysis_exists_on_default_ref?).returns(true)
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(true)
      Repository.any_instance.stubs(:code_scanning_open_alerts_count_by_severity).returns({ "critical" => 1 })
      Repository.any_instance.stubs(:code_scanning_latest_analysis).returns({ "seconds" => 0 })
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(true)

      @repo.security_center_notify(:code_scanning_pr_reviews, source_event: "security_center.test")

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      refute statuses.any? { |s| s.feature_type == "code_scanning" }
      assert statuses.any? { |s| s.feature_type == "code_scanning_pr_reviews" && s.scanning_status == "enrolled" }
    end

    context "#code_scanning_auto_codeql_security_center_status" do
      test "captures status as enrolled" do
        # fake status of primary code_scanning feature
        @repo.stubs(:code_scanning_security_center_status).returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled"))

        Turbocassette.use("code-scanning/get-managed-analysis-info") do
          @repo.security_center_notify("code_scanning", source_event: "security_center.test")
        end

        status = RepositorySecurityCenterStatus.find_by(repository_id: @repo.id, feature_type: "code_scanning_auto_codeql")
        refute_nil status
        status = T.must(status)
        assert_equal "enrolled", status.scanning_status
      end

      test "captures status as eligible when all requirements met" do
        # fake status of primary code_scanning feature
        @repo.stubs(:code_scanning_security_center_status).returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled"))

        CodeScanning::Status.stubs(:validate_prerequisites).returns(nil)

        Turbocassette.use("code-scanning/get-managed-analysis-info-disabled") do
          @repo.security_center_notify("code_scanning", source_event: "security_center.test")
        end

        status = RepositorySecurityCenterStatus.find_by(repository_id: @repo.id, feature_type: "code_scanning_auto_codeql")
        refute_nil status
        status = T.must(status)
        assert_equal "eligible", status.scanning_status
      end

      test "captures status as eligible when ghas disabled" do
        # fake status of primary code_scanning feature
        @private_repo.stubs(:code_scanning_security_center_status).returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled"))
        @private_repo.disable_advanced_security!(actor: @owner)

        if GitHub.enterprise?
          GitHub.stubs(:actions_enabled?).returns(true)
          CodeScanning::Status.stubs(:validate_default_setup_runners).returns(nil)
        end

        Turbocassette.use("code-scanning/get-managed-analysis-info-disabled") do
          @private_repo.security_center_notify("code_scanning", source_event: "security_center.test")
        end

        status = RepositorySecurityCenterStatus.find_by(repository_id: @private_repo.id, feature_type: "code_scanning_auto_codeql")
        refute_nil status
        status = T.must(status)
        assert_equal "eligible", status.scanning_status
      end

      test "captures status as ineligible when repo not eligible for code scanning" do
        # fake status of primary code_scanning feature
        @repo.stubs(:code_scanning_security_center_status).returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled"))

        # condition for ineligibility
        @repo.stubs(:code_scanning_banned?).returns(true)

        Turbocassette.use("code-scanning/get-managed-analysis-info-disabled") do
          @repo.security_center_notify("code_scanning", source_event: "security_center.test")
        end

        status = RepositorySecurityCenterStatus.find_by(repository_id: @repo.id, feature_type: "code_scanning_auto_codeql")
        refute_nil status
        status = T.must(status)
        assert_equal "not_eligible", status.scanning_status
      end

      test "captures status as ineligible when repo can't use actions" do
        # fake status of primary code_scanning feature
        @repo.stubs(:code_scanning_security_center_status).returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled"))

        # condition for ineligibility
        @repo.stubs(:actions_disabled?).returns(true)

        Turbocassette.use("code-scanning/get-managed-analysis-info-disabled") do
          @repo.security_center_notify("code_scanning", source_event: "security_center.test")
        end

        status = RepositorySecurityCenterStatus.find_by(repository_id: @repo.id, feature_type: "code_scanning_auto_codeql")
        refute_nil status
        status = T.must(status)
        assert_equal "not_eligible", status.scanning_status
      end

      test "update auto codeql status only" do
        # fake status of primary code_scanning feature
        @repo.stubs(:code_scanning_security_center_status).returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled"))

        Turbocassette.use("code-scanning/get-managed-analysis-info") do
          @repo.security_center_notify(:code_scanning_auto_codeql, source_event: "security_center.test")
        end

        statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
        refute statuses.any? { |s| s.feature_type == "code_scanning" }
        assert statuses.any? { |s| s.feature_type == "code_scanning_auto_codeql" && s.scanning_status == "enrolled" }
      end
    end

    test "subfeatures are not updated if flag is false" do
      Repository.any_instance.stubs(:code_scanning_analysis_exists_on_default_ref?).returns(true)
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(true)
      Repository.any_instance.stubs(:code_scanning_open_alerts_count_by_severity).returns({ "critical" => 1 })

      @repo.security_center_notify(SecurityCenter::SecurityFeatures::CODE_SCANNING, source_event: "security_center.test", skip_subfeature_updates: true)

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      assert statuses.any? { |s| s.feature_type == "code_scanning" }
      assert statuses.none? { |s| s.feature_type == "code_scanning_pr_reviews" }
      assert statuses.none? { |s| s.feature_type == "code_scanning_auto_codeql" }
    end
  end

  context "secret scanning subfeatures" do
    test "push protection is enabled" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_counts).returns(TokenScanningCount.new(1))

      SecretScanning::Features::Repo::TokenScanning.new(@repo).enable(actor: @owner)
      SecretScanning::Features::Repo::PushProtection.new(@repo).enable(actor: @owner)

      @repo.security_center_notify(SecurityCenter::SecurityFeatures::SECRET_SCANNING, source_event: "security_center.test")

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      assert statuses.any? { |s| s.feature_type == "secret_scanning" }
      assert statuses.any? { |s| s.feature_type == "secret_scanning_push_protection" && s.scanning_status == "enrolled" }
    end

    test "push protection is not enabled" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_counts).returns(TokenScanningCount.new(1))

      SecretScanning::Features::Repo::TokenScanning.new(@repo).enable(actor: @owner)
      SecretScanning::Features::Repo::PushProtection.new(@repo).disable(actor: @owner)

      @repo.security_center_notify(SecurityCenter::SecurityFeatures::SECRET_SCANNING, source_event: "security_center.test")

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      assert statuses.any? { |s| s.feature_type == "secret_scanning" }
      assert statuses.any? { |s| s.feature_type == "secret_scanning_push_protection" && s.scanning_status == "not_enrolled" }
    end

    test "update push protection only" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_counts).returns(TokenScanningCount.new(1))

      SecretScanning::Features::Repo::TokenScanning.new(@repo).enable(actor: @owner)
      SecretScanning::Features::Repo::PushProtection.new(@repo).enable(actor: @owner)

      @repo.security_center_notify(:secret_scanning_push_protection, source_event: "security_center.test")

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      refute statuses.any? { |s| s.feature_type == "secret_scanning" }
      assert statuses.any? { |s| s.feature_type == "secret_scanning_push_protection" && s.scanning_status == "enrolled" }
    end

    test "subfeatures are not updated if flag is false" do
      @repo.security_center_notify(SecurityCenter::SecurityFeatures::SECRET_SCANNING, source_event: "security_center.test", skip_subfeature_updates: true)

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      assert statuses.any? { |s| s.feature_type == "secret_scanning" }
      assert statuses.none? { |s| s.feature_type == "secret_scanning_push_protection" }
    end
  end

  context "#security_center_notify" do
    test "performs regular updates on existing record" do
      SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
      Repository.any_instance.stubs(:dependabot_alerts_security_center_status).returns(
        Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled")
      )

      Repository.any_instance.expects(:upsert_security_center_repository_configuration).never
      Repository.any_instance.expects(:upsert_feature_status_and_alert_serverities).never

      repo = create(:repository, owner: @org)
      create(:repository_security_center_status, "dependabot_alerts", :not_enrolled, repository: repo)
      create(:repository_security_center_config, repository: repo)

      repo.security_center_notify("dependabot_alerts", source_event: "security_center.test")
      repo.reload

      refute_nil repo.repository_security_center_statuses.where(feature_type: "dependabot_alerts", scanning_status: "enrolled").first
      refute_nil repo.repository_security_center_config
    end

    test "performs upsert if record does not exist" do
      SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
      Repository.any_instance.stubs(:dependabot_alerts_security_center_status).returns(
        Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled")
      )

      # we don't update config when handling feature status
      RepositorySecurityCenterConfig.expects(:upsert_all).never
      RepositorySecurityCenterConfig.expects(:update!).never

      # upsert for dependabot and security updates
      RepositorySecurityCenterStatus.expects(:upsert_all).times(2)
      RepositorySecurityCenterStatus.expects(:update!).never

      repo = create(:repository, owner: @org)

      repo.security_center_notify("dependabot_alerts", source_event: "security_center.test")
    end

    context "when data is not changed" do
      test "does not perform update on config table" do
        repo = create(:repository, owner: @org, name: "woof")
        repo_config = create(:repository_security_center_config, repository: repo, ghas_enabled: false)

        assert_no_changes -> { repo_config } do
          assert_query_count_per_table({ repository_security_center_configs: 0 }) do
            repo.security_center_notify(SecurityCenter::SecurityFeatures::REPOSITORY_CONFIGURATION, source_event: "security_center.test")
          end
        end
      end

      test "does not perform update on primary feature" do
        repo = create(:repository, owner: @org, name: "woof")
        primary_feature_status = create(:repository_security_center_status, SecurityCenter::SecurityFeatures::CODE_SCANNING, :enrolled, repository: repo)
        pr_review_feature_status = create(:repository_security_center_status, :code_scanning_pr_reviews, :enrolled, repository: repo)
        codeql_feature_status = create(:repository_security_center_status, :code_scanning_auto_codeql, :enrolled, repository: repo)

        Repository.any_instance.stubs(:code_scanning_security_center_status).returns(
          Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled")
        )
        Repository.any_instance.stubs(:code_scanning_review_security_center_status).returns(
          Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled")
        )
        Repository.any_instance.stubs(:code_scanning_auto_codeql_security_center_status).returns(
          Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled")
        )

        assert_no_changes -> { primary_feature_status } do
          assert_no_changes -> { pr_review_feature_status } do
            assert_no_changes -> { codeql_feature_status } do
              assert_query_count_per_table({
                repository_security_center_status: 0,
              }) do
                repo.security_center_notify(SecurityCenter::SecurityFeatures::CODE_SCANNING, source_event: "security_center.test")
              end
            end
          end
        end
      end
    end
  end

  private

  def process_messages!(**kwargs)
    run_processor(GitHub::StreamProcessors::SecurityCenterRepositoryUpdateProcessor.new(
      rescue_from_standard_error: true
    ),
    **kwargs
  )
  end

  def publish_and_consume(msg)
    hydro_publisher.publish(msg, schema: "github.v1.TokenScanNotify", topic: "github.v1.TokenScanNotify", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    run_processor(GitHub::StreamProcessors::SecretScanningNotificationsProcessor.new)
  end

  def publish_and_consume_security_center_update_event(repo_id)
    perform_enqueued_jobs(only: [::SecurityCenter::RepositorySyncJob]) do
      yield
    end
  end

  def run_update_processor
    perform_enqueued_jobs(only: [::SecurityCenter::RepositorySyncJob]) do
      yield
    end
  end
end

class RepositorySecurityCenterTest < GitHub::IntegrationTestCase
  include PrivateTokenScanningTestHelper
  include HydroTestHelpers
  include HydroMessageJobTestHelpers

  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)
    @private_repo = create(:private_repository, owner: @org)
  end

  setup do
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
    RepositorySecurityCenterStatus.destroy_all
  end

  test "secret scanning enabled from UI" do
    @private_repo.enable_advanced_security!(actor: @owner)
    secret_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(@private_repo)
    secret_scanning_feature.disable(actor: @owner)

    GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_counts).returns(TokenScanningCount.new(0))

    refute secret_scanning_feature.enabled?

    reset_hydro

    as @owner

    perform_enqueued_hydro_jobs(publisher: GitHub.hydro_publisher, only: [SecurityCenter::HydroSecretScanningFeatureToggledJob]) do
      perform_enqueued_jobs only: SecurityAnalysisSettingsUpdateJob do
        put "/organizations/#{@org}/settings/security_analysis/update",
          params: { secret_scanning: "enable_all" }
      end
      assert_hydro_messages count: 1, schema: "github.secret_scanning.v1.SecretScanningFeatureToggled"
    end

    @private_repo.reload

    assert secret_scanning_feature.enabled?

    check_secret_scanning_security_center_status("enrolled")
  end

  test "secret scanning disabled from UI" do
    @private_repo.enable_advanced_security!(actor: @owner)
    secret_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(@private_repo)
    secret_scanning_feature.enable(actor: @owner)
    assert secret_scanning_feature.enabled?

    reset_hydro

    as @owner

    perform_enqueued_hydro_jobs(publisher: GitHub.hydro_publisher, only: [SecurityCenter::HydroSecretScanningFeatureToggledJob]) do
      perform_enqueued_jobs(only: SecurityAnalysisSettingsUpdateJob) do
        put "/organizations/#{@org}/settings/security_analysis/update",
          params: { secret_scanning: "disable_all" }
      end
      assert_hydro_messages count: 1, schema: "github.secret_scanning.v1.SecretScanningFeatureToggled"
    end

    @private_repo.reload

    refute secret_scanning_feature.enabled?

    check_secret_scanning_security_center_status("not_enrolled")
  end

  private

  def check_secret_scanning_security_center_status(enrollment_status)
    status = RepositorySecurityCenterStatus.first
    refute_nil status
    assert_equal "secret_scanning", T.must(status).feature_type
    assert_equal enrollment_status, T.must(status).scanning_status
  end

  def publish_and_consume_security_center_update_event(repo_id)
    perform_enqueued_jobs(only: [::SecurityCenter::RepositorySyncJob]) do
      yield
    end
  end
end
