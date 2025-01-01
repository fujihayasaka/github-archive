# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadIssuesPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @assignee = create(:user)
    @repo = create(:repository, owner: @user)
    @issue = create(:issue, repository: @repo, user: @user)
    @label = create(:label, name: "Bug", repository: @repo)
    @milestone = create(:milestone, created_by: @user, repository: @repo)
    @org = create(:organization, admin: @user)
    @org_repo = create(:repository, owner: @org)
    @org_issue = create(:issue, repository: @org_repo, user: @user)
    @issue_type = @org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])
  end

  [:opened, :closed, :reopened].each do |action|
    context "when the Issue is #{action}" do
      test "v3" do
        payload = build_issues_payload(action: action)
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @issue.id, v3[:issue][:id]
        refute v3[:issue][:type]
        assert_equal @repo.id, v3[:repository][:id]
        assert_equal @repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
      end

      test "v3 with issue_types FF enabled" do
        enable_feature_flag(:issue_types, @org)

        @org_issue.issue_type = @issue_type
        @org_issue.save!

        payload = build_issues_payload(action: action, issue_id: @org_issue.id)
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @org_issue.id, v3[:issue][:id]
        assert_equal @org_issue.issue_type.name, v3[:issue][:type][:name]
        assert_equal @org_repo.id, v3[:repository][:id]
        assert_equal @org_repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
      end
    end
  end

  [:labeled, :unlabeled].each do |action|
    context "when the Issue is #{action}" do
      test "v3" do
        payload = build_issues_payload(action: action, label_id: @label.id)
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @issue.id, v3[:issue][:id]
        assert_equal "Bug", v3[:label][:name]
        assert_equal @repo.id, v3[:repository][:id]
        assert_equal @repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
      end
    end
  end

  [:assigned, :unassigned].each do |action|
    context "when the Issue is #{action}" do
      test "v3" do
        payload = build_issues_payload(action: action, assignee_id: @assignee.id)
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @issue.id, v3[:issue][:id]
        assert_equal @assignee.id, v3[:assignee][:id]
        assert_equal @repo.id, v3[:repository][:id]
        assert_equal @repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
      end
    end
  end

  [:milestoned, :demilestoned].each do |action|
    context "when the Issue is #{action}" do
      test "v3" do
        @issue.milestone = @milestone
        @issue.save!

        if action == :demilestoned
          @issue.milestone = nil
          @issue.save!
        end

        payload = build_issues_payload(action: action, milestone_id: @milestone.id)
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @issue.id, v3[:issue][:id]

        if action == :milestoned
          assert_equal @milestone.id, v3[:issue][:milestone][:id]
        else
          refute v3[:issue][:milestone]
        end

        assert_equal @milestone.id, v3[:milestone][:id]
        assert_equal @repo.id, v3[:repository][:id]
        assert_equal @repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
      end
    end
  end

  [:typed, :untyped].each do |action|
    context "when the Issue is #{action}" do
      test "v3" do
        enable_feature_flag(:issue_types)
        @org_issue.issue_type = action == :untyped ? nil : @issue_type
        @org_issue.save!

        v3 = build_issues_payload(action: action, issue_id: @org_issue.id, issue_type_id: @issue_type.id).to_hash

        assert_equal action, v3[:action]
        assert_equal @org_issue.id, v3[:issue][:id]
        assert_equal @issue_type.id, v3[:type][:id]
        assert_equal @org_repo.id, v3[:repository][:id]
        assert_equal @org_repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
      end
    end
  end

  context "when the Issue's title and body is updated" do
    test "v3" do
      changes = {
        old_body: "Body",
        body: "Changed Body",
        old_title: "Title",
        title: "Changed Title",
      }
      payload = build_issues_payload(action: :edited, changes: changes)
      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @issue.id, v3[:issue][:id]
      assert_equal @user.id, v3[:sender][:id]
      assert_includes v3, :changes
    end
  end

  [:locked, :unlocked].each do |action|
    context "when the Issue is #{action}" do
      test "v3" do
        payload = build_issues_payload(action: action)
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @issue.id, v3[:issue][:id]
        assert_equal @repo.id, v3[:repository][:id]
        assert_equal @repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
        assert_nil v3[:changes]
      end
    end
  end

  context "when the Issue is transferred" do
    test "the payload for the :transferred event for the old issue includes the new_issue and new_repository" do
      issue_transfer = create :issue_transfer
      old_issue = issue_transfer.old_issue
      new_issue = issue_transfer.new_issue

      payload = build_issues_payload(action: :transferred, issue_id: old_issue.id, actor_id: issue_transfer.actor.id)
      v3 = payload.to_hash

      assert_equal :transferred, v3[:action]
      assert_equal old_issue.id, v3[:issue][:id]
      assert_equal old_issue.repository.id, v3[:repository][:id]

      # changes hash includes new_issue and new_repository
      assert_equal new_issue.id, v3[:changes][:new_issue][:id]
      assert_equal new_issue.repository.id, v3[:changes][:new_repository][:id]
    end

    test "the payload for the :opened event for the new issue includes the old_issue and old_repository" do
      issue_transfer = create :issue_transfer
      old_issue = issue_transfer.old_issue
      new_issue = issue_transfer.new_issue

      payload = build_issues_payload(action: :opened, issue_id: new_issue.id, actor_id: issue_transfer.actor.id)
      v3 = payload.to_hash

      assert_equal :opened, v3[:action]
      assert_equal new_issue.id, v3[:issue][:id]
      assert_equal new_issue.repository.id, v3[:repository][:id]

      # changes hash includes old_issue and old_repository
      assert_equal old_issue.id, v3[:changes][:old_issue][:id]
      assert_equal old_issue.repository.id, v3[:changes][:old_repository][:id]
    end
  end

  def build_issues_payload(attrs = {})
    default_attrs = {
      action: :opened,
      issue_id: @issue.id,
      actor_id: @user.id,
    }

    event = Hook::Event::IssuesEvent.new(attrs.reverse_merge(default_attrs))
    Hook::Payload::IssuesPayload.new(event)
  end
end
