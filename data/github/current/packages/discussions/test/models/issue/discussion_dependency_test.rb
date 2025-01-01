# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueDiscussionDependencyTest < GitHub::TestCase
  include DiscussionsTestHelper
  include HookIntegrationTestHelper
  include ResiliencyHelpers

  fixtures do
    create_discussions_authz_fixtures

    @issue = create(:issue, repository: @repo)
    @issue_comment = create(:issue_comment, issue: @issue, repository: @repo)
    @discussion = create(:discussion, repository: @repo)

    @org_issue = create(:issue, repository: @org_repo)
  end

  setup do
    GitHub.flipper[:block_deletion_on_conversion].enable
    # We only want to test hook delivery in sspecific tests
    Hook.stubs(:delivers_in_test?).returns(false)
  end

  context "#discussion" do
    test "returns discussion if it exists for issue" do
      issue_with_discussion = create(:issue)
      issue_with_discussion.repository.turn_on_discussions(actor: issue_with_discussion.user, instrument: false)
      discussion = create(:discussion, issue: issue_with_discussion,
        repository: issue_with_discussion.repository, number: issue_with_discussion.number)
      assert_equal discussion, issue_with_discussion.discussion

      issue_without_discussion = create(:issue)
      assert_nil issue_without_discussion.discussion
    end
  end

  context "#can_be_converted_by?" do
    test "false when discussions setting is disabled for the repository" do
      repo_without_discussions = create(:repository, owner: @owner, has_discussions: false)
      issue_in_repo_wo_discussions = create(:issue, repository: repo_without_discussions)
      refute issue_in_repo_wo_discussions.can_be_converted_by?(@owner)
    end

    test "false when issue is being transferred" do
      issue = create(:issue, repository: @repo)
      issue_comment = create(:issue_comment, issue: issue, repository: @repo)
      new_repository = create(:repository, owner: @owner, has_discussions: true)
      transfer = IssueTransfer.new(old_issue: issue, old_repository: issue.repository, new_repository: new_repository, actor: @owner)
      transfer.send(:create_copy_issue)

      new_issue = transfer.new_issue
      refute_nil new_issue
      refute T.must(new_issue).can_be_converted_by?(@owner)
    end

    test "true for repo owner" do
      assert @issue.can_be_converted_by?(@owner)
    end

    test "true for user with triage access" do
      user = create(:verified_user)
      @org_repo.add_member(user, action: :triage)
      assert @org_issue.can_be_converted_by?(user)
    end

    test "true for user on a team with triage access" do
      user = create(:verified_user)
      team = create(:team, organization: @org_repo.owner)
      team.add_member(user)
      @org_repo.add_team(team, action: :triage)
      assert @org_issue.can_be_converted_by?(user)
    end

    test "true for user with repo write access" do
      user = create(:verified_user)
      @repo.add_member(user, action: :write)
      assert @issue.can_be_converted_by?(user)
    end

    test "false for user on a team without triage access" do
      user = create(:verified_user)
      team = create(:team, organization: @org_repo.owner)
      team.add_member(user)
      @org_repo.add_team(team, action: :read)
      refute @org_issue.can_be_converted_by?(user)
    end

    test "false for user without a verified email address" do
      user = create(:user)
      @repo.add_member(user, action: :write)
      refute @issue.can_be_converted_by?(user)
    end if GitHub.email_verification_enabled?

    test "false when issue author blocked the user" do
      blocked_user = create(:user, login: "blockeduser")
      @repo.add_member(blocked_user, action: :write)
      @issue.user.block(blocked_user)
      refute @issue.can_be_converted_by?(blocked_user)
    end

    test "false when user is spammy" do
      spammer = create(:spammy_user)
      @repo.add_member(spammer, action: :write)
      refute @issue.can_be_converted_by?(spammer)
    end if GitHub.spamminess_check_enabled?

    test "false when user is suspended" do
      suspended_user = create(:suspended_user)
      @repo.add_member(suspended_user, action: :write)
      refute @issue.can_be_converted_by?(suspended_user)
    end

    test "false for a pull request" do
      pull = create(:pull_request, :disable_disk_access)
      refute pull.issue.can_be_converted_by?(pull.user)
    end

    test "false when user only has read access" do
      rando = create(:user)
      refute @issue.can_be_converted_by?(rando)
    end

    test "false when a conversion is already in process" do
      create(:discussion, issue: @issue, repository: @repo, number: @issue.number)
      refute @issue.can_be_converted_by?(@owner)
    end
  end

  test "cannot update an issue while converting it to a discussion" do
    discussion = create(:discussion, issue: @issue, repository: @repo, number: @issue.number)
    discussion.converting!
    @issue.title = "Brand new title"
    refute_predicate @issue, :valid?
    assert_includes @issue.errors[:base],
      "Cannot be modified since it is being converted to a discussion."
  end

  test "does not fail when ApplicationRecord::Configurations cluster is not available" do
    discussion = create(:discussion, issue: @issue, repository: @repo, number: @issue.number)
    @issue.title = "Brand new title"

    prevent_connections_to(ApplicationRecord::Configurations) do
      assert_predicate @issue, :valid?
    end
  end

  context "#mark_as_converted_to_discussion" do
    test "creates only convertered event and updates state to closed" do
      converted_discussion = create(:discussion, repository: @repo, issue: @issue)
      assert_equal converted_discussion, @issue.discussion

      assert @issue.mark_as_converted_to_discussion(actor: @issue.user)
      assert_predicate @issue, :closed?
      assert_nil @issue.events.find_by(event: "closed")
      event = @issue.events.find_by(event: "converted_to_discussion")
      assert_equal converted_discussion, event.subject
      assert_equal @issue.user, event.actor
    end

    test "returns true for an already closed discussion" do
      @issue.close!
      converted_discussion = create(:discussion, repository: @repo, issue: @issue)
      assert_equal converted_discussion, @issue.discussion

      assert @issue.mark_as_converted_to_discussion(actor: @issue.user)
      assert_predicate @issue, :closed?
      event = @issue.events.find_by(event: "converted_to_discussion")
      assert_equal converted_discussion, event.subject
      assert_equal @issue.user, event.actor
    end

    test "returns false if actor is not present" do
      converted_discussion = create(:discussion, repository: @repo, issue: @issue)
      assert_equal converted_discussion, @issue.discussion

      refute @issue.mark_as_converted_to_discussion(actor: nil)
      assert_nil @issue.events.find_by(event: "converted_to_discussion")
      assert_predicate @issue, :open?
    end

    test "returns false if issue does not have associated discussion" do
      assert_nil @issue.discussion
      refute @issue.mark_as_converted_to_discussion(actor: @issue.user)
      assert_nil @issue.events.find_by(event: "converted_to_discussion")
      assert_predicate @issue, :open?
    end

    test "does not create event if closing fails" do
      converted_discussion = create(:discussion, repository: @repo, issue: @issue)
      assert_equal converted_discussion, @issue.discussion

      @issue.stubs(:close).returns(false)
      refute @issue.mark_as_converted_to_discussion(actor: @issue.user)
      assert_nil @issue.events.find_by(event: "converted_to_discussion")
      assert_predicate @issue, :open?
    end

    test "fires issue closed webhook after converting issue to discussion" do
      Hook.stubs(:delivers_in_test?).returns(true)

      perform_enqueued_jobs(only: [DeliverHookEventJob]) do
        repo_hook = create(:hook, :web, installation_target: @repo, events: %w(issues))
        deliveries = subscribe_to_hook_delivery "issues"
        converted_discussion = create(:discussion, repository: @repo, issue: @issue)
        assert_equal converted_discussion, @issue.discussion

        assert @issue.mark_as_converted_to_discussion(actor: @issue.user)
        assert_predicate @issue, :closed?
        assert_nil @issue.events.find_by(event: "closed")
        event = @issue.events.find_by(event: "converted_to_discussion")
        assert_equal converted_discussion, event.subject
        assert_equal @issue.user, event.actor
        assert_equal 1, deliveries.count
        payload = deliveries.payload_for_hook(repo_hook)
        assert_equal @repo.id, payload[:repository][:id]
        assert_equal @issue.id, payload[:issue][:id]
        assert_equal @issue.user.id, payload[:sender][:id]
      end
    end
  end

  context "#ensure_not_converting" do
    test "does not add error if feature flag disabled" do
      GitHub.flipper[:block_deletion_on_conversion].disable
      category = create(:discussion_category, repository: @issue.repository)
      converter = IssueToDiscussionConverter.new(@issue, actor: @issue.repository.owner, category: category)
      assert converter.prepare_for_conversion

      assert_difference("Issue.count", -1) do
        @issue.destroy
      end
    end

    test "does not add error if not converting to discussion" do
      assert_difference("Issue.count", -1) do
        @issue.destroy
      end
    end

    test "adds error if has feature flag and converting to discussion" do
      category = create(:discussion_category, repository: @issue.repository)
      converter = IssueToDiscussionConverter.new(@issue, actor: @issue.repository.owner, category: category)
      assert converter.prepare_for_conversion

      assert_difference("Issue.count", 0) do
        @issue.destroy
      end

      assert @issue.errors.full_messages.include?("This issue is being converted to a discussion.")
    end

    test "does not add error if feature flag enabled and conversion is complete" do
      category = create(:discussion_category, repository: @issue.repository)
      converter = IssueToDiscussionConverter.new(@issue, actor: @issue.repository.owner, category: category)
      assert converter.prepare_for_conversion
      assert converter.finish_conversion, "should return true on success"

      assert_difference("Issue.count", -1) do
        @issue.destroy
      end
    end
  end
end
