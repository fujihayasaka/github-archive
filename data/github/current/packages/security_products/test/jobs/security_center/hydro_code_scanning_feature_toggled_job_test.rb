# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroCodeScanningFeatureToggledJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers
    include HydroTestHelpers

    setup do
      @queue = HydroCodeScanningFeatureToggledJob.queue_name
      @schema = "code_scanning.v0.CodeScanningFeatureToggled"

      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(true)
    end

    test "it updates feature data" do
      repo = create(:repository, owner: create(:organization))

      Repository.any_instance.expects(:code_scanning_security_center_status)
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
      Repository.any_instance.expects(:code_scanning_review_security_center_status)
        .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0))
      Repository.any_instance.expects(:code_scanning_auto_codeql_security_center_status)
        .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0))

      message = {
        repository_id: repo.id,
        feature_enabled: true,
      }

      perform_hydro_message_job(message, schema: @schema, queue: @queue)

      db_status = RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "code_scanning")
      assert db_status
      assert_equal "enrolled", db_status&.scanning_status
      assert_equal 10, db_status&.scanning_count
      db_severities = SecurityCenterAlertSeverity.where(repository_id: repo.id, feature_type: "code_scanning").all
      assert_equal 4, db_severities.find { |s| s.severity == "critical" }&.alert_count
      assert_equal 3, db_severities.find { |s| s.severity == "high" }&.alert_count
      assert_equal 2, db_severities.find { |s| s.severity == "medium" }&.alert_count
      assert_equal 1, db_severities.find { |s| s.severity == "low" }&.alert_count
    end

    context "when repository is soft-deleted" do
      test "it does not update" do
        repo = create(:repository, :soft_deleted, owner: create(:user))
        Repository.any_instance.expects(:security_center_notify).never

        message = {
          repository_id: repo.id,
          feature_enabled: true,
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
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "code_scanning")
        assert_empty SecurityCenterAlertSeverity.where(repository_id: repo.id, feature_type: "code_scanning")
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_org"])
      end
    end

    context "when feature is not available for owner" do
      test "it does not update" do
        repo = create(:repository, owner: create(:organization))
        Repository.any_instance.expects(:security_center_notify).never
        SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(false)

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "code_scanning")
        assert_empty SecurityCenterAlertSeverity.where(repository_id: repo.id, feature_type: "code_scanning")
        assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:feature_not_available"])
      end
    end

    context "lifecycle telemetry" do
      test "reports telemetry when job completes successfully" do
        repo = create(:repository, owner: create(:organization))
        Repository.any_instance.expects(:security_center_notify).once

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)

        assert_dogstats_distribution(1, "security_center.repository_updated.dist", tags: ["source_event:#{@schema}#enable"])
      end

      test "does not report telemetry when job fails" do
        repo = create(:repository, owner: create(:organization))

        message = {
          repository_id: repo.id,
          feature_enabled: true,
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
          repository_id: repo.id,
          feature_enabled: true,
        }

        Resiliency::Response::UnavailableExceptions.each do |exception|
          Repository.any_instance.expects(:security_center_notify).raises(exception, "boom")
          HydroCodeScanningFeatureToggledJob.any_instance.expects(:retry).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      test "it retries on AutoCodeql errors" do
        Repository.any_instance.expects(:security_center_notify).raises(CodeScanning::AutoCodeqlError.new("boom"))
        HydroCodeScanningFeatureToggledJob.any_instance.expects(:retry).once

        repo = create(:repository, owner: create(:organization))

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      test "it retries on throttler errors" do
        repo = create(:repository, owner: create(:organization))

        message = {
          repository_id: repo.id,
          feature_enabled: true,
        }

        [Freno::Throttler::Error, Freno::Throttler::WaitedTooLong].each do |exception|
          Repository.any_instance.expects(:security_center_notify).raises(exception)
          HydroCodeScanningFeatureToggledJob.any_instance.expects(:retry).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      test "it retries when repo not found" do
        ::Repositories::Public.expects(:get_active_or_deleted!).raises(ActiveRecord::RecordNotFound)
        HydroCodeScanningFeatureToggledJob.any_instance.expects(:retry).once

        message = {
          repository_id: -1,
          feature_enabled: true,
        }

        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end
    end
  end
end
