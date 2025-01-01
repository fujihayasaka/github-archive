# typed: true
# frozen_string_literal: true
require "test_helper"

class DanglingIssueOrchestrationStarterJobTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  test "starts dangling orchestrations in the 'created' state and 'set_assignees' step" do
    issue = Timecop.freeze(30.seconds.ago) do
      CreateIssueOrchestration.any_instance.stubs(:execute)

      create(:issue, repository: @repo)
    end

    orchestration = T.must(CreateIssueOrchestration.find_by(issue_id: issue.id))
    assert_equal :created, orchestration.state.to_sym
    assert_equal "set_assignees", orchestration.step_name

    CreateIssueOrchestration.any_instance.unstub(:execute)

    perform_enqueued_jobs only: [IssueOrchestration.job_class] do
      DanglingIssueOrchestrationStarterJob.perform_now
    end

    assert_equal :succeeded, orchestration.reload.state.to_sym
  end

  test "starts dangling orchestrations in the 'created' state and 'job_start' step" do
    issue = Timecop.freeze(30.seconds.ago) do
      CreateIssueOrchestration.any_instance.stubs(:execute)

      create(:issue, repository: @repo)
    end

    orchestration = T.must(CreateIssueOrchestration.find_by(issue_id: issue.id))
    assert_equal :created, orchestration.state.to_sym

    orchestration.update_column(:step_name, "job_start")
    assert_equal "job_start", orchestration.step_name

    CreateIssueOrchestration.any_instance.unstub(:execute)

    perform_enqueued_jobs only: [IssueOrchestration.job_class] do
      DanglingIssueOrchestrationStarterJob.perform_now
    end

    assert_equal :succeeded, orchestration.reload.state.to_sym
  end

  test "starts dangling orchestrations in the 'started' state and 'set_assignees' step" do
    issue = Timecop.freeze(30.seconds.ago) do
      CreateIssueOrchestration.any_instance.stubs(:execute)

      create(:issue, repository: @repo)
    end

    orchestration = T.must(CreateIssueOrchestration.find_by(issue_id: issue.id))
    orchestration.update_column(:state, :started)

    assert_equal :started, orchestration.state.to_sym
    assert_equal "set_assignees", orchestration.step_name

    CreateIssueOrchestration.any_instance.unstub(:execute)

    perform_enqueued_jobs only: [IssueOrchestration.job_class] do
      DanglingIssueOrchestrationStarterJob.perform_now
    end

    assert_equal :succeeded, orchestration.reload.state.to_sym
  end

  test "starts dangling orchestrations in the 'started' state and 'job_start' step" do
    issue = Timecop.freeze(30.seconds.ago) do
      CreateIssueOrchestration.any_instance.stubs(:execute)

      create(:issue, repository: @repo)
    end

    orchestration = T.must(CreateIssueOrchestration.find_by(issue_id: issue.id))
    orchestration.update_column(:state, :started)
    orchestration.update_column(:step_name, "job_start")

    assert_equal :started, orchestration.state.to_sym
    assert_equal "job_start", orchestration.step_name

    CreateIssueOrchestration.any_instance.unstub(:execute)

    perform_enqueued_jobs only: [IssueOrchestration.job_class] do
      DanglingIssueOrchestrationStarterJob.perform_now
    end

    assert_equal :succeeded, orchestration.reload.state.to_sym
  end

  test "only starts dangling orchestrations on step 'job_start' or 'set_assignees'" do
    issue = Timecop.freeze(30.seconds.ago) do
      CreateIssueOrchestration.any_instance.stubs(:execute)

      create(:issue, repository: @repo)
    end

    orchestration = T.must(CreateIssueOrchestration.find_by(issue_id: issue.id))
    assert_equal :created, orchestration.state.to_sym

    orchestration.update_column(:step_name, "abc")

    CreateIssueOrchestration.any_instance.expects(:execute).never

    perform_enqueued_jobs only: [IssueOrchestration.job_class] do
      DanglingIssueOrchestrationStarterJob.perform_now
    end

    assert_equal :created, orchestration.reload.state.to_sym
  end

  test "doesn't start dangling orchestrations outside of configured time interval" do
    CreateIssueOrchestration.any_instance.stubs(:execute)

    issue = create(:issue, repository: @repo)

    orchestration = T.must(CreateIssueOrchestration.find_by(issue_id: issue.id))
    assert_equal :created, orchestration.state.to_sym

    perform_enqueued_jobs only: [IssueOrchestration.job_class] do
      DanglingIssueOrchestrationStarterJob.perform_now
    end

    assert_equal :created, orchestration.reload.state.to_sym
  end

  test "swallows validation errors during orchestration execution" do
    issue = Timecop.freeze(30.seconds.ago) do
      CreateIssueOrchestration.any_instance.stubs(:execute)

      create(:issue, repository: @repo)
    end

    orchestration = T.must(CreateIssueOrchestration.find_by(issue_id: issue.id))
    assert_equal :created, orchestration.state.to_sym

    orchestration.update_column(:issue_id, nil)

    CreateIssueOrchestration.any_instance.expects(:execute).once

    perform_enqueued_jobs only: [IssueOrchestration.job_class] do
      DanglingIssueOrchestrationStarterJob.perform_now
    end

    assert_equal :created, orchestration.reload.state.to_sym
  end

  test "batching respects input timestamp" do
    issue = Timecop.freeze(9.minutes.ago - 30.seconds) do
      CreateIssueOrchestration.any_instance.stubs(:execute)

      create(:issue, repository: @repo)
    end

    batch = IssueOrchestration.dangling_orchestrations_batch(9.minutes.ago, 0, 5)

    assert_equal 1, batch.size
    assert_equal issue.id, batch.first.issue_id
  end

  test "job exits if too much time has passed" do
    issue = Timecop.freeze(30.seconds.ago) do
      CreateIssueOrchestration.any_instance.stubs(:execute)

      create(:issue, repository: @repo)
    end

    orchestration = T.must(CreateIssueOrchestration.find_by(issue_id: issue.id))

    # just validate that we can compute the next batch here.
    next_batch = DanglingIssueOrchestrationStarterJob.new.next_batch

    assert_equal 1, next_batch.size
    assert_equal orchestration.id, next_batch.first.id

    # now travel back in time - the job started 2 min ago.
    job_start = 2.minutes.ago
    next_batch = DanglingIssueOrchestrationStarterJob.new.next_batch(timestamp: job_start)

    assert_predicate next_batch, :empty?

  end

  context "batches correctly" do
    test "when batch size is evenly divisible by total count" do
      batches_correctly(batch_size: 2, total_size: 4)
    end

    test "when batch size isn't evenly divisible by total count" do
      batches_correctly(batch_size: 2, total_size: 5)
    end

    test "when batch size is higher than total count" do
      batches_correctly(batch_size: 5, total_size: 2)
    end

    test "when batch size matches total count" do
      batches_correctly(batch_size: 2, total_size: 2)
    end

    test "when no matches" do
      batches_correctly(batch_size: 12, total_size: 0)
    end
  end

  def batches_correctly(batch_size:, total_size:)
    DanglingIssueOrchestrationStarterJob.stub_const(:BATCH_SIZE, batch_size) do
      orchestrations = []

      Timecop.freeze(30.seconds.ago) do
        CreateIssueOrchestration.any_instance.stubs(:execute)

        total_size.times do
          issue = create(:issue, repository: @repo)

          orchestration = T.must(IssueOrchestration.find_by(issue_id: issue.id, type: "CreateIssueOrchestration"))

          assert_equal :created, orchestration.state.to_sym

          orchestrations << orchestration
        end
      end

      CreateIssueOrchestration.any_instance.unstub(:execute)

      # should perform 2 out of the three orchestrations.
      perform_enqueued_jobs only: [IssueOrchestration.job_class, DanglingIssueOrchestrationStarterJob] do
        DanglingIssueOrchestrationStarterJob.perform_now
      end

      orchestrations.each do |orchestration|
        assert_equal :succeeded, orchestration.reload.state.to_sym
      end
    end
  end
end unless GitHub.enterprise?
