# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueStateTest < GitHub::TestCase
  fixtures do
    @issue = create(:issue)
    @closed_issue = create(:issue)
    @closer = create(:user)
    @closed_issue.repository.add_member(@closer)
    @closed_issue.close(@closer)
    @commenter = create(:user)
    @first_duplicate_issue = create(:issue, repository: @issue.repository)
    @second_duplicate_issue = create(:issue, repository: @issue.repository)

    @org_on_business_plus = create :business_plus_organization
    @org_repo = create :repository, owner: @org_on_business_plus
    @other_user = create :user
  end

  context "#marked_as_duplicate_of?" do
    test "true when issue is marked as a duplicate of given issue" do
      create(:duplicate_issue, issue: @first_duplicate_issue, canonical_issue: @issue)

      assert @first_duplicate_issue.marked_as_duplicate_of?(@issue)
    end

    test "false when issue is marked as not a duplicate of given issue" do
      create(:duplicate_issue, issue: @first_duplicate_issue, canonical_issue: @issue, duplicate: false)

      refute @first_duplicate_issue.marked_as_duplicate_of?(@issue)
    end

    test "false when issue has never been marked as a duplicate of given issue" do
      refute @first_duplicate_issue.marked_as_duplicate_of?(@issue)
    end

    test "does not query database when given a list of DuplicateIssues" do
      dupe = create(:duplicate_issue, issue: @first_duplicate_issue, canonical_issue: @issue)
      dupes = [dupe]
      dupe.destroy # delete record so we can be sure database isn't queried

      assert @first_duplicate_issue.marked_as_duplicate_of?(@issue, duplicate_issues: dupes)
    end
  end

  context "#create_comment" do
    test "returns persisted comment when comment body is present" do
      comment_body = "Great work!"

      comment = @issue.create_comment(@commenter, comment_body)

      assert_predicate comment, :persisted?
      assert_equal comment_body, comment.body
      assert_equal @commenter, comment.user
      assert_equal @issue.repository, comment.repository
    end

    test "returns unpersisted comment when comment body is blank" do
      comment = @issue.create_comment(@commenter, "")

      refute_predicate comment, :persisted?
    end

    test "returns unpersisted comment when commenter is unable to comment" do
      unpermitted_user = create(:user)
      User::InteractionAbility.stubs(:interaction_allowed?).returns(false)
      User::InteractionAbility.stubs(:ban_expiry).returns(1.day.from_now)
      comment_body = "Duplicate of ##{@issue.number} and ##{@first_duplicate_issue.number}"

      comment = @issue.create_comment(unpermitted_user, comment_body)

      refute_predicate comment, :persisted?
    end unless GitHub.enterprise?

    test "creates issue events for the dupe issue, one per canonical issue" do
      @issue.repository.add_member(@commenter, action: :write)
      comment_body = "Duplicate of ##{@issue.number}"

      assert_difference "IssueEvent.marked_as_duplicates.count" do
        @second_duplicate_issue.create_comment(@commenter, comment_body)
      end

      event1 = IssueEvent.marked_as_duplicates.joins(:issue_event_detail).
        where(issue_id: @second_duplicate_issue, actor_id: @commenter,
              repository_id: @second_duplicate_issue.repository_id,
              issue_event_details: { subject_type: "Issue", subject_id: @issue }).first
      assert event1, "should have marked @second_duplicate_issue as a dupe of @issue"
    end
  end

  context "#open" do
    test "enqueues community profile debounce job when open succeeds", skip_enterprise: true do
      repo = create(:repository)
      help_wanted_label = create(:label, name: Labelable::HELP_WANTED_NAME, repository: repo)
      issue = create(:issue, state: "closed", repository: repo, labels: [help_wanted_label])

      CommunityProfileUpdateHelpWantedCountersJob.expects(:enqueue_once_per_interval).
        with(args: [repo.id], interval: CommunityProfile::UPDATE_INTERVAL)

      issue.stubs(reopenable_by?: true)
      issue.open
    end

    test "issues are reopenable by installations with write permissions on issues", skip_enterprise: true do
      issue = create(:issue, state: "closed")
      installation = make_integration_installation(repository: issue.repository, permissions: { "issues" => :write })

      issue.open(installation)

      assert_predicate issue, :open?
    end

    test "pull requests are reopenable by installations with write permissions on pull requests", skip_enterprise: true do
      Spokesd.enable_spokesd

      forker = @commenter
      repo_source = @issue.repository
      repo_fork = create(:fork_repository, forker: forker, fork_repo: repo_source, from_example: :pull_request_fork)
      example_repo :pull_request_source, repo_source

      installation = make_integration_installation(repository: repo_source, permissions: { "pull_requests" => :write })

      attrs = {
        user: forker,
        base: "master",
        head: "#{forker}:topic",
        title: "some title",
        body: "some body",
        issue: create(:issue, user: forker, repository: repo_source),
      }
      pull = PullRequest.create_for repo_source, attrs
      pull.close(pull.user)

      # Guard: make sure the pull request is actually closed.
      assert_predicate pull.reload, :closed?

      pull.open(installation)

      assert_predicate pull.reload, :open?
    end
  end

  context "#close" do
    test "enqueues community profile update job when close succeeds", skip_enterprise: true do
      repo = create(:repository)
      help_wanted_label = create(:label, name: Labelable::HELP_WANTED_NAME, repository: repo)
      issue = create(:issue, state: "open", repository: repo, labels: [help_wanted_label])
      CommunityProfileUpdateHelpWantedCountersJob.expects(:enqueue_once_per_interval).
        with(args: [repo.id], interval: CommunityProfile::UPDATE_INTERVAL).once
      issue.close
    end

    test "creates issue event by default" do
      assert @issue.close(@issue.user)
      refute_nil @issue.events.find_by(event: "closed")
    end

    test "closes issue with nil state_reason if reason is completed" do
      assert @issue.close(@issue.user, attributes: { state_reason: "completed" })
      assert_predicate @issue, :closed?
      assert_nil @issue.state_reason
      refute_nil @issue.events.find_by(event: "closed")
    end

    test "returns nil if already closed as completed" do
      assert @issue.close(@issue.user, attributes: { state_reason: "completed" })
      assert_predicate @issue, :closed?
      assert_nil @issue.state_reason
      refute_nil @issue.events.find_by(event: "closed")

      assert_no_difference(-> { @issue.events.count }) do
        assert_nil @issue.close(@issue.user, attributes: { state_reason: "completed" })
      end
    end

    test "does not create issue event if create_event is false" do
      assert @issue.close(@issue.user, create_event: false)
      assert_nil @issue.events.find_by(event: "closed")
    end

    test "reports to Failbot when closing an issue when its pull is already merged" do
      GitHub.flipper[:tasklist_block_markdown_at_rest].disable
      GitHub.flipper[:secret_scanning_push_protection_for_users_opt_out].disable
      Failbot.reports.clear

      repo = create(:repository, from_example: :simple)
      pull = create(:pull_request, :with_mergeable_head, :merged, repository: repo)

      assert pull.merged?
      refute pull.issue.close

      assert_equal 1, Failbot.reports.length
    end

    test "reports to Failbot when updating issue fails on PR merge" do
      GitHub.flipper[:tasklist_block_markdown_at_rest].disable
      GitHub.flipper[:secret_scanning_push_protection_for_users_opt_out].disable
      Failbot.reports.clear

      repo = create(:repository, from_example: :simple)
      pull = create(:pull_request, :with_mergeable_head, repository: repo)

      pull.stubs(:merged?).returns(true)
      pull.issue.title = ""

      refute pull.issue.close

      assert_equal 1, Failbot.reports.length
      assert_equal "Title can't be blank", Failbot.reports.first["sensitive_context"]["gh.pull_request.errors"]
    end

    context "auto-close workflow" do
      test "creates issue event with performed_by_project_workflow_action_id" do
        assert @issue.close(@issue.user, attributes: { performed_by_project_workflow_action_id: 12345 })
        refute_nil @issue.events.where(performed_by_project_workflow_action_id: 12345)
      end

      test "does not close issue with performed_by_project_workflow_action_id attribute if not closable by user" do
        refute @issue.close(@other_user, attributes: { performed_by_project_workflow_action_id: 12345 })
      end
    end
  end

  context "#async_closable_by" do
    test "author can close" do
      assert @issue.async_closable_by?(@issue.user).sync
    end

    test "non-collaborator cannot close" do
      refute @issue.async_closable_by?(@other_user).sync
    end

    test "collaborator can close" do
      @issue.repository.add_member(@other_user)
      assert @issue.async_closable_by?(@other_user).sync
    end

    test "triage role can close" do
      issue = create(:issue, state: "open", repository: @org_repo)
      @org_repo.send(:grant, @other_user, :triage)

      assert issue.async_closable_by?(@other_user).sync
    end

    test "site scoped GitHub installation with permissions" do
      GitHub.flipper[:disabled_global_apps].disable

      permissions = { "metadata" => :read, "contents" => :write, "issues" => :write }
      integration = create_unlimited_global_integration(permissions: permissions)
      installation = make_site_scoped_integration_installation(
        integration: integration, target: @issue.repository.owner,
        repositories: [@issue.repository], permissions: permissions
      )

      assert @issue.async_closable_by?(installation.bot).sync
    end
  end

  context "#reopenable_by" do
    test "author cannot reopen" do
      refute @closed_issue.reopenable_by?(@closed_issue.user)
    end

    test "non-collaborator cannot reopen" do
      refute @closed_issue.reopenable_by?(@other_user)
    end

    test "closer can reopen" do
      assert @closed_issue.reopenable_by?(@closed_issue.closed_by)
    end

    test "collaborator can reopen" do
      @closed_issue.repository.add_member(@other_user)
      assert @closed_issue.reopenable_by?(@other_user)
    end

    test "triage role can reopen" do
      issue = create(:issue, state: "closed", repository: @org_repo)
      @org_repo.send(:grant, @other_user, :triage)

      assert issue.reopenable_by?(@other_user)
    end
  end
end
