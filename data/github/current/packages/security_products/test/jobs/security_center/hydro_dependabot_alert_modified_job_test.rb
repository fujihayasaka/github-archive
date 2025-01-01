# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroDependabotAlertModifiedJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers

    fixtures do
      @org = create :organization
    end

    setup do
      # referencing the job class forces it to load, so it can be looked up by queue name
      @queue = SecurityCenter::HydroDependabotAlertModifiedJob.queue_name
      @schema = "github.security_alerts.v1.RepositoryVulnerabilityAlertLifecycleEvent"

      SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
      GitHub.flipper[:security_center_dependabot_alerts_enqueue_repo_sync].disable
    end

    context "delegate to repository sync job when feature flag enabled" do
      test "it enqueues repo sync job" do
        GitHub.flipper[:security_center_dependabot_alerts_enqueue_repo_sync].enable
        repo = create(:repository, owner: @org)

        RepositorySyncJob
        .expects(:enqueue_once_per_interval)
        .with do |**options|
          kwargs = options[:kwargs]
          kwargs[:repository_id] == repo.id &&
          kwargs[:source_event] == "#{@schema}#create" &&
          kwargs[:feature_type] == "dependabot_alerts" &&
          kwargs[:event_timestamp].present? &&
          options[:interval] == 60 &&
          options[:run_at_beginning_of_interval] == false &&
          options[:unique_id] == ActiveJob::LockingJob::DEFAULT_LOCK_STRINGIFY_PROC.call(repository_id: repo.id, feature_type: "dependabot_alerts")
        end
        .once

        message = {
          action: "create",
          repository_id: repo.id,
        }
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      test "it enqueues only once within debounce interval" do
        GitHub.flipper[:security_center_dependabot_alerts_enqueue_repo_sync].enable
        repo = create(:repository, owner: @org)

        message = {
          action: "create",
          repository_id: repo.id,
        }

        assert_enqueued_jobs(1, only: RepositorySyncJob) do
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      test "it enqueues again after debounce interval" do
        GitHub.flipper[:security_center_dependabot_alerts_enqueue_repo_sync].enable
        repo = create(:repository, owner: @org)

        message = {
          action: "create",
          repository_id: repo.id,
        }

        assert_enqueued_jobs(1, only: RepositorySyncJob) do
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
          Timecop.travel(1.minute) do
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end
      end

      test "it enqueues again for different repository" do
        GitHub.flipper[:security_center_dependabot_alerts_enqueue_repo_sync].enable
        repo1 = create(:repository, owner: @org)
        repo2 = create(:repository, owner: @org)

        assert_enqueued_jobs(2, only: RepositorySyncJob) do
          perform_hydro_message_job({ action: "create", repository_id: repo1.id }, schema: @schema, queue: @queue)
          perform_hydro_message_job({ action: "create", repository_id: repo2.id }, schema: @schema, queue: @queue)
        end
      end
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
        action: "create",
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

    context "when repository is not found" do
      context "when alert is being resolved" do
        context "when alert does not exist" do
          test "it does not update or retry" do
            Repository.any_instance.expects(:dependabot_alerts_security_center_status).never
            HydroDependabotAlertModifiedJob.any_instance.expects(:retry).never

            message = {
              action: "resolve",
              repository_id: -1,
              repository_vulnerability_alert_id: -1,
            }

            perform_hydro_message_job(message, schema: @schema, queue: @queue)

            assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:repo_not_found"])
          end
        end

        context "when alert exists" do
          test "it retries" do
            rva = create(:repository_vulnerability_alert)
            Repository.any_instance.expects(:dependabot_alerts_security_center_status).never
            HydroDependabotAlertModifiedJob.any_instance.expects(:retry).once

            message = {
              action: "resolve",
              repository_id: -1,
              repository_vulnerability_alert_id: rva.id,
            }

            perform_hydro_message_job(message, schema: @schema, queue: @queue)

            refute_dogstats_increment("security_center.repository_update.abort")
          end
        end
      end

      context "when alert is being withdrawed" do
        test "enqueue update job to properly clean up repository data" do
          HydroDependabotAlertModifiedJob.any_instance.expects(:retry).never
          RepositorySyncJob.expects(:perform_later).with do |args|
            args[:repository_id] == -1 &&
            args[:source_event] == "#{@schema}#withdraw" &&
            args[:feature_type] == "dependabot_alerts" &&
            args[:event_timestamp].present?
          end.once

          message = {
            action: "withdraw",
            repository_id: -1,
          }

          perform_hydro_message_job(message, schema: @schema, queue: @queue)

          refute_dogstats_increment("security_center.repository_update.abort")
        end
      end

      test "it retries" do
        Repository.any_instance.expects(:dependabot_alerts_security_center_status).never

        %w[
          create
          dismiss
          reopen
          reintroduce
          auto_dismiss
          auto_reopen
        ].each do |action|
          HydroDependabotAlertModifiedJob.any_instance.expects(:retry).once

          message = {
            action:,
            repository_id: -1,
          }

          perform_hydro_message_job(message, schema: @schema, queue: @queue)
          refute_dogstats_increment("security_center.repository_update.abort")
        end
      end
    end

    context "when repository is soft-deleted" do
      test "it does not update" do
        repo = create(:repository, :soft_deleted, owner: create(:user))
        Repository.any_instance.expects(:security_center_notify).never

        message = {
          action: "create",
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
        Repository.any_instance.expects(:dependabot_alerts_security_center_status).never

        message = {
          action: "create",
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
          action: "create",
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
          action: "create",
          repository_id: repo.id,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        assert_dogstats_distribution(1, "security_center.repository_updated.dist", tags: ["source_event:github.security_alerts.v1.RepositoryVulnerabilityAlertLifecycleEvent#create"])
      end

      test "does not report telemetry when job fails" do
        repo = create(:repository, owner: @org)

        message = {
          action: "create",
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
          action: "create",
          repository_id: repo.id,
        }

        Resiliency::Response::UnavailableExceptions.each do |exception|
          Repository.any_instance.expects(:security_center_notify).raises(exception, "boom")
          HydroDependabotAlertModifiedJob.any_instance.expects(:retry).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      test "it retries on throttler errors" do
        repo = create(:repository, owner: create(:organization))

        message = {
          action: "create",
          repository_id: repo.id,
        }

        [Freno::Throttler::Error, Freno::Throttler::WaitedTooLong].each do |exception|
          Repository.any_instance.expects(:security_center_notify).raises(exception)
          HydroDependabotAlertModifiedJob.any_instance.expects(:retry).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end
    end
  end
end
