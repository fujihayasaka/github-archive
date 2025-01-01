# typed: true
# frozen_string_literal: true

require "test_helper"

class ImportableIssueEventTest < GitHub::TestCase
  fixtures do
    @assigner = create(:user)
    @assignee = create(:user)
    @repo = create(:repository, owner: @assigner)
    @repo.add_member(@assignee)
    @issue = create(:issue, repository: @repo, user: @assigner)

    @issue_event = ImportableIssueEvent.new(issue: @issue, event: "assigned", actor_id: @assignee.id, subject_id: @assigner.id)
    @issue_event.save!
  end

  test "has IssueEvent type" do
    assert_equal "IssueEvent", @issue_event.type
  end

  context "#importing?" do
    test "#importing? returns true during import context" do
      assert @issue_event.importing?
    end

    test "#importing? returns false outside of import context" do
      not_importing = IssueEvent.find(@issue_event.id)
      refute not_importing.importing?
    end
  end
end
