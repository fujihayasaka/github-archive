# typed: true
# frozen_string_literal: true

require "test_helper"

class AssignmentTest < GitHub::TestCase
  fixtures do
    @repository = create(:repository)
    @issue      = create :issue, repository: @repository
    @assignment = create(:assignment, issue: @issue, assignee: @repository.owner)
    @rando      = create(:user)
  end

  test "the fixture is valid" do
    assert_predicate create(:assignment), :persisted?
  end

  test "cannot create assignment with nonunique assignee/issue" do
    duplicate = build :assignment, issue: @assignment.issue, assignee: @assignment.assignee
    refute_predicate duplicate, :valid?
    assert_includes_match /has already been taken/, duplicate.errors[:assignee_id]
  end

  test "allows non-collaborator with skip_ensure_assignee_is_a_collaborator" do
    @assignment.assignee = @rando
    @assignment.skip_ensure_assignee_is_a_collaborator = true
    assert_predicate @assignment, :valid?
  end

  test "validates assignee is a repo collaborator" do
    @assignment.assignee = @rando
    refute_predicate @assignment, :valid?
    assert_includes @assignment.errors.messages[:assignee], "must be a collaborator"
  end

  test "triggers an assignment event on the parent issue when created" do
    assignee = create :user, login: "assignee-mcgee"
    @repository.add_member assignee

    assert_difference("@issue.events.count", 1) do
      create(:assignment, issue: @issue, assignee: assignee)
    end

    # Event is attributed to the issue creator when it isn't triggered by an
    # actual user.
    #
    # NOTE: The subject and actor are logically swapped.
    assignment_event = @issue.events.last
    assert_equal "assigned",  assignment_event.event
    assert_equal assignee,    assignment_event.actor
    assert_equal @issue.user, assignment_event.subject
  end

  test "triggers an un-assignment event on the parent issue when destroyed" do
    assignee = create :user, login: "assignee-mcgee"
    @repository.add_member assignee
    assignment = create(:assignment, issue: @issue, assignee: assignee)

    assert_difference("@issue.events.count", 1) { assignment.destroy }

    # Event is attributed to the issue creator when it isn't triggered by an
    # actual user.
    #
    # NOTE: The subject and actor are logically swapped.
    assignment_event = @issue.events.last
    assert_equal "unassigned", assignment_event.event
    assert_equal assignee,     assignment_event.actor
    assert_equal @issue.user,  assignment_event.subject
  end

  test "sets `repository_id` from the issue" do
    assignee = create :user, login: "assignee-mcgee"
    @repository.add_member assignee
    assignment = create(:assignment, issue: @issue, assignee: assignee)

    refute_nil assignment.repository_id
    assert_equal @issue.repository_id, assignment.repository_id
  end

  test "skips touching the issue if skip_create_issue_orchestration" do
    assignee = create :user
    @repository.add_member assignee

    @issue.skip_create_issue_orchestration = true
    @issue.expects(:touch).never

    assignment = create(:assignment, issue: @issue, assignee: assignee)
  end

  test "skips touching the issue if skip_touch_issue_updated_at" do
    assignee = create :user
    @repository.add_member assignee

    @issue.expects(:touch).never

    create(:assignment, issue: @issue, assignee: assignee, skip_touch_issue_updated_at: true)
  end

  test "skips touching the issue if feature flag is set" do
    GitHub.flipper[:disable_touch_issue_in_assignment].enable

    assignee = create :user
    @repository.add_member assignee

    @issue.expects(:touch).never

    assignment = create(:assignment, issue: @issue, assignee: assignee)
  end
end
