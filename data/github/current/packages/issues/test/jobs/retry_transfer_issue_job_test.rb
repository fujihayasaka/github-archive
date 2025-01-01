# typed: true
# frozen_string_literal: true

require "test_helper"

class RetryTransferIssueJobTest < GitHub::TestCase
  fixtures do
    @owner = create :user
    @staff = create :staff_admin_user
    @old_repo = create :repository, owner: @owner
    @old_issue = create :issue, repository: @old_repo
    @new_repo = create :repository, owner: @owner
    @new_issue = create :issue, repository: @new_repo

    @label = create :label, repository: @old_repo, name: "special bug"
    @old_issue.labels << @label
    @old_issue.save!
  end

  setup do
    IssueTransfer.create!(
      old_issue: @old_issue,
      old_repository: @old_repo.repository,
      new_repository: @new_repo,
      actor: @owner,
      new_issue: @new_issue,
    )
    @transferred_issue = IssueTransfer.last
  end

  context "successfully transfers issue transfers with errors" do
    test "when old issue still exists" do
      # mock error on issue transfer
      @transferred_issue.update_column(:state, "errored")
      assert_equal "errored", @transferred_issue.state

      RetryTransferIssueJob.perform_now(@old_repo.id, @staff)

      @transferred_issue.reload
      @new_issue.reload
      assert_equal "done", @transferred_issue.state
      assert_empty @new_issue.labels
    end

    test "when old issue still exists and creates new labels" do
      # mock error on issue transfer
      @transferred_issue.update_column(:state, "errored")
      assert_equal "errored", @transferred_issue.state

      RetryTransferIssueJob.perform_now(@old_repo.id, @staff, { create_labels_if_missing: true })

      @transferred_issue.reload
      assert_equal "done", @transferred_issue.state
      assert_equal @label.name, @new_issue.labels.first.name
    end

    test "when old issue no longer exists" do
      # mock error on issue transfer
      @transferred_issue.update_column(:state, "errored")
      @transferred_issue.old_issue.destroy!

      @transferred_issue.reload
      assert_equal "errored", @transferred_issue.state
      assert_nil @transferred_issue.old_issue

      RetryTransferIssueJob.perform_now(@old_repo.id, @staff, {})

      @transferred_issue.reload
      assert_equal "done", @transferred_issue.state
    end
  end
end
