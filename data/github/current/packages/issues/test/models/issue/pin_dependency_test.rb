# typed: true
# frozen_string_literal: true

require "test_helper"

class IssuePinDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @writer = create(:user)
    @anon = create(:user)

    @org = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)
    @repo.add_member(@writer, action: :write)

    @issue = create(:issue, repository: @repo, user: @user)
  end

  test "pins a issue as admin" do
    @issue.pin(actor: @user)

    assert @issue.pinned?
  end

  test "pins a issue as writer" do
    @issue.pin(actor: @writer)

    assert @issue.pinned?
  end

  test "does not pin a issue if not write" do
    @issue.pin(actor: @anon)

    refute @issue.pinned?
  end

  test "does not pin a issue if a pull request" do
    @issue.stubs(:pull_request?).returns(true)
    @issue.pin(actor: @user)

    refute @issue.pinned?
  end

  test "does not pin a issue if already 3 pinned issues" do
    issue1 = create(:issue, repository: @repo, user: @user)
    issue2 = create(:issue, repository: @repo, user: @user)
    issue3 = create(:issue, repository: @repo, user: @user)

    issue1.pin(actor: @user)
    issue2.pin(actor: @user)
    issue3.pin(actor: @user)
    @issue.pin(actor: @user)

    refute @issue.pinned?
  end

  test "unpins a issue" do
    @issue.pin(actor: @user)
    pinned_issue = @repo.pinned_issues.find_by(issue_id: @issue.id)
    assert @issue.pinned?

    deleted_record = @issue.unpin(actor: @user)

    @issue.reload
    refute @issue.pinned?
    assert_equal deleted_record.id, pinned_issue.id
  end
end
