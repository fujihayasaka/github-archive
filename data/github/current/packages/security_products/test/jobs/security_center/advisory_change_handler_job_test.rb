# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require_relative "../../../app/models/security_center/k_v"

module SecurityCenter
  class AdvisoryChangeHandlerJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper
    include DependabotAlertsEnterpriseEnablementHelper

    fixtures do
      @user = create(:user)
      @org = create(:organization, admin: @user)
    end

    setup do
      if GitHub.enterprise?
        stub_dependabot_alerts_enterprise_enablement
      end

      RepositorySecurityCenterStatus.destroy_all
      SecurityCenterAlertSeverity.destroy_all
      reset_jobs

      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      SecurityCenter::SecurityFeatures.stubs(
        code_scanning_enabled_for_instance?: false,
        secret_scanning_enabled_for_instance?: false,
        dependabot_alerts_enabled_for_instance?: true,
      )
      SecurityProduct::VulnerabilityAlerts.stubs(:enabled_for_instance?).returns(true)

      # AR join breaks stubbing for org property (GHAS purchased), so re-stub here
      Repository.any_instance.stubs(:owner).returns(@org)
    end

    test "should raise an error if no vulnerability_id or vulnerable_version_range_id is provided" do
      assert_raises(ArgumentError) do
        SecurityCenter::AdvisoryChangeHandlerJob.perform_later
      end
    end

    test "should queue update job repositories affected by advisory change" do
      vulnerability = create(:vulnerability, severity: "moderate")

      repo_count = 8.times do
        repo = create(:public_repository, owner: @org)
        create(:repository_vulnerability_alert, :open, active: true, repository: repo, vulnerability: vulnerability)
      end

      # Create inactive alerts to make sure they're not considered for an update
      1.times do
        repo = create(:public_repository, owner: @org)
        create(:repository_vulnerability_alert, :open, active: false, repository: repo, vulnerability: vulnerability)
      end

      perform_enqueued_jobs(only: ::SecurityCenter::RepositorySyncJob) do
        SecurityCenter::AdvisoryChangeHandlerJob.perform_now(vulnerability_id: vulnerability.id, source_event: "security_advisory.update")
      end

      assert_performed_jobs repo_count, only: ::SecurityCenter::RepositorySyncJob

      assert_equal repo_count * 3, RepositorySecurityCenterStatus.count
      feature_types = RepositorySecurityCenterStatus.all.pluck(:feature_type)
      assert_includes feature_types, "dependabot_alerts"
      assert_includes feature_types, "dependabot_security_updates"
      assert_includes feature_types, "dependabot_version_updates"
      assert_equal 3, feature_types.uniq.length

      severities = SecurityCenterAlertSeverity.all.pluck(:severity)
      assert_includes severities, "moderate"
      assert_equal 1, severities.uniq.length
    end

    test "should queue update job repositories affected by advisory vulnerable version change" do
      vulnerability = create(:vulnerability, severity: "moderate")
      vulnerable_range = create(:vulnerable_version_range, {
        vulnerability: vulnerability,
        affects: "rails",
        requirements: ">= 4.0.0, <= 4.2.0",
        fixed_in: "4.2.1",
      })

      repo_count = 12.times do
        repo = create(:public_repository, owner: @org)
        create(:repository_vulnerability_alert, :open, active: true, repository: repo, vulnerability: vulnerability, vulnerable_version_range: vulnerable_range)
      end

      # Create inactive alerts to make sure they're not considered for an update
      1.times do
        repo = create(:public_repository, owner: @org)
        create(:repository_vulnerability_alert, :open, active: false, repository: repo, vulnerability: vulnerability, vulnerable_version_range: vulnerable_range)
      end

      perform_enqueued_jobs(only: ::SecurityCenter::RepositorySyncJob) do
        SecurityCenter::AdvisoryChangeHandlerJob.perform_now(vulnerable_version_range_id: vulnerable_range.id, source_event: "security_advisory.update")
      end

      assert_performed_jobs repo_count, only: ::SecurityCenter::RepositorySyncJob

      assert_equal repo_count * 3, RepositorySecurityCenterStatus.count
      feature_types = RepositorySecurityCenterStatus.all.pluck(:feature_type)
      assert_includes feature_types, "dependabot_alerts"
      assert_includes feature_types, "dependabot_security_updates"
      assert_includes feature_types, "dependabot_version_updates"
      assert_equal 3, feature_types.uniq.length

      severities = SecurityCenterAlertSeverity.all.pluck(:severity)
      assert_includes severities, "moderate"
      assert_equal 1, severities.uniq.length
    end

    test "should filter out repositories not owned by an org" do
      vulnerability = create(:vulnerability, severity: "moderate")

      3.times do
        repo = create(:public_repository, owner: @user)
        create(:repository_vulnerability_alert, :open, active: true, repository: repo, vulnerability: vulnerability)
      end

      updated_repo_count = 4.times do
        repo = create(:public_repository, owner: @org)
        create(:repository_vulnerability_alert, :open, active: true, repository: repo, vulnerability: vulnerability)
      end

      perform_enqueued_jobs(only: ::SecurityCenter::RepositorySyncJob) do
        SecurityCenter::AdvisoryChangeHandlerJob.perform_now(vulnerability_id: vulnerability.id, source_event: "security_advisory.update")
      end

      assert_performed_jobs updated_repo_count, only: ::SecurityCenter::RepositorySyncJob
    end

    context "batch job" do
      test "queues subsequent jobs for batching" do
        vulnerability = create(:vulnerability, severity: "moderate")

        repo_count = 10.times do
          repo = create(:public_repository, owner: @org)
          create(:repository_vulnerability_alert, :open, active: true, repository: repo, vulnerability: vulnerability)
        end

        SecurityCenter::AdvisoryChangeHandlerJob.stub_const(:BATCH_SIZE, 3) do
          assert_performed_jobs 4, only: SecurityCenter::AdvisoryChangeHandlerJob do
            perform_enqueued_jobs(only: SecurityCenter::AdvisoryChangeHandlerJob) do
              SecurityCenter::AdvisoryChangeHandlerJob.perform_later(vulnerability_id: vulnerability.id)
            end
          end
        end
      end

      test "queries distinct batch of alert ids" do
        vulnerability = create(:vulnerability, severity: "moderate")

        repo_ids = 10.times.map do
          repo = create(:public_repository, owner: @org) do |r|
            3.times do
              create(:repository_vulnerability_alert, :open, active: true, repository: r, vulnerability: vulnerability)
            end
          end

          repo.id
        end

        expected_alert_ids = RepositoryVulnerabilityAlert.active_and_inactive.where(repository_id: repo_ids).pluck(:id)

        batch = SecurityCenter::AdvisoryChangeHandlerJob.new.next_batch(vulnerability_id: vulnerability.id, offset_item_id: 0)
        assert_same_elements expected_alert_ids, batch
      end

      test "if multiple alerts share the same repo, only enqueue repo sync job once for each repo" do
        vulnerability = create(:vulnerability, severity: "moderate")

        repo_ids = 10.times.map do
          repo = create(:public_repository, owner: @org) do |r|
            # create three alerts for each repo
            3.times do
              create(:repository_vulnerability_alert, :open, active: true, repository: r, vulnerability: vulnerability)
            end
          end

          repo.id
        end

        SecurityCenter::AdvisoryChangeHandlerJob.stub_const(:BATCH_SIZE, 3) do
          assert_enqueued_jobs 10, only: SecurityCenter::RepositorySyncJob do
            perform_enqueued_jobs(only: SecurityCenter::AdvisoryChangeHandlerJob) do
              SecurityCenter::AdvisoryChangeHandlerJob.perform_later(vulnerability_id: vulnerability.id)
            end
          end
        end
      end
    end

    context "interruption" do
      test "creates lock on new session" do
        kv_key = "security_center/advisory_change_handler_job:1_"
        refute  SecurityCenter::KV.store.exists(kv_key).value!

        enqueue_result = SecurityCenter::AdvisoryChangeHandlerJob.perform_later(vulnerability_id: 1)
        assert !!enqueue_result
        assert  SecurityCenter::KV.store.exists(kv_key).value!
      end

      test "steals lock on new session" do
        kv_key = "security_center/advisory_change_handler_job:1_"
        existing_session_id = SecureRandom.uuid
        SecurityCenter::KV.store.set(kv_key, existing_session_id)

        enqueue_result = SecurityCenter::AdvisoryChangeHandlerJob.perform_later(vulnerability_id: 1)
        assert !!enqueue_result
        refute_equal existing_session_id, SecurityCenter::KV.store.get(kv_key).value!
      end

      test "continues on held lock" do
        kv_key = "security_center/advisory_change_handler_job:1_"
        existing_session_id = SecureRandom.uuid
        SecurityCenter::KV.store.set(kv_key, existing_session_id)

        enqueue_result = SecurityCenter::AdvisoryChangeHandlerJob.perform_later(vulnerability_id: 1, session_id: existing_session_id)
        assert !!enqueue_result
        assert_equal existing_session_id, SecurityCenter::KV.store.get(kv_key).value!
      end

      test "aborts on stolen lock" do
        kv_key = "security_center/advisory_change_handler_job:1_"
        existing_session_id = SecureRandom.uuid
        SecurityCenter::KV.store.set(kv_key, existing_session_id)

        enqueue_result = SecurityCenter::AdvisoryChangeHandlerJob.perform_later(vulnerability_id: 1, session_id: SecureRandom.uuid)
        refute !!enqueue_result
        assert_equal existing_session_id, SecurityCenter::KV.store.get(kv_key).value!
        assert_dogstats_increment("security_center.security_advisory_update.interrupted.count", tags: ["reason:conflict"])
      end

      test "reports on continuation with no lock" do
        kv_key = "security_center/advisory_change_handler_job:1_"
        refute SecurityCenter::KV.store.exists(kv_key).value!
        session_id = SecureRandom.uuid

        Failbot.expects(:report).with(
          instance_of(StandardError),
          has_entries(
            "gh.security_alerts.vulnerability.id": 1,
            "gh.security_alerts.vulnerable_version_range.id": nil,
            "gh.security_center.job.session_id": session_id,
          ))

        enqueue_result = SecurityCenter::AdvisoryChangeHandlerJob.perform_later(vulnerability_id: 1, session_id: session_id)
        refute !!enqueue_result
        refute  SecurityCenter::KV.store.exists(kv_key).value!

        assert_dogstats_increment("security_center.security_advisory_update.interrupted.count", tags: ["reason:missing_lock"])
      end
    end
  end
end
