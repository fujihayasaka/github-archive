# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadPullRequestPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @assignee = create(:user)
    @repo = create :repository, owner: @user, from_example: :rebase_pull_request
    @label = create :label, name: "Bug", repository: @repo
    @pull = create(:issue, user: @user, repository: @repo)
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: @pull,
    )

    @org    = create(:organization, login: "myorg")
    @team   = create(:team, organization: @org, name: "myteam", permission: "pull")
  end

  [:opened, :closed, :reopened].each do |action|
    context "when the PullRequest is #{action}" do
      test "v3" do
        payload = build_pull_payload(action: action)
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @pull.id, v3[:pull_request][:id]
        assert_equal @repo.id, v3[:repository][:id]
        assert_equal @repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
        assert_merge_options_exist(@repo, @repo, v3)
      end
    end
  end

  [:synchronize].each do |action|
    context "when the PullRequest is #{action}" do
      test "v3" do
        payload = build_pull_payload(
          action: action,
          before: @pull.base_sha,
          after: @pull.head_sha,
        )
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @pull.id, v3[:pull_request][:id]
        assert_equal @repo.id, v3[:repository][:id]
        assert_equal @repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
        assert_equal @pull.base_sha, v3[:before]
        assert_equal @pull.head_sha, v3[:after]
        assert_equal @pull.head_sha, v3[:pull_request][:head][:sha]
        assert_merge_options_exist(@repo, @repo, v3)
      end
    end
  end

  [:labeled, :unlabeled].each do |action|
    context "when the PullRequest is #{action}" do
      test "v3" do
        payload = build_pull_payload(action: action, label_id: @label.id)
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @pull.id, v3[:pull_request][:id]
        assert_equal "Bug", v3[:label][:name]
        assert_equal @repo.id, v3[:repository][:id]
        assert_equal @repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
        assert_merge_options_exist(@repo, @repo, v3)
      end
    end
  end

  [:assigned, :unassigned].each do |action|
    context "when the PullRequest is #{action}" do
      test "v3" do
        payload = build_pull_payload(action: action, assignee_id: @assignee.id)
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @pull.id, v3[:pull_request][:id]
        assert v3[:pull_request][:assignees]
        assert_equal @assignee.id, v3[:assignee][:id]
        assert_equal @repo.id, v3[:repository][:id]
        assert_equal @repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
        assert_merge_options_exist(@repo, @repo, v3)
      end
    end
  end

  [:review_requested, :review_request_removed].each do |action|
    context "when the PullRequest is #{action}" do
      test "v3" do
        payload = build_pull_payload(action: action, subject_id: @assignee.id, subject_type: "User")
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @pull.id, v3[:pull_request][:id]
        assert_equal @assignee.id, v3[:requested_reviewer][:id]
        assert v3[:pull_request][:requested_reviewers]
        assert_equal @repo.id, v3[:repository][:id]
        assert_equal @repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
        assert_merge_options_exist(@repo, @repo, v3)
      end
    end
  end

  [:review_requested, :review_request_removed].each do |action|
    context "when the PullRequest is #{action} and team is subject" do
      test "v3" do
        payload = build_pull_payload(action: action, subject_id: @team.id, subject_type: "Team")
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @pull.id, v3[:pull_request][:id]
        assert_equal @team.id, v3[:requested_team][:id]
        assert v3[:pull_request][:requested_reviewers]
        assert_equal @repo.id, v3[:repository][:id]
        assert_equal @repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
        assert_merge_options_exist(@repo, @repo, v3)
      end
    end
  end

  context "when the action is :auto_merge_enabled" do
    test "v3" do
      @repo.allow_auto_merge(actor: @repo.owner)
      @repo.protect_branch(@pull.base_ref_name, creator: @repo.owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, entry_point: :test_case)
      @repo.add_member(@pull.user)

      auto_merge_request = create(
        :auto_merge_request,
        pull_request: @pull,
        user: @user,
        merge_method: :auto_squash_and_merge,
        commit_title: "Commit title",
        commit_message: "Commit message"
      )

      payload = build_pull_payload(action: :auto_merge_enabled)
      v3 = payload.to_hash

      assert_equal :auto_merge_enabled, v3[:action]
      assert_equal @pull.id, v3[:pull_request][:id]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @repo.name, v3[:repository][:name]
      assert_equal @user.id, v3[:sender][:id]
      assert_equal @user.login, v3[:sender][:login]
      assert_equal @user.id, v3[:pull_request][:auto_merge][:enabled_by][:id]
      assert_equal :squash, v3[:pull_request][:auto_merge][:merge_method]
      assert_equal "Commit title", v3[:pull_request][:auto_merge][:commit_title]
      assert_equal "Commit message", v3[:pull_request][:auto_merge][:commit_message]
      assert_merge_options_exist(@repo, @repo, v3)
    end
  end

  context "when the action is :auto_merge_disabled" do
    test "v3" do
      payload = build_pull_payload(action: :auto_merge_disabled, reason: "Pull request was closed")
      v3 = payload.to_hash

      assert_equal :auto_merge_disabled, v3[:action]
      assert_equal @pull.id, v3[:pull_request][:id]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @repo.name, v3[:repository][:name]
      assert_equal @user.id, v3[:sender][:id]
      assert_equal @user.login, v3[:sender][:login]
      assert_equal "Pull request was closed", v3[:reason]
      assert_merge_options_exist(@repo, @repo, v3)
    end
  end

  context "when the PullRequest's title and body is updated" do
    test "v3" do
      changes = {
        old_body: "Body",
        body: "Changed Body",
        old_title: "Title",
        title: "Changed Title",
      }
      payload = build_pull_payload(action: :edited, changes: changes)
      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @pull.id, v3[:pull_request][:id]
      assert_includes v3, :changes
    end
  end

  context "when the PullRequest is a draft" do
    test "v3" do
      @pull.update_attribute(:draft, true)
      payload = build_pull_payload
      v3 = payload.to_hash

      assert_includes v3[:pull_request], :draft
      assert v3[:pull_request][:draft]
    end
  end

  [:locked, :unlocked].each do |action|
    context "when the PullRequest is #{action}" do
      test "v3" do
        payload = build_pull_payload(action: action)
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @pull.id, v3[:pull_request][:id]
        assert_equal @repo.id, v3[:repository][:id]
        assert_equal @repo.name, v3[:repository][:name]
        assert_equal @user.id, v3[:sender][:id]
        assert_equal @user.login, v3[:sender][:login]
        assert_nil v3[:changes]
      end
    end
  end

  def build_pull_payload(attrs = {})
    default_attrs = {
      action: :opened,
      pull_request_id: @pull.id,
      actor_id: @user.id,
    }

    event = Hook::Event::PullRequestEvent.new(attrs.reverse_merge(default_attrs))
    Hook::Payload::PullRequestPayload.new(event)
  end

  def assert_merge_options_exist(head_repo, base_repo, v3)
    head_repo_hash = v3[:pull_request][:head][:repo]
    assert_equal head_repo.squash_merge_allowed?, head_repo_hash[:allow_squash_merge]
    assert_equal head_repo.merge_commit_allowed?, head_repo_hash[:allow_merge_commit]
    assert_equal head_repo.rebase_merge_allowed?, head_repo_hash[:allow_rebase_merge]
    assert_equal head_repo.delete_branch_on_merge?, head_repo_hash[:delete_branch_on_merge]

    base_repo_hash = v3[:pull_request][:base][:repo]
    assert_equal base_repo.squash_merge_allowed?, base_repo_hash[:allow_squash_merge]
    assert_equal base_repo.merge_commit_allowed?, base_repo_hash[:allow_merge_commit]
    assert_equal base_repo.rebase_merge_allowed?, base_repo_hash[:allow_rebase_merge]
    assert_equal base_repo.delete_branch_on_merge?, base_repo_hash[:delete_branch_on_merge]
  end
end
