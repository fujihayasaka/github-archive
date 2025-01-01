# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventIssuesEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @issue = create(:issue, user: @user, repository: @repo)
    @label = create(:label, name: "Rainbow Unicorns", repository: @repo)
    @assignee = create(:user)
    @milestone = create(:milestone, created_by: @user, repository: @repo)

    @org = create(:organization, admin: @user)
    @issue_type = @org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])
    @org_repo = create(:repository, owner: @org, from_example: :rebase_pull_request)
    @org_issue = create(:issue, user: @user, repository: @org_repo)
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::IssuesEvent, :action, :issue_id, :actor_id
  end

  context "#issue" do
    test "returns the specified issue" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @issue.id, actor_id: @user.id
      assert_equal @issue, event.issue
    end
  end

  context "#target_repository" do
    test "returns the repo of the specified user" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @issue.id, actor_id: @user.id
      assert_equal @repo, event.target_repository
    end

    test "does not return the repo of the specified user if issue is nil" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @issue.id, actor_id: @user.id
      @issue.destroy!
      assert_nil event.target_repository
    end
  end

  context "#target_organization" do
    test "returns the organization of the specified repo" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @org_issue.id, actor_id: @user.id
      assert_equal @org, event.target_organization
      assert_equal @org_repo, event.target_repository
    end

    test "does not return the org if the specified repo is nil" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @org_issue.id, actor_id: @user.id
      @org_issue.destroy!
      assert_nil event.target_repository
      assert_nil event.target_organization
    end

    test "does not return an org if the specified repo is user-owned" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @issue.id, actor_id: @user.id
      assert_equal @repo, event.target_repository
      assert_nil event.target_organization
    end
  end

  context "#issue_type_enabled" do
    test "enabled when issue_types FF is enabled for org" do
      enable_feature_flag(:issue_types, @org)
      event = Hook::Event::IssuesEvent.new action: :opened, issue_id: @org_issue.id, actor_id: @user.id
      assert event.issue_types_enabled, "should be enabled for typed"
    end

    test "disabled for typed action when FF is disabled" do
      disable_feature_flag(:issue_types)
      event = Hook::Event::IssuesEvent.new action: :opened, issue_id: @org_issue.id, actor_id: @user.id
      refute event.issue_types_enabled, "should be disabled for typed"
    end
  end

  context "#feature_flag_enabled?" do
    test "enabled for milestoned action" do
      disable_feature_flag(:issue_types)
      event = Hook::Event::IssuesEvent.new action: :milestoned, issue_id: @issue.id, actor_id: @user.id
      assert Hook::Event::IssuesEvent.feature_flagged?
      assert event.feature_flagged?, "feature flagged for issue events"
      assert event.feature_flag_enabled?, "should always be enabled for milestoned"
    end

    test "disabled for typed action when FF is disabled" do
      disable_feature_flag(:issue_types)
      event = Hook::Event::IssuesEvent.new action: :typed, issue_id: @org_issue.id, actor_id: @user.id
      assert Hook::Event::IssuesEvent.feature_flagged?
      assert event.feature_flagged?, "feature flagged for issue events"
      refute event.feature_flag_enabled?, "should be disabled for typed"
    end

    test "enabled for typed action when issue_types FF is enabled for org" do
      enable_feature_flag(:issue_types, @org)
      event = Hook::Event::IssuesEvent.new action: :typed, issue_id: @org_issue.id, actor_id: @user.id
      assert Hook::Event::IssuesEvent.feature_flagged?
      assert event.feature_flagged?, "feature flagged for issue events"
      assert event.feature_flag_enabled?, "should be enabled for typed"
    end

    test "disabled for untyped action when FF disabled" do
      disable_feature_flag(:issue_types)
      event = Hook::Event::IssuesEvent.new action: :untyped, issue_id: @org_issue.id, actor_id: @user.id
      assert Hook::Event::IssuesEvent.feature_flagged?
      assert event.feature_flagged?, "feature flagged for issue events"
      refute event.feature_flag_enabled?, "should be disabled for untyped"
    end

    test "enabled for untyped action when issue_types FF is enabled" do
      enable_feature_flag(:issue_types, @org)
      event = Hook::Event::IssuesEvent.new action: :untyped, issue_id: @org_issue.id, actor_id: @user.id
      assert Hook::Event::IssuesEvent.feature_flagged?
      assert event.feature_flagged?, "feature flagged for issue events"
      assert event.feature_flag_enabled?, "should be disabled for typed"
    end
  end

  context "#actor" do
    test "returns the specified user" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @issue.id, actor_id: @user.id
      assert_equal @user, event.actor
    end
  end

  context "#label" do
    test "returns the specified label" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @issue.id, actor_id: @user.id, label_id: @label.id
      assert_equal @label, event.label
    end

    test "nil returned if no label is specified" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @issue.id, actor_id: @user.id
      refute event.label
    end
  end

  context "#milestone" do
    test "returns the specified milestone" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @issue.id, actor_id: @user.id, milestone_id: @milestone.id
      assert_equal @milestone, event.milestone
    end

    test "nil returned if no milestone is specified" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @issue.id, actor_id: @user.id
      refute event.milestone
    end
  end

  context "#type" do
    test "returns the specified issue_type" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @org_issue.id, actor_id: @user.id, issue_type_id: @issue_type.id
      assert_equal @issue_type, event.type
    end

    test "nil returned if no issue_type is specified" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @org_issue.id, actor_id: @user.id
      refute event.type
    end
  end

  context "#assignee" do
    test "returns the specified assignee" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @issue.id, actor_id: @user.id, assignee_id: @assignee.id
      assert_equal @assignee, event.assignee
    end

    test "nil returned if no assignee is specified" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @issue.id, actor_id: @user.id
      refute event.assignee
    end
  end

  context "#deliverable?" do
    test "returns true" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @issue.id, actor_id: @user.id
      assert_predicate event, :deliverable?
    end

    test "returns false for deleted issue" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: -1, actor_id: @user.id
      refute_predicate event, :deliverable?
    end
  end

  context "#model_importing?" do
    test "returns true when the repo locked for migration" do
      @repo.lock_for_migration
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @issue.id, actor_id: @user.id
      assert event.model_importing?
      assert_predicate event, :model_importing?
    end

    test "returns false when the repo is not locked for migration" do
      event = Hook::Event::IssuesEvent.new action: :created, issue_id: @issue.id, actor_id: @user.id
      refute event.model_importing?
      refute_predicate event, :model_importing?
    end
  end

  context ".description" do
    test "returns the right description" do
      assert_equal "Issue opened, edited, deleted, transferred, pinned, unpinned, closed, reopened, assigned, unassigned, labeled, unlabeled, milestoned, demilestoned, locked, or unlocked.",
        Hook::Event::IssuesEvent.description
    end
  end

  context ".changes" do
    test "returns body change when change" do
      changes = {
        old_body: "old body",
        body: "new body",
      }

      event = Hook::Event::IssuesEvent.new action: :edited, issue_id: @issue.id, actor_id: @user.id, changes: changes

      expected_changes = { body: { from: "old body" } }

      assert event.changes
      assert_equal expected_changes, event.changes
    end

    test "returns body change when empty" do
      changes = {
        old_body: "old body",
        body: "",
      }

      event = Hook::Event::IssuesEvent.new action: :edited, issue_id: @issue.id, actor_id: @user.id, changes: changes

      expected_changes = { body: { from: "old body" } }

      assert event.changes
      assert_equal expected_changes, event.changes
    end

    test "returns body change when old body is empty" do
      changes = {
        old_body: "",
        body: "edited body",
      }

      event = Hook::Event::IssuesEvent.new action: :edited, issue_id: @issue.id, actor_id: @user.id, changes: changes

      expected_changes = { body: { from: "" } }

      assert event.changes
      assert_equal expected_changes, event.changes
    end

    test "returns body change when nil" do
      changes = {
        old_body: "old body"
      }

      event = Hook::Event::IssuesEvent.new action: :edited, issue_id: @issue.id, actor_id: @user.id, changes: changes

      expected_changes = { body: { from: "old body" } }

      assert event.changes
      assert_equal expected_changes, event.changes
    end
  end
end
