# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroDependabotFeatureToggledJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers

    fixtures do
      @org = create(:organization)
    end

    setup do
      # referencing the job class forces it to load, so it can be looked up by queue name
      @queue = SecurityCenter::HydroDependabotFeatureToggledJob.queue_name
      @schema = "github.security_alerts.v1.RepositoryVulnerabilityAlertsAnalyticsEvent"

      SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
    end

    test "it updates feature data" do
      repo = create(:repository, owner: @org)

      Repository.any_instance.expects(:dependabot_alerts_security_center_status)
        .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new(
          "enrolled",
          10,
          scanning_count_by_severity: {
            critical: 4,
            high: 3,
            medium: 2,
            low: 1,
          }
        ))
        .once

      message = {
        action: "enable",
        repository_id: repo.id,
      }

      perform_hydro_message_job(message, schema: @schema, queue: @queue)

      db_status = RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "dependabot_alerts")
      assert db_status
      assert_equal "enrolled", db_status&.scanning_status
      assert_equal 10, db_status&.scanning_count
      db_severities = SecurityCenterAlertSeverity.where(repository_id: repo.id, feature_type: "dependabot_alerts").all
      assert_equal 4, db_severities.find { |s| s.severity == "critical" }&.alert_count
      assert_equal 3, db_severities.find { |s| s.severity == "high" }&.alert_count
      assert_equal 2, db_severities.find { |s| s.severity == "medium" }&.alert_count
      assert_equal 1, db_severities.find { |s| s.severity == "low" }&.alert_count
    end

    context "when event includes unsupported action" do
      test "it does not update" do
        repo = create(:repository, owner: @org)
        Repository.any_instance.expects(:security_center_notify).never

        message = {
          action: "digest_sent",
          # no repository id for this event
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "dependabot_alerts")
        assert_empty SecurityCenterAlertSeverity.where(repository_id: repo.id, feature_type: "dependabot_alerts")
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:action_not_supported"])
      end
    end

    context "when repository is soft-deleted" do
      test "it does not update" do
        repo = create(:repository, :soft_deleted, owner: create(:user))
        Repository.any_instance.expects(:security_center_notify).never

        message = {
          action: "enable",
          repository_id: repo.id,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "code_scanning")
        assert_empty SecurityCenterAlertSeverity.where(repository_id: repo.id, feature_type: "code_scanning")
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:repo_deleted"])
      end
    end

    context "when repository is user-owned" do
      test "it does not update" do
        repo = create(:repository, owner: create(:user))
        Repository.any_instance.expects(:security_center_notify).never

        message = {
          action: "enable",
          repository_id: repo.id,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "dependabot_alerts")
        assert_empty SecurityCenterAlertSeverity.where(repository_id: repo.id, feature_type: "dependabot_alerts")
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_org"])
      end
    end

    context "when feature is not available for owner" do
      test "it does not update" do
        repo = create(:repository, owner: @org)
        Repository.any_instance.expects(:security_center_notify).never
        SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(false)

        message = {
          action: "enable",
          repository_id: repo.id,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "dependabot_alerts")
        assert_empty SecurityCenterAlertSeverity.where(repository_id: repo.id, feature_type: "dependabot_alerts")
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:feature_not_available"])
      end
    end

    context "lifecycle telemetry" do
      test "reports telemetry when job completes successfully" do
        repo = create(:repository, owner: @org)

        message = {
          action: "enable",
          repository_id: repo.id,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        assert_dogstats_distribution(1, "security_center.repository_updated.dist", tags: ["source_event:github.security_alerts.v1.RepositoryVulnerabilityAlertsAnalyticsEvent#enable"])
      end

      test "does not report telemetry when job fails" do
        repo = create(:repository, owner: @org)

        message = {
          action: "enable",
          repository_id: repo.id,
        }

        assert_raises(StandardError) do
          Repository.any_instance.stubs(:security_center_notify).raises(StandardError.new).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end

        refute_dogstats_distribution("security_center.repository_updated.dist")
      end
    end

    context "resiliency" do
      test "it retries on recoverable errors" do
        repo = create(:repository, owner: create(:organization))

        message = {
          action: "enable",
          repository_id: repo.id,
        }

        Resiliency::Response::UnavailableExceptions.each do |exception|
          Repository.any_instance.expects(:security_center_notify).raises(exception, "boom")
          HydroDependabotFeatureToggledJob.any_instance.expects(:retry).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      test "it retries on throttler errors" do
        repo = create(:repository, owner: create(:organization))

        message = {
          action: "enable",
          repository_id: repo.id,
        }

        [Freno::Throttler::Error, Freno::Throttler::WaitedTooLong].each do |exception|
          Repository.any_instance.expects(:security_center_notify).raises(exception)
          HydroDependabotFeatureToggledJob.any_instance.expects(:retry).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      test "it retries on gitrpc errors" do
        repo = create(:repository, owner: create(:organization))

        message = {
          action: "enable",
          repository_id: repo.id,
        }

        [GitRPC::NetworkError].each do |exception|
          Repository.any_instance.expects(:security_center_notify).raises(exception)
          HydroDependabotFeatureToggledJob.any_instance.expects(:retry).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      test "it retries when repo not found" do
        ::Repositories::Public.expects(:get_active_or_deleted!).raises(ActiveRecord::RecordNotFound)
        HydroDependabotFeatureToggledJob.any_instance.expects(:retry).once

        message = {
          action: "enable",
          repository_id: -1,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end
    end
  end
end
