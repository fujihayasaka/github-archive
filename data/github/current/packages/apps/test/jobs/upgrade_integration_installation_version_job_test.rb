# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class UpgradeIntegrationInstallationVersionJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  setup do
    disable_feature_flag(:cancel_upgrade_integration_installation_version_job)
    @integration = create(:integration)
    self.perform_enqueued_jobs = [UpgradeIntegrationInstallationVersionJob]
  end

  test "updates when the installation is auto upgradeable" do
    installation = make_integration_installation(target: create(:organization), integration: @integration)
    version      = create(:integration_version, integration: @integration)

    assert installation.auto_upgradeable_to?(version), "expected #{installation} to be auto upgradedable to #{version}"

    UpgradeIntegrationInstallationVersionJob.perform_now(@integration.id, nil, version.number)

    assert_equal version.number, installation.reload.integration_version_number
  end

  test "sends an email when the installation is not auto upgradeable" do
    installation = make_integration_installation(target: create(:organization), integration: @integration)
    version      = create(:integration_version, integration: @integration, default_permissions: { "members" => :read })

    refute installation.auto_upgradeable_to?(version), "expected #{installation} to not be auto upgradedable to #{version}"

    assert_enqueued_with(job: DeliverIntegrationUpdateEmailJob, args: [installation.id, { integration_version_id: version.id }]) do
      UpgradeIntegrationInstallationVersionJob.perform_now(@integration.id, nil, version.number)
    end

    refute_equal version.number, installation.reload.integration_version_number
  end

  test "updates all versions lower than the given version" do
    installation1 = make_integration_installation(target: create(:organization), integration: @integration)
    _version2     = create(:integration_version, integration: @integration, default_permissions: { "members" => :read })

    installation2 = make_integration_installation(target: create(:organization), integration: @integration)
    version3      = create(:integration_version, integration: @integration)

    UpgradeIntegrationInstallationVersionJob.perform_now(@integration.id, nil, version3.number)

    assert_equal version3.number, installation1.reload.integration_version_number
    assert_equal version3.number, installation2.reload.integration_version_number
  end

  test "updates all versions at same time, does not run the second" do
    installation1 = make_integration_installation(target: create(:organization), integration: @integration)
    version2      = create(:integration_version, integration: @integration, default_permissions: { "members" => :read })

    installation2 = make_integration_installation(target: create(:organization), integration: @integration)
    version3      = create(:integration_version, integration: @integration)

    UpgradeIntegrationInstallationVersionJob.perform_now(@integration.id, nil, version2.number)
    UpgradeIntegrationInstallationVersionJob.perform_now(@integration.id, nil, version3.number)

    assert_equal version3.number, installation1.reload.integration_version_number
    assert_equal version3.number, installation2.reload.integration_version_number

    UpgradeIntegrationInstallationVersionJob.perform_now(@integration.id, nil, version2.number)
    assert_equal version3.number, installation1.reload.integration_version_number
    assert_equal version3.number, installation2.reload.integration_version_number
  end

  test "enqueues another job if the upgrade takes too long" do
    GitHub::SafeTimer.any_instance.stubs(:run?).returns(true).returns(false)

    installation_1 = make_integration_installation(target: create(:organization), integration: @integration)
    installation_2 = make_integration_installation(target: create(:organization), integration: @integration)
    version      = create(:integration_version, integration: @integration)

    assert installation_1.auto_upgradeable_to?(version), "expected #{installation_1} to be auto upgradedable to #{version}"

    UpgradeIntegrationInstallationVersionJob.stub_const(:BATCH_SIZE, 1) do
      self.perform_enqueued_jobs = []
      assert_enqueued_with(job: UpgradeIntegrationInstallationVersionJob, args: [
        @integration.id, nil, version.number, {
          installation_id: installation_2.id, outdated_version_number: installation_2.integration_version_number
        }
      ]) do
        UpgradeIntegrationInstallationVersionJob.perform_now(@integration.id, nil, version.number)
      end
    end

    assert_equal version.number, installation_1.reload.integration_version_number
    # installation_2 should not yet be upgraded, because the job should still
    # be queued
    refute_equal version.number, installation_2.reload.integration_version_number
  end

  test "enqueues a job to process versions even further outdated" do
    installation_1 = make_integration_installation(target: create(:organization), integration: @integration)
    create(:integration_version, integration: @integration); @integration.reload

    _installation_2 = make_integration_installation(target: create(:organization), integration: @integration)
    version      = create(:integration_version, integration: @integration)

    self.perform_enqueued_jobs = []
    assert_enqueued_with(job: UpgradeIntegrationInstallationVersionJob, args: [
      @integration.id, nil, version.number, { outdated_version_number: installation_1.integration_version_number }
    ]) do
      UpgradeIntegrationInstallationVersionJob.perform_now(@integration.id, nil, version.number)
    end
  end

  test "supports offsetting" do
    installation1 = make_integration_installation(target: create(:organization), integration: @integration)
    installation2 = make_integration_installation(target: create(:organization), integration: @integration)

    version = create(:integration_version, integration: @integration)

    assert installation1.auto_upgradeable_to?(version), "expected #{installation1} to be auto upgradedable to #{version}"
    assert installation2.auto_upgradeable_to?(version), "expected #{installation2} to be auto upgradedable to #{version}"

    UpgradeIntegrationInstallationVersionJob.perform_now(@integration.id, nil, version.number, installation_id: installation2.id)

    refute_equal version.number, installation1.reload.integration_version_number
    assert_equal version.number, installation2.reload.integration_version_number
  end

  test "supports upgrades cancellation" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    installation = make_integration_installation(target: create(:organization), integration: @integration)
    version      = create(:integration_version, integration: @integration)

    enable_feature_flag(:cancel_upgrade_integration_installation_version_job, @integration)
    UpgradeIntegrationInstallationVersionJob.perform_now(@integration.id, nil, version.number)

    assert_count("cancelled", expected_tags: ["popular:false"])
    refute_equal version.number, installation.reload.integration_version_number
  end

  test "supports per-batch retries" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    installation_1 = make_integration_installation(target: create(:organization), integration: @integration)
    installation_2 = make_integration_installation(target: create(:organization), integration: @integration)
    version      = create(:integration_version, integration: @integration)


    UpgradeIntegrationInstallationVersionJob.stub_const(:BATCH_SIZE, 1) do
      # Assert we retry once per batch and that all batches are processed
      IntegrationInstallation.any_instance.expects(:auto_update_version).times(4).
        raises(ActiveRecord::ActiveRecordError.new("something went wrong!"))

      expected_retry_logs = {
        "gh.job.name" => "UpgradeIntegrationInstallationVersionJob",
        "gh.job.action" => "retry",
        "gh.integration.id" => @integration.id,
        "gh.job.exception_message" => "something went wrong!"
      }

      expected_failed_retry_logs = {
        "gh.job.name" => "UpgradeIntegrationInstallationVersionJob",
        "gh.job.action" => "failed_retry",
        "gh.integration.id" => @integration.id,
        "gh.job.exception_message" => "something went wrong!"
      }

      captured_log = capture_logs do
        UpgradeIntegrationInstallationVersionJob.perform_now(@integration.id, nil, version.number)
      end

      captured_log.each_line.with_index do |line, index|
        if index == 0 || index == 2
          expected_retry_logs.each do |k, v|
            assert_log_match(line, k, v)
          end
        else
          expected_failed_retry_logs.each do |k, v|
            assert_log_match(line, k, v)
          end
        end
      end

      assert_count("process_batch.retry", expected_tags: ["popular:false"])
      assert_count("process_batch.failed_retry", expected_tags: ["popular:false"])
    end
  end

  test "supports retries when errors occur" do
    version = create(:integration_version, integration: @integration)

    assert_retry_on_dirty_exit job: UpgradeIntegrationInstallationVersionJob, args: [@integration.id, nil, version.number]
    assert_retry_on_throttler_error job: UpgradeIntegrationInstallationVersionJob, args: [@integration.id, nil, version.number]
  end

  context "instrumentation" do
    test "it emits total_installations, updated_installations and finished metrics" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      2.times { make_integration_installation(target: create(:organization), integration: @integration) }
      version = create(:integration_version, integration: @integration)

      UpgradeIntegrationInstallationVersionJob.perform_now(@integration.id, nil, version.number)

      assert_distribution_values("total_installations", expected_values: [2], expected_tags: ["popular:false"])
      assert_distribution_values("updated_installations", expected_values: [2], expected_tags: ["popular:false"])

      assert_count("finished", expected_tags: ["popular:false"])
    end

    test "it emits tags for popular apps" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      2.times { make_integration_installation(target: create(:organization), integration: @integration) }
      version = create(:integration_version, integration: @integration)

      UpgradeIntegrationInstallationVersionJob.stub_const(:MINIMIMUM_POPULAR_INSTALLATIONS_COUNT, 1) do
        UpgradeIntegrationInstallationVersionJob.perform_now(@integration.id, nil, version.number)
      end

      assert_distribution_values(
        "total_installations",
        expected_values: [2],
        expected_tags: ["popular:true", "integration:#{@integration.slug}"]
      )
      assert_distribution_values(
        "updated_installations",
        expected_values: [2],
        expected_tags: ["popular:true", "integration:#{@integration.slug}"]
      )

      assert_count("finished", expected_tags: ["popular:true", "integration:#{@integration.slug}"])
    end

    test "it emits stats for processed installations per second" do
      Timecop.freeze(now = Time.now) do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        2.times { make_integration_installation(target: create(:organization), integration: @integration) }
        version = create(:integration_version, integration: @integration)

        UpgradeIntegrationInstallationVersionJob.perform_now(@integration.id, nil, version.number)
        assert_distribution_values("installations_per_second", expected_values: [2], expected_tags: ["popular:false"])
      end
    end
  end

  def assert_distribution_values(suffix, expected_values:, expected_tags:)
    key = "job.upgrade_integration_installation_version_job.#{suffix}"
    values = GitHub.dogstats.distributions(key, tags: expected_tags).map(&:value)
    assert_equal expected_values, values
  end

  def assert_count(suffix, expected_tags:)
    key = "job.upgrade_integration_installation_version_job.#{suffix}"
    assert_predicate GitHub.dogstats.counts(key, tags: expected_tags), :any?
  end
end
