# typed: true
# frozen_string_literal: true

require "test_helper"

class DeletedIssueTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)

    @org = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)

    @collaborator = create(:user)
    @repo.add_member(@collaborator)

    @issue = create(:issue, repository: @repo, user: @user)
  end

  test "deletes the issue" do
    DeletedIssue.delete_issue(@issue, deleter: @user)
    assert_raises(ActiveRecord::RecordNotFound) { @issue.reload }
  end

  test "triggers a deletion webhook" do
    Hook::DeliverySystem.any_instance.expects(:deliver_later)
    DeletedIssue.delete_issue(@issue, deleter: @user)
  end

  test "does not trigger a deletion webhook for a spammy user", skip_enterprise: true do
    spammy_user = create :spammy_user
    repo = create :repository
    issue = create(:issue, repository: repo, user: spammy_user)

    Hook::DeliverySystem.any_instance.expects(:deliver_later).never
    DeletedIssue.delete_issue(issue, deleter: spammy_user)
  end


  context "hydro events" do
    test "sends hydro event on delete" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      DeletedIssue.delete_issue(@issue, deleter: @user)

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(@user),
        repository: Hydro::EntitySerializer.repository(@repo),
        issue: Hydro::EntitySerializer.issue(@issue),
      }
      assert_hydro_published(message, schema: "github.v1.IssueDeleted")
    end
  end
end
