# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class TransferIssueJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers

  fixtures do
    User.create_ghost
    @owner = create(:user)
    @member = create(:user)
    @org = create(:organization)
    @org.add_member(@owner, action: :admin)
    @org.add_member(@member, action: :write)
    @old_repository = create(:repository, owner: @org)
    @new_repository = create(:repository, owner: @org)
    @old_repository.add_member(@member, action: :write)
    @new_repository.add_member(@member, action: :write)
    @issue = create :issue, title: "Transfer me", user: @member, repository: @old_repository

    @label = create :label, repository: @old_repository, name: "special bug"
    @issue.labels << @label
    @issue.save!
  end

  test "locks by transfer object old_issue's id" do
    new_issue = create :issue, title: "Transfer to me", user: @member, repository: @new_repository
    transfer = IssueTransfer.create!(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, new_issue: new_issue, actor: @member)

    # Force unload the `old_issue` association
    transfer = IssueTransfer.find(T.must(transfer.id))

    _, queries = log_queries do
      job = TransferIssueJob.new(transfer)
      assert_equal @issue.id.to_s, job.lock_key
    end

    assert_equal 0, queries.size
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: TransferIssueJob, args: [nil]
    assert_retry_on_recoverable_exceptions job: TransferIssueJob, args: [nil]
  end

  test "retries job in case of Freno::Throttler::Error" do
    IssueTransfer.any_instance.expects(:complete_transfer).once.raises(Freno::Throttler::Error)
    TransferIssueJob.any_instance.expects(:retry_job)

    transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @member)

    perform_enqueued_jobs(only: TransferIssueJob) do
      transfer.send(:create_copy_issue)
      transfer.save!
      transfer.async_transfer!
    end
  end

  test "retries in case of ActiveRecord::RecordInvalid" do
    IssueTransfer.any_instance.expects(:complete_transfer).once.raises(ActiveRecord::RecordInvalid)
    TransferIssueJob.any_instance.expects(:retry_job)

    transfer = IssueTransfer.new(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @member)

    perform_enqueued_jobs(only: TransferIssueJob) do
      transfer.send(:create_copy_issue)
      transfer.save!
      transfer.async_transfer!
    end
  end

  test "tags with stats context" do
    transfer = IssueTransfer.create(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @member)

    perform_enqueued_jobs(only: TransferIssueJob) do
      transfer.send(:create_copy_issue)
      transfer.save!
      job = transfer.async_transfer!
      assert_equal job.send(:stats_tags), []
    end

    assert_dogstats_increment(:at_least_one, "active_job.performed")

    transfer.reload
    assert_empty T.must(transfer.new_issue).labels
  end

  test "correctly creates label in new repository if the `create_labels_if_missing` flag is set" do
    transfer = IssueTransfer.create(old_issue: @issue, old_repository: @issue.repository, new_repository: @new_repository, actor: @member)

    perform_enqueued_jobs(only: TransferIssueJob) do
      transfer.send(:create_copy_issue)
      transfer.save!
      transfer.async_transfer!(create_labels_if_missing: true)
    end

    transfer.reload
    assert_equal @label.name, T.must(T.must(transfer.new_issue).labels.first).name
  end
end
