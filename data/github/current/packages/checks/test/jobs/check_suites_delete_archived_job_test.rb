# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckSuitesDeleteArchiveJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :simple)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(@launch_app)

    if GitHub.enterprise?
      GitHub.stubs(:checks_retention_enabled?).returns(true)
      GitHub.stubs(:checks_retention_archive_threshold).returns(400)
    end
  end

  context "input" do
    test "throws error if updated_at_start is not provided" do
      assert_raises(ArgumentError) do
        CheckSuitesDeleteArchivedJob.perform_now(updated_at_start: nil, updated_at_end: 10, concurrent_job_key: "check_suites_delete_archived_job_0")
      end
    end

    test "throws error if updated_at_end is not provided" do
      assert_raises(ArgumentError) do
        CheckSuitesDeleteArchivedJob.perform_now(updated_at_start: 1, updated_at_end: nil, concurrent_job_key: "check_suites_delete_archived_job_0")
      end
    end

    test "throws error if concurrent_job_key is not provided" do
      assert_raises(ArgumentError) do
        CheckSuitesDeleteArchivedJob.perform_now(updated_at_start: 1, updated_at_end: 10, concurrent_job_key: nil)
      end
    end
  end

  context "third party check suites" do
    test "deletes archived records records" do
      archived_check_suite = create_third_party_check_suite_with_all_entities(11.days.ago)
      non_archived_check_suite = create_third_party_check_suite_with_all_entities(nil)

      CheckSuitesDeleteArchivedJob.perform_now(updated_at_start: 12.days.ago, updated_at_end: Time.now, concurrent_job_key: "check_suites_delete_archived_job_0")

      assert_check_suite_and_entities_deleted(archived_check_suite)
      refute_check_suite_and_entities_deleted(non_archived_check_suite)
      assert_dogstats_count_value 1, "checks.delete_archived_job.deleted", tags: ["model:checksuite"]
    end

    test "deletes archived records and all their dependencies" do
      outside_window_old_archived_check_suite = create_third_party_check_suite_with_all_entities(15.days.ago)
      older_archived_check_suite = create_third_party_check_suite_with_all_entities(13.days.ago)
      archived_check_suite = create_third_party_check_suite_with_all_entities(11.days.ago)
      not_old_enough_archived_check_suite = create_third_party_check_suite_with_all_entities(9.days.ago)
      non_archived_cs = create_third_party_check_suite_with_all_entities(nil)

      CheckSuitesDeleteArchivedJob.perform_now(updated_at_start: 14.days.ago, updated_at_end: Time.now, concurrent_job_key: "check_suites_delete_archived_job_0")

      refute_check_suite_and_entities_deleted(outside_window_old_archived_check_suite) # outside_window_old_archived_check_suite is 15 days old but the updated_at timestap window (14 days) passed into CheckSuitesDeleteArchivedJob does not account for it so it should not be deleted
      assert_check_suite_and_entities_deleted(older_archived_check_suite)
      assert_check_suite_and_entities_deleted(archived_check_suite)
      refute_check_suite_and_entities_deleted(not_old_enough_archived_check_suite)
      refute_check_suite_and_entities_deleted(non_archived_cs)

      assert_dogstats_count_value 2, "checks.delete_archived_job.deleted", tags: ["model:checksuite"]
    end
  end

  context "actions check suites" do
    test "deletes archived records" do
      archived_cs = create_actions_check_suite_with_all_entities(11.days.ago)
      non_archived_check_suite_with_entities = create_actions_check_suite_with_all_entities(nil)

      CheckSuitesDeleteArchivedJob.perform_now(updated_at_start: 12.days.ago, updated_at_end: Time.now, concurrent_job_key: "check_suites_delete_archived_job_0")

      assert_check_suite_and_entities_deleted(archived_cs)
      refute_check_suite_and_entities_deleted(non_archived_check_suite_with_entities)
      assert_dogstats_count_value 1, "checks.delete_archived_job.deleted", tags: ["model:checksuite"]
    end

    test "deletes archived records and all their dependencies" do
      outside_window_check_suite = create_actions_check_suite_with_all_entities(15.days.ago)
      old_archived_cs1 = create_actions_check_suite_with_all_entities(13.days.ago)
      old_archived_cs2 = create_actions_check_suite_with_all_entities(11.days.ago)
      too_recent_archived_check_suite = create_actions_check_suite_with_all_entities(9.days.ago)
      non_archived_check_suite = create_actions_check_suite_with_all_entities(nil)

      CheckSuitesDeleteArchivedJob.perform_now(updated_at_start: 14.days.ago, updated_at_end: Time.now, concurrent_job_key: "check_suites_delete_archived_job_0")

      refute_check_suite_and_entities_deleted(outside_window_check_suite)
      assert_check_suite_and_entities_deleted(old_archived_cs1)
      assert_check_suite_and_entities_deleted(old_archived_cs2)
      refute_check_suite_and_entities_deleted(too_recent_archived_check_suite)
      refute_check_suite_and_entities_deleted(non_archived_check_suite)
      assert_dogstats_count_value 2, "checks.delete_archived_job.deleted", tags: ["model:checksuite"]
    end

    test "elastic search correctly removes workflow run indexes" do
      archived_check_suite_with_entities = perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        create_actions_check_suite_with_all_entities(11.days.ago, true)
      end
      non_archived_check_suite_with_entities = perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
        create_actions_check_suite_with_all_entities(nil, true)
      end

      archived_workflow_run = archived_check_suite_with_entities[1]
      non_archived_workflow_run = non_archived_check_suite_with_entities[1]

      search_result_before_deletion = Actions::WorkflowRun.search(query: "", repo: @repo)
      assert_equal 2, search_result_before_deletion[:workflow_runs].count

      perform_enqueued_jobs(only: [RemoveFromSearchIndexJob]) do
        CheckSuitesDeleteArchivedJob.perform_now(updated_at_start: 12.days.ago, updated_at_end: Time.now, concurrent_job_key: "check_suites_delete_archived_job_0")
      end

      assert_check_suite_and_entities_deleted(archived_check_suite_with_entities)
      refute_check_suite_and_entities_deleted(non_archived_check_suite_with_entities)
      assert_dogstats_count_value 1, "checks.delete_archived_job.deleted", tags: ["model:checksuite"]
      assert_dogstats_count_value 1, "checks.delete_archived_job.enqueued_remove_from_search_index_jobs"

      search_result_after_deletion = Actions::WorkflowRun.search(query: "", repo: @repo)
      assert_equal 1, search_result_after_deletion[:workflow_runs].count
      assert_equal non_archived_workflow_run.id, search_result_after_deletion[:workflow_runs].first.id
    end

    test "deletes archived records and emit deletion events to hydro" do
      non_actions_suites = create_list(:check_suite, 10, :completed, :success, repository: @repo, archived_at: 11.days.ago, updated_at: 11.days.ago)
      actions_suites = create_list(:check_suite_for_actions_app, 10, :completed, :success, repository: @repo, archived_at: 11.days.ago, updated_at: 11.days.ago)

      CheckSuitesDeleteArchivedJob.perform_now(updated_at_start: 12.days.ago, updated_at_end: Time.now, concurrent_job_key: "check_suites_delete_archived_job_0")

      actions_suites.map(&:workflow_run).each do |workflow_run|
        workflow_run.workflow_run_executions.each do |execution|
          assert_hydro_published({
            repository_id: workflow_run.repository_id,
            workflow_run_id: workflow_run.id,
            check_suite_id: workflow_run.check_suite_id,
            workflow_run_backend_id: execution.external_id
          }, schema: "github.actions.v0.WorkflowRunDeleted")
        end

        assert_nil CheckSuite.find_by(id: workflow_run.check_suite_id)
        assert_nil Actions::WorkflowRun.find_by(id: workflow_run.id)
      end

      assert_hydro_messages(count: 10, schema: "github.actions.v0.WorkflowRunDeleted")
      assert_dogstats_count_value 20, "checks.delete_archived_job.deleted", tags: ["model:checksuite"]
    end
  end

  context "third party and actions check suites" do
    test "deletes all their dependencies" do
      outside_window_actions_check_suite = create_actions_check_suite_with_all_entities(15.days.ago)
      outside_window_third_party_check_suite = create_third_party_check_suite_with_all_entities(15.days.ago)

      old_archived_actions_check_suite1 = create_actions_check_suite_with_all_entities(13.days.ago)
      old_archived_third_party_check_suite1 = create_third_party_check_suite_with_all_entities(13.days.ago)

      old_archived_actions_check_suite2 = create_actions_check_suite_with_all_entities(11.days.ago)
      old_archived_third_party_check_suite2 = create_third_party_check_suite_with_all_entities(11.days.ago)

      too_recent_archived_actions_check_suite = create_actions_check_suite_with_all_entities(9.days.ago)
      too_recent_archived_third_party_check_suite = create_third_party_check_suite_with_all_entities(9.days.ago)

      non_archived_actions_check_suite = create_actions_check_suite_with_all_entities(nil)
      non_archived_third_party_check_suite = create_third_party_check_suite_with_all_entities(nil)

      CheckSuitesDeleteArchivedJob.perform_now(updated_at_start: 14.days.ago, updated_at_end: Time.now, concurrent_job_key: "check_suites_delete_archived_job_0")

      refute_check_suite_and_entities_deleted(outside_window_actions_check_suite)
      refute_check_suite_and_entities_deleted(outside_window_third_party_check_suite)

      assert_check_suite_and_entities_deleted(old_archived_actions_check_suite1)
      assert_check_suite_and_entities_deleted(old_archived_third_party_check_suite1)

      assert_check_suite_and_entities_deleted(old_archived_actions_check_suite2)
      assert_check_suite_and_entities_deleted(old_archived_third_party_check_suite2)

      refute_check_suite_and_entities_deleted(too_recent_archived_actions_check_suite)
      refute_check_suite_and_entities_deleted(too_recent_archived_third_party_check_suite)

      refute_check_suite_and_entities_deleted(non_archived_actions_check_suite)
      refute_check_suite_and_entities_deleted(non_archived_third_party_check_suite)

      assert_dogstats_count_value 4, "checks.delete_archived_job.deleted", tags: ["model:checksuite"]
    end

    test "deletes all their dependencies with custom delete archived window on enterprise", enterprise_only: true do
      enable_feature_flag(:check_suites_delete_archived)
      GitHub.stubs(:checks_retention_delete_threshold).returns(12) # default is 10 but can be customized on GHES

      outside_window_actions_check_suite = create_actions_check_suite_with_all_entities(15.days.ago)
      outside_window_third_party_check_suite = create_third_party_check_suite_with_all_entities(15.days.ago)

      old_archived_actions_check_suite1 = create_actions_check_suite_with_all_entities(13.days.ago)
      old_archived_third_party_check_suite1 = create_third_party_check_suite_with_all_entities(13.days.ago)

      old_archived_actions_check_suite2 = create_actions_check_suite_with_all_entities(11.days.ago)
      old_archived_third_party_check_suite2 = create_third_party_check_suite_with_all_entities(11.days.ago)

      too_recent_archived_actions_check_suite = create_actions_check_suite_with_all_entities(9.days.ago)
      too_recent_archived_third_party_check_suite = create_third_party_check_suite_with_all_entities(9.days.ago)

      non_archived_actions_check_suite = create_actions_check_suite_with_all_entities(nil)
      non_archived_third_party_check_suite = create_third_party_check_suite_with_all_entities(nil)

      CheckSuitesDeleteArchivedJob.perform_now(updated_at_start: 14.days.ago, updated_at_end: Time.now, concurrent_job_key: "check_suites_delete_archived_job_0")

      refute_check_suite_and_entities_deleted(outside_window_actions_check_suite)
      refute_check_suite_and_entities_deleted(outside_window_third_party_check_suite)

      assert_check_suite_and_entities_deleted(old_archived_actions_check_suite1)
      assert_check_suite_and_entities_deleted(old_archived_third_party_check_suite1)

      # 11 days is older than the default 10 day delete window however the checks_retention_delete_threshold is set to 12 so it should not be deleted
      refute_check_suite_and_entities_deleted(old_archived_actions_check_suite2)
      refute_check_suite_and_entities_deleted(old_archived_third_party_check_suite2)

      refute_check_suite_and_entities_deleted(too_recent_archived_actions_check_suite)
      refute_check_suite_and_entities_deleted(too_recent_archived_third_party_check_suite)

      refute_check_suite_and_entities_deleted(non_archived_actions_check_suite)
      refute_check_suite_and_entities_deleted(non_archived_third_party_check_suite)

      assert_dogstats_count_value 2, "checks.delete_archived_job.deleted", tags: ["model:checksuite"]
    end
  end

  private

  def refute_check_suite_and_entities_deleted(check_suite_and_entities)
    check_suite_and_entities.each do |entity|
      entity.reload
    end
  end

  def assert_check_suite_and_entities_deleted(check_suite_and_entities)
    check_suite_and_entities.each do |entity|
      assert_raises ActiveRecord::RecordNotFound do
        entity.reload
      end
    end
  end

  def create_third_party_check_suite_with_all_entities(archived_at_and_updated_at_time)
    if archived_at_and_updated_at_time.present?
      check_suite = create(:check_suite, :completed, :success, repository: @repo, archived_at: archived_at_and_updated_at_time, updated_at: archived_at_and_updated_at_time)
    else
      check_suite = create(:check_suite, :completed, :success, repository: @repo)
    end

    check_run = create(:check_run, :completed, :success, check_suite: check_suite, repository: @repo)
    check_run_annotation = create(:check_annotation, check_run: check_run)

    [check_suite, check_run, check_run_annotation]
  end

  def create_actions_check_suite_with_all_entities(archived_at_and_updated_at_time, make_searchable = false)
    if archived_at_and_updated_at_time.present?
      check_suite = create(:check_suite_for_actions_app, :completed, :success, repository: @repo, archived_at: archived_at_and_updated_at_time, updated_at: archived_at_and_updated_at_time)
    else
      check_suite = create(:check_suite_for_actions_app, :completed, :success, repository: @repo)
    end

    workflow_run = check_suite.workflow_run
    make_searchable(workflow_run) if make_searchable # add to elastic search

    workflow_run_execution = workflow_run.latest_workflow_run_execution
    check_suite_annotation = create(:check_annotation_for_check_suite, check_suite: check_suite)
    artifact = create(:artifact, check_suite: check_suite)
    check_run1 = create(:check_run_for_actions_app, :completed, :success, check_suite: check_suite, repository: @repo)
    check_run2 = create(:check_run_for_actions_app, :completed, :success, check_suite: check_suite, repository: @repo)
    workflow_job_run1 = check_run1.workflow_job_run
    workflow_job_run2 = check_run2.workflow_job_run
    check_run_annotation = create(:check_annotation, check_run: check_run1)

    [check_suite, workflow_run, check_suite_annotation, artifact, check_run1, check_run2, workflow_job_run1, workflow_job_run2, check_run_annotation]
  end
end
