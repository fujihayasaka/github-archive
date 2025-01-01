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
    GitHub.flipper[:security_center_reconciliation_ignore_failure].disable

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
      Repository.any_instance.stubs(:code_scanning_analysis_exists_on_default_ref?).returns(false)
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(false)
      Repository.any_instance.stubs(:code_scanning_enabled?).returns(false)
      Repository.any_instance.stubs(:code_scanning_latest_analysis).returns({ "seconds" => 0 })
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)

      @repo.security_center_notify("code_scanning", source_event: "security_center.test")

      assert_equal "not_enrolled", T.must(RepositorySecurityCenterStatus.first).scanning_status
      assert_equal 0, T.must(RepositorySecurityCenterStatus.first).scanning_count
      assert_nil T.must(RepositorySecurityCenterStatus.first).scanned_at
    end

    test "update enrolled status for repo" do
      # Stub methods that code_scanning_security_center_status depends on
      Repository.any_instance.stubs(:code_scanning_analysis_exists_on_default_ref?).returns(true)
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(true)
      Repository.any_instance.stubs(:code_scanning_open_alerts_count_by_severity).returns({ "critical" => 3 })
      Repository.any_instance.stubs(:code_scanning_latest_analysis).returns({ "seconds" => 0 })
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(true)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)

      @repo.security_center_notify("code_scanning", source_event: "security_center.test")

      assert_equal "enrolled", T.must(RepositorySecurityCenterStatus.first).scanning_status
      assert_equal 3, T.must(RepositorySecurityCenterStatus.first).scanning_count
      assert_equal Time.at(0), T.must(RepositorySecurityCenterStatus.first).scanned_at
    end

    test "update status for repo with existing status present" do
      create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: @repo, scanning_count: 0)

      # Stub methods that code_scanning_security_center_status depends on
      Repository.any_instance.stubs(:code_scanning_analysis_exists_on_default_ref?).returns(true)
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(true)
      Repository.any_instance.stubs(:code_scanning_open_alerts_count_by_severity).returns({ "critical" => 3 })
      Repository.any_instance.stubs(:code_scanning_latest_analysis).returns({ "seconds" => 0 })
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(true)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)

      @repo.security_center_notify("code_scanning", source_event: "security_center.test")

      assert_equal "enrolled", T.must(RepositorySecurityCenterStatus.first).scanning_status
      assert_equal 3, T.must(RepositorySecurityCenterStatus.first).scanning_count
      assert_equal Time.at(0), T.must(RepositorySecurityCenterStatus.first).scanned_at
    end

    test "update status for failing turboscan raises error" do
      Repository.any_instance.expects(:code_scanning_open_alerts_count_by_severity).at_least_once.returns(nil)

      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)
      CodeScanning::AutoCodeql.any_instance.stubs(:can_enable?).returns(SecurityProduct::Result.new(false))

      # check_run 1 doesnt exist, but we need something to call refresh
      assert_raises ::Repository::SecurityCenterDependency::UnknownSecurityFeatureStatusError do
        @repo.security_center_notify("code_scanning", source_event: "security_center.test")
      end

      # If there is an error then we do not expect the status to be set
      assert RepositorySecurityCenterStatus.first.nil?
    end

    test "update status for failing turboscan ignores error when feature flag enabled" do
      @repo.enable_feature(:security_center_reconciliation_ignore_failure)

      Repository.any_instance.expects(:code_scanning_open_alerts_count_by_severity).at_least_once.returns(nil)

      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)
      CodeScanning::AutoCodeql.any_instance.stubs(:can_enable?).returns(SecurityProduct::Result.new(false))

      # check_run 1 doesnt exist, but we need something to call refresh
      assert_no_error_reported do
        @repo.security_center_notify("code_scanning", source_event: "security_center.test")
      end

      # If there is an error then we do not expect the status to be set
      assert RepositorySecurityCenterStatus.first.nil?
    end

    test "update status for repo with existing status missing latest" do
      create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: @repo, scanning_count: 0)

      # Stub methods that code_scanning_security_center_status depends on
      Repository.any_instance.stubs(:code_scanning_analysis_exists_on_default_ref?).returns(true)
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(true)
      Repository.any_instance.stubs(:code_scanning_latest_analysis).returns(nil)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(true)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)

      @repo.security_center_notify("code_scanning", source_event: "security_center.test")

      assert_equal "enrolled", T.must(RepositorySecurityCenterStatus.first).scanning_status
      assert_equal 0, T.must(RepositorySecurityCenterStatus.first).scanning_count
      assert_nil T.must(RepositorySecurityCenterStatus.first).scanned_at
    end

    test "update status for private repo with GHAS disabled" do
      create(:repository_security_center_status, :code_scanning, :enrolled, repository: @private_repo, scanning_count: 3)

      @private_repo.disable_advanced_security!(actor: @owner)

      Turbocassette.use("code-scanning/counts-missing-latest") do
        @private_repo.security_center_notify("code_scanning", source_event: "security_center.test")
      end

      assert_equal "not_enrolled", T.must(RepositorySecurityCenterStatus.first).scanning_status
      assert_equal 0, T.must(RepositorySecurityCenterStatus.first).scanning_count
      assert_nil T.must(RepositorySecurityCenterStatus.first).scanned_at
    end

    test "update status for public repo with GHAS disabled", enterprise_only: true do
      create(:repository_security_center_status, :code_scanning, :enrolled, repository: @repo, scanning_count: 3)

      @repo.disable_advanced_security!(actor: @owner)

      Turbocassette.use("code-scanning/counts-present") do
        @repo.security_center_notify("code_scanning", source_event: "security_center.test")
      end

      # Code scanning is available for public repos in dotcom even if GHAS is disabled.
      # In GHES we treat public repos like private repos. GHAS is required.
      if GitHub.enterprise?
        assert_equal "not_enrolled", T.must(RepositorySecurityCenterStatus.first).scanning_status
        assert_equal 0, T.must(RepositorySecurityCenterStatus.first).scanning_count
        assert_nil T.must(RepositorySecurityCenterStatus.first).scanned_at
      else
        assert_equal "enrolled", T.must(RepositorySecurityCenterStatus.first).scanning_status
        assert_equal 3, T.must(RepositorySecurityCenterStatus.first).scanning_count
        assert_equal Time.parse("0001-01-01T00:00:00Z"), T.must(RepositorySecurityCenterStatus.first).scanned_at
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

      check_secret_scanning_security_center_status("not_enrolled", 0)
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

      check_secret_scanning_security_center_status("enrolled", 1)
    end

    test "dependabot_alerts is updated for non-GHAS org repo" do
      SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)

      repo = create(:repository, owner: @org)

      repo.security_center_notify("dependabot_alerts", source_event: "security_center.test")
      refute_nil repo.repository_security_center_statuses.where(feature_type: "dependabot_alerts").first
    end
  end

  context "SecurityCenterAlertSeverities table ingestion" do
    test "code scanning is ingested" do
      create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: @repo, scanning_count: 0)

      # Stub methods that code_scanning_security_center_status depends on
      Repository.any_instance.stubs(:code_scanning_analysis_exists_on_default_ref?).returns(true)
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(true)
      Repository.any_instance.stubs(:code_scanning_latest_analysis).returns({ "seconds" => 0 })
      Repository.any_instance.stubs(:code_scanning_open_alerts_count_by_severity).returns({ "low" => 1, "high" => 2 })
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(true)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabling?).returns(false)

      @repo.security_center_notify("code_scanning", source_event: "security_center.test")

      severities = SecurityCenterAlertSeverity.where(repository_id: @repo.id, feature_type: "code_scanning")
      assert_equal 2, severities.count
      assert_equal "low", T.must(severities.first).severity
      assert_equal 1, T.must(severities.first).alert_count
      assert_equal "high", T.must(severities.last).severity
      assert_equal 2, T.must(severities.last).alert_count
    end

    test "secret scanning is not ingested" do
      # secret scanning is not ingested because it doesn't have a severity breakdown
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_counts).returns(TokenScanningCount.new(1))

      repo = create(:public_repository, owner: @org)
      token = create(:token_scan_result, repository: repo)
      token = create(:token_scan_result, repository: repo)
      location = create(:token_scan_result_location,
        repository_id: repo.id,
        token_scan_result_id: token.id,
      )
      token.update(first_location_id: location.id)

      reset_hydro

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        repo.set_visibility(actor: @owner, visibility: Repository::PRIVATE_VISIBILITY)
      end

      publish_and_consume_security_center_update_event(repo.id) do
        run_processor(GitHub::StreamProcessors::SecurityCenterRepositoryUpdateProcessor.new, allowed_primary_query_count: 13)
      end

      repo.reload

      assert_equal [], SecurityCenterAlertSeverity.where(repository_id: repo.id, feature_type: "secret_scanning")
    end

    test "dependabot alerts are ingested" do
      # dependabot alerts are ingested and that it has an accurate severity breakdown
      stub_dependabot_alerts_enterprise_enablement if GitHub.enterprise?

      node_high_vulnerability = create :published_vulnerability, severity: :high
      node_high_range = create :vulnerable_version_range,
        vulnerability: node_high_vulnerability,
        affects:     "node.js",
        requirements: ">= 4.0.0",
        fixed_in: "3.9.9"

      express_moderate_vulnerability = create :published_vulnerability, severity: :moderate
      express_moderate_range = create :vulnerable_version_range,
        vulnerability: express_moderate_vulnerability,
        affects:     "express.js",
        requirements: ">= 4.0.0",
        fixed_in: "3.9.9"

      @repo.enable_vulnerability_alerts(actor: @repo.owner)

      perform_enqueued_hydro_jobs(publisher: GitHub.hydro_publisher, only: [::SecurityCenter::HydroDependabotAlertModifiedJob]) do
        create_repository_vulnerability_alert(
          vulnerability_id: node_high_vulnerability.id,
          repository_id: @repo.id,
          vulnerable_version_range_id: node_high_range.id,
          state: "open",
          vulnerable_manifest_path: "package.json"
        )

        create_repository_vulnerability_alert(
          vulnerability_id: express_moderate_vulnerability.id,
          repository_id: @repo.id,
          vulnerable_version_range_id: express_moderate_range.id,
          state: "open",
          vulnerable_manifest_path: "package.json"
        )
      end

      # HydroDependabotAlertModifiedJob delegates to repo sync, with debouncing
      perform_enqueued_jobs(only: SecurityCenter::RepositorySyncJob)

      assert_equal 2, SecurityCenterAlertSeverity.all.count
      high_severity_status = SecurityCenterAlertSeverity.where(severity: :high).first
      moderate_severity_status = SecurityCenterAlertSeverity.where(severity: :moderate).first
      refute_nil high_severity_status
      refute_nil moderate_severity_status
      assert_equal 1, T.must(high_severity_status).alert_count
      assert_equal 1, T.must(moderate_severity_status).alert_count

      # check that the "all" case isn't recorded
      all_severity_status = SecurityCenterAlertSeverity.where(severity: :all).first
      assert_nil all_severity_status
    end

    test "severity statuses are removed when a repo is deleted" do
      repo = create(:repository, owner: @org)

      create(:security_center_alert_severity, :dependabot_alerts, repository: repo,
        severity: "high", alert_count: 2)

      assert_equal 1, SecurityCenterAlertSeverity.count

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        repo.remove(@owner)
        # alerts are only removed when the repo is purged
        repo.purge(synchronous: true)
      end

      assert_equal 0, SecurityCenterAlertSeverity.count
    end

    test "severity statuses are correctly updated when list of severities changes" do
      create(:repository_security_center_config, repository: @repo)

      create(:repository_security_center_status, repository: @repo,
        feature_type: "dependabot_alerts", scanning_status: "enrolled", scanning_count: 999)
      create(:security_center_alert_severity, :dependabot_alerts, repository: @repo,
          severity: "high", alert_count: 999)

      Repository.any_instance.stubs(:dependabot_alerts_security_center_status).returns(
        Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 999,
          scanning_count_by_severity: { "low" => 999 })
      )

      @repo.security_center_notify("dependabot_alerts", source_event: "security_center.test")
      severities = SecurityCenterAlertSeverity.all
      assert_equal 1, severities.count
      assert_equal "low", T.must(severities.first).severity
      assert_equal 999, T.must(severities.first).alert_count
    end
  end

  context "telemetry" do
    context "deviation tracking" do
      [
        SecurityCenter::OrganizationReconciliationJob::RECONCILIATION_EVENT,
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
            repository: @repo, feature_type: "secret_scanning", scanning_status: "failed", scanning_count: 0)
          status = @repo.security_center_status_for_feature("secret_scanning")
          @repo.stubs(:secret_scanning_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 999))

          assert_logged(
            Body: "Deviation detected in feature status",
            "gh.security_center.feature_type": "secret_scanning",
            "gh.security_center.deviations": %w(scanning_count scanning_status),
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
            "deviation:scanning_count",
            "deviation:scanning_status",
          ])
        end

        test "logs deviation for missing feature status with #{event} event" do
          create(:repository_security_center_config, repository: @repo)

          @repo.stubs(:secret_scanning_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 999))

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
            feature_type: "secret_scanning", scanning_status: "enrolled", scanning_count: 999)
          @repo.stubs(:secret_scanning_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 999))

          create(:repository_security_center_status, repository: @repo,
            feature_type: "secret_scanning_push_protection", scanning_status: "not_enrolled")
          status = @repo.security_center_status_for_feature("secret_scanning_push_protection")
          @repo.stubs(:push_protection_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0))

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
            feature_type: "secret_scanning", scanning_status: "enrolled", scanning_count: 999)
          @repo.stubs(:secret_scanning_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 999))

          @repo.stubs(:push_protection_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0))

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

        test "logs deviation for alert severity discrepancy with #{event} event" do
          create(:repository_security_center_config, repository: @repo)

          create(:repository_security_center_status, repository: @repo,
            feature_type: "dependabot_alerts", scanning_status: "enrolled", scanning_count: 999)
          status = create(:security_center_alert_severity, :dependabot_alerts, repository: @repo,
              severity: "high", alert_count: 999)

          Repository.any_instance.stubs(:dependabot_alerts_security_center_status).returns(
            Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 999,
              scanning_count_by_severity: { "high" => 998 })
          )

          # Stubbing sub-features so they don't deviate
          create(:repository_security_center_status, repository: @repo,
            feature_type: "dependabot_security_updates", scanning_status: "enrolled")
          @repo.stubs(:security_updates_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0))

          unless GitHub.flipper[:security_center_skip_dependabot_version_updates_status].enabled?
            create(:repository_security_center_status, repository: @repo,
              feature_type: "dependabot_version_updates", scanning_status: "enrolled")
            @repo.stubs(:version_updates_security_center_status).once.
              returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0))
          end

          assert_logged(
            Body: "Deviation detected in feature severity status",
            "gh.security_center.feature_type": "dependabot_alerts",
            "gh.security_center.severity": "high",
            "gh.security_center.deviations": %w(alert_count),
            "gh.repo.id": @repo.id,
            "gh.repo.name": @repo.name,
            "gh.owner.id": @repo.owner_id,
            "gh.owner.login": @repo.owner_display_login,
            "gh.business.id": @repo.business_id,
            "gh.org.id": @repo.owner_id,
            "gh.org.login": @repo.owner_display_login,
            "gh.security_center.source_event": event,
          ) do
            @repo.security_center_notify("dependabot_alerts", source_event: event)
          end

          assert_dogstats_increment("security_center.reconciliation.deviation.severitycount", tags: [
            "feature_type:dependabot_alerts",
            "severity:high",
            "source_event:#{event}",
            "deviation:alert_count",
          ])
        end

        test "logs deviation for missing alert severity with #{event} event" do
          create(:repository_security_center_config, repository: @repo)

          create(:repository_security_center_status, repository: @repo,
            feature_type: "dependabot_alerts", scanning_status: "enrolled", scanning_count: 999)
          status = @repo.security_center_status_for_feature("dependabot_alerts")

          Repository.any_instance.stubs(:dependabot_alerts_security_center_status).returns(
            Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 999,
              scanning_count_by_severity: { "high" => 999 })
          )

          # Stubbing sub-features so they don't deviate
          create(:repository_security_center_status, repository: @repo,
            feature_type: "dependabot_security_updates", scanning_status: "enrolled")
          @repo.stubs(:security_updates_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0))

          unless GitHub.flipper[:security_center_skip_dependabot_version_updates_status].enabled?
            create(:repository_security_center_status, repository: @repo,
              feature_type: "dependabot_version_updates", scanning_status: "enrolled")
            @repo.stubs(:version_updates_security_center_status).once.
              returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0))
          end

          assert_logged(
            Body: "Deviation detected in feature severity status",
            "gh.security_center.feature_type": "dependabot_alerts",
            "gh.security_center.severity": "high",
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
            @repo.security_center_notify("dependabot_alerts", source_event: event)
          end

          assert_dogstats_increment("security_center.reconciliation.deviation.severitycount", tags: [
            "feature_type:dependabot_alerts",
            "source_event:#{event}",
            "deviation:record_missing",
          ])
        end

        test "logs deviation for deleted alert severity with #{event} event" do
          create(:repository_security_center_config, repository: @repo)

          create(:repository_security_center_status, repository: @repo,
            feature_type: "dependabot_alerts", scanning_status: "enrolled", scanning_count: 999)
          status = @repo.security_center_status_for_feature("dependabot_alerts")

          create(:security_center_alert_severity, :dependabot_alerts, repository: @repo,
            severity: "high", alert_count: 999)

          Repository.any_instance.stubs(:dependabot_alerts_security_center_status).returns(
            Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 999,
              scanning_count_by_severity: { "low" => 999 })
          )

          # Stubbing sub-features so they don't deviate
          create(:repository_security_center_status, repository: @repo,
            feature_type: "dependabot_security_updates", scanning_status: "enrolled")
          @repo.stubs(:security_updates_security_center_status).once.
            returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0))

          unless GitHub.flipper[:security_center_skip_dependabot_version_updates_status].enabled?
            create(:repository_security_center_status, repository: @repo,
              feature_type: "dependabot_version_updates", scanning_status: "enrolled")
            @repo.stubs(:version_updates_security_center_status).once.
              returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0))
          end

          assert_logged(
            Body: "Deviation detected in feature severity status",
            "gh.security_center.feature_type": "dependabot_alerts",
            "gh.security_center.severity": "high",
            "gh.security_center.deviations": %w(record_exists),
            "gh.repo.id": @repo.id,
            "gh.repo.name": @repo.name,
            "gh.owner.id": @repo.owner_id,
            "gh.owner.login": @repo.owner_display_login,
            "gh.business.id": @repo.business_id,
            "gh.org.id": @repo.owner_id,
            "gh.org.login": @repo.owner_display_login,
            "gh.security_center.source_event": event,
          ) do
            @repo.security_center_notify("dependabot_alerts", source_event: event)
          end

          assert_dogstats_increment("security_center.reconciliation.deviation.severitycount", tags: [
            "feature_type:dependabot_alerts",
            "source_event:#{event}",
            "deviation:record_exists",
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
          .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 999))
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

    test "dependabot version updates are enabled" do
      GitHub.flipper[:security_center_skip_dependabot_version_updates_status].disable
      @repo.stubs(:dependabot_version_updates_enabled?).returns(true)

      @repo.security_center_notify(SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS, source_event: "security_center.test")

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      assert statuses.any? { |s| s.feature_type == "dependabot_alerts" }
      assert statuses.any? { |s| s.feature_type == "dependabot_version_updates" && s.scanning_status == "enrolled" }
    end

    test "dependabot version updates are not enabled" do
      GitHub.flipper[:security_center_skip_dependabot_version_updates_status].disable
      @repo.stubs(:dependabot_version_updates_enabled?).returns(false)

      @repo.security_center_notify(SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS, source_event: "security_center.test")

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      assert statuses.any? { |s| s.feature_type == "dependabot_alerts" }
      assert statuses.any? { |s| s.feature_type == "dependabot_version_updates" && s.scanning_status == "not_enrolled" }
    end

    test "dependabot version updates keeps previous status on git error" do
      GitHub.flipper[:security_center_skip_dependabot_version_updates_status].disable
      @repo.expects(:dependabot_version_updates_enabled?).raises(GitRPC::Failure.new(StandardError.new)).at_least_once

      # previously non-existant
      RepositorySecurityCenterStatus.destroy_all
      @repo.security_center_notify(SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS, source_event: "security_center.test")
      assert RepositorySecurityCenterStatus.find_by(repository_id: @repo.id, feature_type: "dependabot_alerts")
      refute RepositorySecurityCenterStatus.find_by(repository_id: @repo.id, feature_type: "dependabot_version_updates", scanning_status: "not_enrolled")

      # previously not enrolled
      RepositorySecurityCenterStatus.destroy_all
      create(:repository_security_center_status, repository: @repo, feature_type: :dependabot_version_updates, scanning_status: "not_enrolled")
      @repo.security_center_notify(SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS, source_event: "security_center.test")
      assert RepositorySecurityCenterStatus.find_by(repository_id: @repo.id, feature_type: "dependabot_alerts")
      assert RepositorySecurityCenterStatus.find_by(repository_id: @repo.id, feature_type: "dependabot_version_updates", scanning_status: "not_enrolled")

      # previously enrolled
      RepositorySecurityCenterStatus.destroy_all
      create(:repository_security_center_status, repository: @repo, feature_type: :dependabot_version_updates, scanning_status: "enrolled")
      @repo.security_center_notify(SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS, source_event: "security_center.test")
      assert RepositorySecurityCenterStatus.find_by(repository_id: @repo.id, feature_type: "dependabot_alerts")
      assert RepositorySecurityCenterStatus.find_by(repository_id: @repo.id, feature_type: "dependabot_version_updates", scanning_status: "enrolled")
    end

    test "update version updates only" do
      @repo.stubs(:dependabot_version_updates_enabled?).returns(true)

      @repo.security_center_notify(:dependabot_version_updates, source_event: "security_center.test")

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      refute statuses.any? { |s| s.feature_type == "dependabot_alerts" }
      assert statuses.any? { |s| s.feature_type == "dependabot_version_updates" && s.scanning_status == "enrolled" }
    end

    test "subfeatures are not updated if flag is false" do
      @repo.security_center_notify(SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS, source_event: "security_center.test", skip_subfeature_updates: true)

      statuses = RepositorySecurityCenterStatus.where(repository_id: @repo.id)
      assert statuses.any? { |s| s.feature_type == "dependabot_alerts" }
      assert statuses.none? { |s| s.feature_type == "dependabot_security_updates" }
      assert statuses.none? { |s| s.feature_type == "dependabot_version_updates" }
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
        @repo.stubs(:code_scanning_security_center_status).returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled", 0))

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
        @repo.stubs(:code_scanning_security_center_status).returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled", 0))

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
        @private_repo.stubs(:code_scanning_security_center_status).returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled", 0))
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
        @repo.stubs(:code_scanning_security_center_status).returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled", 0))

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
        @repo.stubs(:code_scanning_security_center_status).returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled", 0))

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
        @repo.stubs(:code_scanning_security_center_status).returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_enrolled", 0))

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
        Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 1)
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
        Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 1)
      )

      # we don't update config when handling feature status
      RepositorySecurityCenterConfig.expects(:upsert_all).never
      RepositorySecurityCenterConfig.expects(:update!).never

      # upsert for dependabot and 2 subfeatures (security updates + version updates)
      expected = GitHub.flipper[:security_center_skip_dependabot_version_updates_status].enabled? ? 2 : 3
      RepositorySecurityCenterStatus.expects(:upsert_all).times(expected)
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
        primary_feature_status = create(:repository_security_center_status, SecurityCenter::SecurityFeatures::CODE_SCANNING, :enrolled, repository: repo, scanning_count: 10)
        pr_review_feature_status = create(:repository_security_center_status, :code_scanning_pr_reviews, :enrolled, repository: repo, scanning_count: 0)
        codeql_feature_status = create(:repository_security_center_status, :code_scanning_auto_codeql, :enrolled, repository: repo, scanning_count: 0)
        feature_serverity = create(:security_center_alert_severity, SecurityCenter::SecurityFeatures::CODE_SCANNING, repository: repo, severity: "high", alert_count: 10)

        Repository.any_instance.stubs(:code_scanning_security_center_status).returns(
          Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new(
            "enrolled",
            10,
            scanning_count_by_severity: { "high" => 10 },
            scanning_date: nil
          )
        )
        Repository.any_instance.stubs(:code_scanning_review_security_center_status).returns(
          Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0)
        )
        Repository.any_instance.stubs(:code_scanning_auto_codeql_security_center_status).returns(
          Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0)
        )

        assert_no_changes -> { primary_feature_status } do
          assert_no_changes -> { pr_review_feature_status } do
            assert_no_changes -> { codeql_feature_status } do
              assert_no_changes -> { feature_serverity } do
                assert_query_count_per_table({
                  repository_security_center_status: 0,
                  security_center_alert_severities: 2 # From SELECT since we try to purge any serverties not found.
                }) do
                  repo.security_center_notify(SecurityCenter::SecurityFeatures::CODE_SCANNING, source_event: "security_center.test")
                end
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

  def check_secret_scanning_security_center_status(enrollment_status, scanning_count)
    # This table is cleared before every test, so we don't need to worry about multiple entries / repos
    status = RepositorySecurityCenterStatus.find_by(feature_type: "secret_scanning")
    refute_nil status
    status = T.must(status)
    assert_equal "secret_scanning", status.feature_type
    assert_equal enrollment_status, status.scanning_status
    assert_equal scanning_count, status.scanning_count
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

  def create_dependabot_alerts(repo)
    node_high_vulnerability = create :published_vulnerability, severity: :high
    node_high_range = create :vulnerable_version_range,
      vulnerability: node_high_vulnerability,
      affects:     "node.js",
      requirements: ">= 4.0.0",
      fixed_in: "3.9.9"

    create_repository_vulnerability_alert(
      vulnerability_id: node_high_vulnerability.id,
      repository_id: repo.id,
      vulnerable_version_range_id: node_high_range.id,
      state: "open",
      vulnerable_manifest_path: "package.json"
    )

    create(:security_center_alert_severity, :dependabot_alerts, repository: repo,
      severity: "high", alert_count: 1)

    node_low_vulnerability = create :published_vulnerability, severity: :low
    node_low_range = create :vulnerable_version_range,
      vulnerability: node_low_vulnerability,
      affects:     "express.js",
      requirements: ">= 4.0.0",
      fixed_in: "3.9.9"

    create_repository_vulnerability_alert(
      vulnerability_id: node_low_vulnerability.id,
      repository_id: repo.id,
      vulnerable_version_range_id: node_low_range.id,
      state: "open",
      vulnerable_manifest_path: "package.json"
    )

    create(:security_center_alert_severity, :dependabot_alerts, repository: repo,
      severity: "low", alert_count: 1)
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

    check_secret_scanning_security_center_status("enrolled", 0)
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

    check_secret_scanning_security_center_status("not_enrolled", 0)
  end

  private

  def check_secret_scanning_security_center_status(enrollment_status, scanning_count)
    status = RepositorySecurityCenterStatus.first
    refute_nil status
    assert_equal "secret_scanning", T.must(status).feature_type
    assert_equal enrollment_status, T.must(status).scanning_status
    assert_equal scanning_count, T.must(status).scanning_count
  end

  def publish_and_consume_security_center_update_event(repo_id)
    perform_enqueued_jobs(only: [::SecurityCenter::RepositorySyncJob]) do
      yield
    end
  end
end
