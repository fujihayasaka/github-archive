# typed: true
# frozen_string_literal: true

require "test_helper"

class TransferableIssueTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @user = create(:user)
    @old_repo = create(:private_repository, owner: @org)
    @new_repo = create(:private_repository, owner: @org)
    @old_repo.add_member(@user, action: :write)
    @new_repo.add_member(@user, action: :write)
    @issue = create(:issue, repository: @old_repo)
  end

  context "is_transfer_in_progress?" do
    test "returns true if new issue is being transferred" do
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @old_repo, new_repository: @new_repo, actor: @user)
      transfer.send(:create_copy_issue)

      assert T.must(transfer.new_issue).is_transfer_in_progress?
    end

    test "returns false if new issue is not being transferred" do
      refute @issue.is_transfer_in_progress?
    end
  end

  context "is_being_transferred?" do
    test "returns true if old issue is being transferred" do
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @old_repo, new_repository: @new_repo, actor: @user)
      transfer.send(:create_copy_issue)

      assert @issue.is_being_transferred?
    end

    test "returns false if old issue is not being transferred" do
      refute @issue.is_being_transferred?
    end
  end

  context "is_involved_in_current_transfer?" do
    test "returns true if new issue is being transferred" do
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @old_repo, new_repository: @new_repo, actor: @user)
      transfer.send(:create_copy_issue)

      assert T.must(transfer.new_issue).is_involved_in_current_transfer?
    end

    test "returns true if old issue is being transferred" do
      transfer = IssueTransfer.new(old_issue: @issue, old_repository: @old_repo, new_repository: @new_repo, actor: @user)
      transfer.send(:create_copy_issue)

      assert @issue.is_involved_in_current_transfer?
    end

    test "returns false if neither old nor new issue is being transferred" do
      refute @issue.is_involved_in_current_transfer?
    end
  end
end
