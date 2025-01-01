# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

# issue_types basic tests
class Issues::ReindexIssuesForAssociationJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    GitHub.flipper[:issue_types].enable
    @org = create(:organization)
    @user = create(:user)
    @org.add_member(create(:user))

    @repo = create(:repository, owner: @org)
    @other_repo = create(:repository, owner: @org)

    @issue_type = create :issue_type, owner: @org
  end

  test "queues up indexing jobs for all issues having a given issue_type" do
    number_of_issues = 10
    create_typed_issues(number_of_issues)

    Issues::ReindexIssuesForAssociationJob.stub_const(:BATCH_SIZE, 2) do
      assert_enqueued_jobs number_of_issues, only: AddToSearchIndexJob do
        perform_enqueued_jobs only: Issues::ReindexIssuesForAssociationJob do
          Issues::ReindexIssuesForAssociationJob.enqueue(:issue_type, @issue_type.id)
        end
      end
    end
  end

  context "limitted to a specific repo" do
    test "queues up indexing jobs for all issues having a given issue_type" do
      number_of_issues = 10
      create_typed_issues(number_of_issues)

      Issues::ReindexIssuesForAssociationJob.stub_const(:BATCH_SIZE, 2) do
        # We are targetting one of two repos, so half the number of jobs should be executed
        assert_enqueued_jobs (number_of_issues / 2), only: AddToSearchIndexJob do
          perform_enqueued_jobs only: Issues::ReindexIssuesForAssociationJob do
            Issues::ReindexIssuesForAssociationJob.enqueue(:issue_type, @issue_type.id, {
              sharding_key: :repository_id,
              sharding_key_value: @repo.id
            })
          end
        end
      end
    end
  end

  context "resilience" do
    test "retries on recoverable exceptions" do
      Timecop.freeze do
        assert_retry_conditions(
          job: Issues::ReindexIssuesForAssociationJob,
          args: [
            association_name: :issue_type,
            association_id: @issue_type.id,
            submitted_at: Timestamp.from_time(Time.now.utc)
          ],
          using_kwargs: true
        ) do
          Issues::ReindexIssuesForAssociationJob.enqueue(:issue_type, @issue_type.id)
        end
      end
    end

    test "retries on WaitForReplication::DataUnavailable error" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      # Simulate replication delay
      stub = WaitForReplication
        .any_instance
        .stubs(:wait!)
      5.times do
        stub = stub.raises(
          WaitForReplication::DataUnavailable.new(
            store_name: @issue_type.cluster_name,
            wait_required: 5.0,
            max_wait: 8.0
          )).then
      end
      stub.returns(nil)

      perform_enqueued_jobs only: Issues::ReindexIssuesForAssociationJob do
        Issues::ReindexIssuesForAssociationJob.enqueue(:issue_type, @issue_type.id)
      end

      assert_equal 5, GitHub.dogstats.increments("active_job.retry", tags: [
        "class:issues/reindex_issues_for_association_job",
        "queue:index_high",
        "adapter:#{Issues::ReindexIssuesForAssociationJob.queue_adapter_name}",
        "error:wait_for_replication/data_unavailable",
      ]).length
    end
  end

  private

  def create_typed_issues(number_of_issues)
    number_of_issues.times do |i|
      target_repo = i.even? ? @repo : @other_repo
      create :issue, repository: target_repo, issue_type: @issue_type
    end
  end
end

# labels and milestones (port tests from EnqueueIssuesSearchIndexJobsJob to ensure equivelency)
class Issues::ReindexIssuesForAssociationJobMilestonesLabelsTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @other_repo = create(:repository, owner: @user)

    # supported types now are milestones and labels so adding both of these.
    @milestone = create :milestone, repository: @repo, created_by: @repo.owner
    @label = create :label, repository: @repo
  end

  context "perform job" do
    test "queues up individual jobs for each of the enqueued milestone's issues" do
      number_of_issues = 5
      create_issues_for_milestone(number_of_issues)

      queues_up_individual_jobs_for_each_of_enqueued_records_issues(:milestone, @milestone.id, @milestone.issues)
    end

    test "queues up individual jobs for each of the enqueued label's issues" do
      number_of_issues = 5
      number_of_issues.times do
        issue = create :issue, repository: @repo, user: @repo.owner
        issue.labels << @label
      end

      queues_up_individual_jobs_for_each_of_enqueued_records_issues(:labels, @label.id, @label.repository_restricted_issues)
    end

    # test AddToSearchIndexJob job args, no easy way to validate args of multiple queued jobs.
    test "fire with only one job" do
      issue = create :issue, repository: @repo, user: @repo.owner, milestone: @milestone

      expected_args = ->(args) do
        assert_equal "issue", args[0]
        assert_equal issue.id, args[1]
      end

      assert_enqueued_with(job: AddToSearchIndexJob, args: expected_args, queue: "index_high") do
        queues_up_individual_jobs_for_each_of_enqueued_records_issues(:milestone, @milestone.id, @milestone.issues)
      end
    end

    test "exit gracefully if milestone deleted" do
      assert_nothing_raised do
        assert_no_enqueued_jobs do
          Issues::ReindexIssuesForAssociationJob.perform_now(
            association_name: :milestone,
            association_id: Milestone.maximum(:id).next,
            submitted_at: Time.now)
        end
      end
    end

    test "re-enqueues the job if GitHub::Restraint::UnableToLock error is raised" do
      Issues::ReindexIssuesForAssociationJob.any_instance.stubs(:perform).raises(GitHub::Restraint::UnableToLock)

      expected_args = ->(args) do
        named = args[0]
        assert_equal :milestone, named[:association_name]
        assert_equal @milestone.id, named[:association_id]
      end

      submitted_at = Time.now
      assert_enqueued_with(job: Issues::ReindexIssuesForAssociationJob, args: expected_args) do
        Issues::ReindexIssuesForAssociationJob.perform_now(
          association_name: :milestone,
          association_id: @milestone.id,
          submitted_at: Time.now)
      end
    end
  end

  private

  def create_issues_for_milestone(number_of_issues)
    number_of_issues.times do
      create :issue, repository: @repo, user: @repo.owner, milestone: @milestone
    end
  end

  def queues_up_individual_jobs_for_each_of_enqueued_records_issues(type, id, issues)
    Issues::ReindexIssuesForAssociationJob.stub_const(:BATCH_SIZE, 2) do
      assert_enqueued_jobs issues.size, only: AddToSearchIndexJob do
        perform_enqueued_jobs only: Issues::ReindexIssuesForAssociationJob do
          Issues::ReindexIssuesForAssociationJob.enqueue(type, id)
        end
      end
    end
  end
end
