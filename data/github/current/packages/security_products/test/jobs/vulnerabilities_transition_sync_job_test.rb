# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class VulnerabilitiesTransitionSyncJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers

  fixtures do
    @vuln = create(:vulnerability)
    # This is to avoid id collisions with the Vulnerability model
    first_scoped_vuln_id = Vulnerability.last&.id.to_i + 1000
    @open_source_vuln = create(:open_source_vulnerability, id: first_scoped_vuln_id)
    @innersource_vuln = create(:innersource_vulnerability)

    @scoped_vulnerability = VulnerabilitiesTransitionSyncJob::ScopedVulnerability
    @vulnerability = VulnerabilitiesTransitionSyncJob::Vulnerability
  end

  setup do
    GitHub.flipper[:innersource_sync].enable
    GitHub.flipper[:innersource_sync_direction_reverse].disable
  end

  test "a vulnerability can be synced with corresponding scoped vulnerability" do
    refute @scoped_vulnerability.exists?(id: @vuln.id)
    VulnerabilitiesTransitionSyncJob.perform_now(@vuln.id, direction: :to_scoped_vulnerabilities)
    assert scoped_vuln = @scoped_vulnerability.find_by(id: @vuln.id)
    assert_equal @vuln.ghsa_id, scoped_vuln&.ghsa_id
  end

  test "a scoped vulnerability can be synced with corresponding vulnerability" do
    refute @vulnerability.exists?(id: @open_source_vuln.id)
    VulnerabilitiesTransitionSyncJob.perform_now(@open_source_vuln.id, direction: :to_vulnerabilities)
    assert vuln = @vulnerability.find_by(id: @open_source_vuln.id)
    assert_equal @open_source_vuln.ghsa_id, vuln&.ghsa_id
  end

  test "can sync back and forth" do
    refute @scoped_vulnerability.exists?(id: @vuln.id)
    VulnerabilitiesTransitionSyncJob.perform_now(@vuln.id, direction: :to_scoped_vulnerabilities)
    assert scoped_vuln = @scoped_vulnerability.find_by(id: @vuln.id)
    assert_equal "open_source", scoped_vuln&.scope
    assert_equal @vuln.description, scoped_vuln&.description

    scoped_vuln.update!(description: "new description")
    refute_equal @vuln.description, scoped_vuln&.description

    VulnerabilitiesTransitionSyncJob.perform_now(scoped_vuln&.id, direction: :to_vulnerabilities)
    @vuln.reload
    assert_equal @vuln.description, scoped_vuln&.description
  end

  test "an innersource vulnerability cannot be synced to vulnerabilities table" do
    refute @vulnerability.find_by(id: @innersource_vuln.id)
    VulnerabilitiesTransitionSyncJob.perform_now(@innersource_vuln.id, direction: :to_vulnerabilities)
    refute @vulnerability.find_by(id: @innersource_vuln.id)
  end

  test "the job is disabled when ff is off" do
    GitHub.flipper[:innersource_sync].disable
    assert_enqueued_jobs 0, only: VulnerabilitiesTransitionSyncJob do
      VulnerabilitiesTransitionSyncJob.perform_now(@vuln.id)
    end
  end

  test "defaults to syncing from vulnerabilities table" do
    VulnerabilitiesTransitionSyncJob.perform_now(@vuln.id)
    assert @scoped_vulnerability.find_by(id: @vuln.id)
  end

  test "ff switches syncing to start from scoped vulnerabilities table" do
    GitHub.flipper[:innersource_sync_direction_reverse].enable
    VulnerabilitiesTransitionSyncJob.perform_now(@open_source_vuln)
    assert @vulnerability.find_by(id: @open_source_vuln.id)
  end

  test "job retries on dirty exit and other errors successfully" do
    assert_retry_conditions job: VulnerabilitiesTransitionSyncJob, args: [@vuln.id]
  end

  test "job is idempotent" do
    refute @scoped_vulnerability.exists?(id: @vuln.id)
    VulnerabilitiesTransitionSyncJob.perform_now(@vuln.id)
    first_scoped_vuln_attr = @scoped_vulnerability.find_by(id: @vuln.id).attributes
    VulnerabilitiesTransitionSyncJob.perform_now(@vuln.id)
    second_scoped_vuln_attr = @scoped_vulnerability.find_by(id: @vuln.id).attributes

    assert_equal first_scoped_vuln_attr, second_scoped_vuln_attr
  end

  test "instruments job volume" do
    VulnerabilitiesTransitionSyncJob.perform_now(@vuln.id)
    VulnerabilitiesTransitionSyncJob.perform_now(@open_source_vuln.id, direction: :to_vulnerabilities)
    assert_dogstats_increment 1, "vulnerabilities_transition_sync.run", tags: ["sync_direction:to_scoped_vulnerabilities"]
    assert_dogstats_increment 1, "vulnerabilities_transition_sync.run", tags: ["sync_direction:to_vulnerabilities"]
  end

  test "instruments replication lag" do
    WaitForReplication.any_instance.stubs(:wait!).returns(2)
    WaitForReplication.any_instance.expects(:wait!)
    VulnerabilitiesTransitionSyncJob.perform_now(@vuln.id)
    assert_dogstats_timing "vulnerabilities_transition_sync.replication.duration", tags: ["sync_direction:to_scoped_vulnerabilities"]
  end

  test "errors retried report to failbot when exhausted" do
    @vulnerability.stubs(:find_by!).raises(ActiveRecord::RecordNotFound)
    Failbot.expects(:report).with(
      instance_of(ActiveRecord::RecordNotFound),
      has_entries(
        vulnerability_id: @vuln.id
      )
    )

    perform_enqueued_jobs(only: [VulnerabilitiesTransitionSyncJob]) do
      VulnerabilitiesTransitionSyncJob.perform_now(@vuln.id)
    end
  end

  test "callbacks are run when syncing to vulnerabilities table" do
    GitHub.flipper[:innersource_sync_direction_reverse].enable

    advisory = create(:repository_advisory)
    scoped_vuln = create(:open_source_vulnerability, ghsa_id: advisory.ghsa_id)
    vvr = create(:vulnerable_version_range, vulnerability_id: scoped_vuln.id)

    # create
    Vulnerability.any_instance.expects(:synchronize_search_index).at_least_once
    #update
    unless GitHub.single_or_multi_tenant_enterprise?
      Vulnerability.any_instance.expects(:update_repo_advisory_status).at_least_once
    end
    Vulnerability.any_instance.expects(:notify_security_center).at_least_once
    Vulnerability.any_instance.expects(:expire_github_kvs).at_least_once

    VulnerabilitiesTransitionSyncJob.perform_now(scoped_vuln.id, direction: :to_vulnerabilities)

    scoped_vuln.update(severity: :low)
    VulnerabilitiesTransitionSyncJob.perform_now(scoped_vuln.id, direction: :to_vulnerabilities)

    scoped_vuln.update(status: :withdrawn)
    VulnerabilitiesTransitionSyncJob.perform_now(scoped_vuln.id, direction: :to_vulnerabilities)
  end
end
