# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"
require "test_helpers/issue_event_test_helper"
require "test_helpers/query_identifier_helper"

class Hovercard::LoaderTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include IssueEventTestHelper
  include GitHub::PullRequestTestHelpers
  include QueryIdentifierHelper

  setup do
    GitHub.flipper[:extract_checklists].disable
    GitHub.flipper[:notifyd_issue_watch_activity_notify].disable
  end

  def compare_queries(expected_queries, actual_queries, message: nil)
    assert_equal parse_queries(expected_queries), identify_queries(actual_queries).sort, message
  end

  def assert_queries(expected_queries)
    # loader
    loader, queries = log_cleaned_queries do
      yield
    end
    compare_queries expected_queries, queries, message: "Unexpected queries while loading data"

    # adapter
    _, queries = log_cleaned_queries do
      Hovercard::Loader.hovercard_adapter(loader)
    end

    compare_queries "", queries, message: "Expected no queries when creating an HoverAdapter"
  end

  test "preloading does not execute unexpected queries for an issue" do
    user = create(:user)
    repo = create(:repository, owner: user)
    issue = perform_enqueued_jobs(only: SubscribeAndNotifyJob) do
      create(:issue, repository: repo, user: user)
    end

    queries = [
      "issue_comments.has_timeline_items?",
      "issue_events",
      "notification_subscription_events",
      "notification_subscriptions",
      "notification_thread_subscriptions",
      "notification_thread_type_subscriptions",
      "primary_avatars",
      "users"
    ]
    queries.unshift("duplicate_issues") if GitHub.flipper[:issues_react_close_as_duplicate].enabled?
    queries = queries.join("\n")

    assert_queries queries do
      Hovercard::Loader.new(
        issue,
        repo,
        user,
        cap_filter: cap_authorizing_filter
      )
    end
  end

  context "tracked issues" do
    test "preloading loads issue state reason for tracked issues" do
      user = create(:user)
      repo = create(:repository, owner: user)
      GitHub.flipper[:extract_checklists].enable(repo)
      GitHub.flipper[:extract_checklists].enable(user)

      issue = create(:issue, repository: repo, user: user)
      tracked_issue = create(:issue, repository: repo, user: user)
      issue.body = "- [ ] ##{tracked_issue.number}"
      issue.close(issue.user, attributes: { state_reason: "not_planned" })
      issue.save!
      issue.reload
      tracked_issue.reload

      assert tracked_issue.tracked_in_issues.any?

      hovercard_adapter = Hovercard::Loader.load_for(
        tracked_issue,
        repo,
        user,
        cap_filter: cap_authorizing_filter
      )

      assert hovercard_adapter.tracked_in_issues.any? && hovercard_adapter.tracked_in_issues.first[:issue_state_reason] == "not_planned"
    end

    test "tracked issues in private repos aren't loaded" do
      user = create(:user)
      user_2 = create(:user)
      repo = create(:repository, owner: user)
      private_repo = create(:private_repository, owner: user)

      GitHub.flipper[:extract_checklists].enable(repo)
      GitHub.flipper[:extract_checklists].enable(private_repo)
      GitHub.flipper[:extract_checklists].enable(user)
      GitHub.flipper[:extract_checklists].enable(user_2)

      issue = create(:issue, repository: private_repo, user: user)
      tracked_issue = create(:issue, repository: repo, user: user)
      create(:issue_link, source_issue: issue, target_issue: tracked_issue)

      assert tracked_issue.tracked_in_issues.any?

      # user with permissions should see tracked item
      hovercard_adapter = Hovercard::Loader.load_for(
        tracked_issue,
        repo,
        user,
        cap_filter: cap_authorizing_filter
      )

      assert hovercard_adapter.tracked_in_issues.any?

      # user without permissions to the private repo shouldn't see the tracked item
      hovercard_adapter = Hovercard::Loader.load_for(
        tracked_issue,
        repo,
        user_2,
        cap_filter: cap_authorizing_filter
      )

      refute hovercard_adapter.tracked_in_issues.any?
    end

    test "tracked_issues doesn't return unauthorized tracked issues" do
      user = create(:user)
      repo = create(:repository, owner: user)

      GitHub.flipper[:extract_checklists].enable(repo)
      GitHub.flipper[:extract_checklists].enable(user)

      issue = create(:issue, repository: repo, user: user)
      tracked_issue = create(:issue, repository: repo, user: user)
      create(:issue_link, source_issue: issue, target_issue: tracked_issue)

      assert tracked_issue.tracked_in_issues.any?

      # user with permissions should see tracked item
      hovercard_adapter = Hovercard::Loader.load_for(
        tracked_issue,
        repo,
        user,
        cap_filter: cap_unauthorizing_filter(issue)
      )

      refute hovercard_adapter.tracked_in_issues.any?
    end

    test "tracked_issues returns authorized tracked issues" do
      user = create(:user)
      repo = create(:repository, owner: user)

      GitHub.flipper[:extract_checklists].enable(repo)
      GitHub.flipper[:extract_checklists].enable(user)

      issue = create(:issue, repository: repo, user: user)
      tracked_issue = create(:issue, repository: repo, user: user)
      create(:issue_link, source_issue: issue, target_issue: tracked_issue)

      assert tracked_issue.tracked_in_issues.any?

      # user with permissions should see tracked item
      hovercard_adapter = Hovercard::Loader.load_for(
        tracked_issue,
        repo,
        user,
        cap_filter: cap_authorizing_filter(issue)
      )

      assert hovercard_adapter.tracked_in_issues.any?
    end

    test "tracked_issues returns issues tracked in issues graph" do
      user = create(:user)
      repo = create(:repository, owner: user)

      issue = create(:issue, repository: repo, user: user)
      tracking_issue = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(
          ownerId: issue.repository.owner.id,
          itemId: issue.id,
          primaryKey: ::IssuesGraph::Proto::PrimaryKey.new(
            uuid: SecureRandom.uuid,
          )
        ),
        repoId: repo.id,
        userName: user.login,
        repoName: repo.name,
        number: issue.number,
        title: issue.title,
        url: issue.url,
        state: issue.state,
      )
      issue2 = create(:issue, repository: repo, user: user)
      tracking_issue_2 = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(
          ownerId: issue2.repository.owner.id,
          itemId: issue2.id,
          primaryKey: ::IssuesGraph::Proto::PrimaryKey.new(
            uuid: SecureRandom.uuid,
          )
        ),
        repoId: repo.id,
        userName: user.login,
        repoName: repo.name,
        number: issue2.number,
        title: issue2.title,
        url: issue2.url,
        state: issue2.state,
      )
      tracking_block = IssuesGraph::Proto::TrackingBlock.new(issues: [tracking_issue])
      tracking_block_2 = IssuesGraph::Proto::TrackingBlock.new(issues: [tracking_issue_2])
      tracking_block_response = IssuesGraph::Proto::GetIssueResponse.new(trackedBy: [tracking_block, tracking_block_2])
      result = ::IssuesGraph::Result.success(tracking_block_response)
      GitHub.async_issues_graph_api_client.expects(:get_issue).once.returns(Promise.resolve(result))

      GitHub.flipper[:tasklist_block].enable(repo.owner)
      GitHub.flipper[:issue_hierarchy_state].enable
      GitHub.flipper[:issues_graph_api_concurrent_faraday].enable(repo)

      issue = create(:issue, repository: repo, user: user)

      # user with permissions should see tracked item
      hovercard_adapter = Hovercard::Loader.load_for(
        issue,
        repo,
        user,
        cap_filter: cap_authorizing_filter
      )

      assert_equal tracking_issue.number, hovercard_adapter.tracked_in_issues[0][:issue_number]
      assert_equal tracking_issue_2.number, hovercard_adapter.tracked_in_issues[1][:issue_number]
    end

    test "tracked_issues returns issues tracked in issues graph AND in dotcom" do
      GitHub.flipper[:tasklist_block_markdown_at_rest].disable
      user = create(:user)
      repo = create(:repository, owner: user)

      hierarchy_issue = create(:issue, repository: repo, user: user)
      tracking_hierarchy_issue = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(
          ownerId: repo.owner.id,
          itemId: hierarchy_issue.id,
          primaryKey: ::IssuesGraph::Proto::PrimaryKey.new(
            uuid: SecureRandom.uuid,
          )
        ),
        repoId: repo.id,
        userName: user.login,
        repoName: repo.name,
        number: hierarchy_issue.number,
        title: hierarchy_issue.title,
        url: hierarchy_issue.url,
        state: hierarchy_issue.state,
      )
      tracking_block = IssuesGraph::Proto::TrackingBlock.new(issues: [tracking_hierarchy_issue])
      tracking_block_response = IssuesGraph::Proto::GetIssueResponse.new(trackedBy: [tracking_block])
      result = ::IssuesGraph::Result.success(tracking_block_response)
      GitHub.async_issues_graph_api_client.expects(:get_issue).once.returns(Promise.resolve(result))

      GitHub.flipper[:extract_checklists].enable(repo)
      GitHub.flipper[:extract_checklists].enable(user)
      GitHub.flipper[:tasklist_block].enable(repo.owner)
      GitHub.flipper[:issue_hierarchy_state].enable
      GitHub.flipper[:issues_graph_api_concurrent_faraday].enable(repo)

      issue = create(:issue, repository: repo, user: user)
      tracked_issue = create(:issue, repository: repo, user: user)
      create(:issue_link, source_issue: issue, target_issue: tracked_issue)

      assert tracked_issue.tracked_in_issues.any?

      # user with permissions should see tracked item
      hovercard_adapter = Hovercard::Loader.load_for(
        tracked_issue,
        repo,
        user,
        cap_filter: cap_authorizing_filter([user, issue])
      )

      assert_equal tracking_hierarchy_issue.number, hovercard_adapter.tracked_in_issues[0][:issue_number]
      assert_equal issue.number, hovercard_adapter.tracked_in_issues[1][:issue_number]
    end

    test "tracked_issues DOES NOT return inaccessible issues" do
      user = create(:user)
      repo = create(:repository, owner: user)

      other_user = create(:user)
      other_user_repo = create(:private_repository, owner: other_user)

      issue = create(:issue, repository: other_user_repo, user: other_user)
      tracking_issue = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(
          ownerId: issue.repository.owner.id,
          itemId: issue.id,
          primaryKey: ::IssuesGraph::Proto::PrimaryKey.new(
            uuid: SecureRandom.uuid,
          )
        ),
        repoId: other_user_repo.id,
        userName: other_user.login,
        repoName: other_user_repo.name,
        number: issue.number,
        title: issue.title,
        url: issue.url,
        state: issue.state,
      )

      tracking_block = IssuesGraph::Proto::TrackingBlock.new(issues: [tracking_issue])
      tracking_block_response = IssuesGraph::Proto::GetIssueResponse.new(trackedBy: [tracking_block])
      result = ::IssuesGraph::Result.success(tracking_block_response)
      GitHub.async_issues_graph_api_client.expects(:get_issue).once.returns(Promise.resolve(result))

      GitHub.flipper[:tasklist_block].enable
      GitHub.flipper[:issue_hierarchy_state].enable
      GitHub.flipper[:issues_graph_api_concurrent_faraday].enable

      issue = create(:issue, repository: repo, user: user)

      # user without permissions should see nothing
      hovercard_adapter = Hovercard::Loader.load_for(
        issue,
        repo,
        user,
        cap_filter: cap_authorizing_filter
      )

      assert_empty hovercard_adapter.tracked_in_issues
    end
  end

  test "Hovercard::Loader returns the correct issue data for a pull request" do
    user = create(:user)
    repo = create(:repository, owner: user, from_example: :simple)

    pr_issue = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: repo, user: user)

    pull_request = create(:pull_request, repository: repo, issue: pr_issue, base_ref: "master",
      head_ref: "cr-line-endings", user: repo.owner)

    tracked_issue = create(:issue, repository: repo, user: user)

    # user with permissions should see tracked item
    hovercard_adapter = Hovercard::Loader.load_for(
      pr_issue.pull_request,
      repo,
      user,
      cap_filter: cap_authorizing_filter([user, pr_issue])
    )

    assert_equal pull_request.id, hovercard_adapter.database_id
    assert_equal pr_issue.number, hovercard_adapter.number
  end

  test "preloading does not execute unexpected queries for a pull request" do
    # Disable feature flag that explicitly bypasses scientist experiment
    GitHub.flipper[:use_simplified_pull_request_check_reviews_query].disable

    user = create(:user)
    repo = create(:repository, owner: user, from_example: :pull_request_source)
    issue = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: repo)
    pull_request = create(:pull_request, issue: issue, head_ref: "master-merged-topic")

    assert_queries %{
      issue_comments.has_timeline_items?
      issue_events
      notification_subscriptions
      notification_thread_subscriptions
      notification_thread_type_subscriptions
      primary_avatars
      protected_branches (review status context)
      pull_request_reviews (review status context)
      pull_request_reviews (review status context)
      pull_request_reviews (review status context)
      repository_rulesets
      review_requests (review status context)
      review_requests (review status context)
      users
    } do
      Hovercard::Loader.new(
        pull_request,
        repo,
        user,
        cap_filter: cap_authorizing_filter
      )
    end
  end

  test "preloading does not execute unexpected queries for an issue comment" do
    user = create(:user)
    repo = create(:repository, owner: user)
    issue = create(:issue, repository: repo, user: user)
    issue_comment = create(:issue_comment, :wait_for_orchestration, issue: issue, user: user)

    queries = [
      "issue_comments.has_timeline_items?",
      "issue_comments.has_timeline_items?",
      "issue_events",
      "notification_subscription_events",
      "notification_subscriptions",
      "notification_thread_subscriptions",
      "notification_thread_type_subscriptions",
      "primary_avatars",
      "users"
    ]
    queries.unshift("duplicate_issues") if GitHub.flipper[:issues_react_close_as_duplicate].enabled?
    queries = queries.join("\n")

    assert_queries queries do
      Hovercard::Loader.new(
        issue,
        repo,
        user,
        cap_filter: cap_authorizing_filter,
        comment_id: issue_comment.id,
        comment_type: IssueOrPullRequestHovercard::ISSUE_COMMENT_TYPE
      )
    end
  end

  test "does not load comment that does not belong to repo" do
    user = create(:user)
    repo = create(:repository, owner: user)
    issue = create(:issue, repository: repo, user: user)
    issue_comment = create(:issue_comment, issue: issue, user: user)
    other_repo = create(:repository)
    other_issue = create(:issue, repository: other_repo)
    other_comment = create(:issue_comment, issue: other_issue)

    loader = Hovercard::Loader.load_for(
      issue,
      repo,
      user,
      cap_filter: cap_authorizing_filter,
      comment_id: other_comment.id,
      comment_type: IssueOrPullRequestHovercard::ISSUE_COMMENT_TYPE,
    )
    assert_nil loader.comment
  end

  test "preloading does not execute unexpected queries for an issue comment created by a bot" do
    user = create(:user)
    repo = create(:repository, owner: user)
    issue = perform_enqueued_jobs(only: SubscribeAndNotifyJob) do
      create(:issue, repository: repo, user: user)
    end
    bot = create(:integration, owner: user).bot
    issue_comment = create(:issue_comment, issue: issue, user: bot)
    queries = [
      "integrations",
      "issue_comments.has_timeline_items?",
      "issue_comments.has_timeline_items?",
      "issue_events",
      "notification_subscription_events",
      "notification_subscriptions",
      "notification_thread_subscriptions",
      "notification_thread_type_subscriptions",
      "primary_avatars",
      "primary_avatars",
      "users"
    ]
    queries.unshift("duplicate_issues") if GitHub.flipper[:issues_react_close_as_duplicate].enabled? || GitHub.flipper[:issues_react_close_as_duplicate].enabled?(repo.owner)
    queries = queries.join("\n")

    assert_queries queries do
      Hovercard::Loader.new(
        issue,
        repo,
        user,
        cap_filter: cap_authorizing_filter,
        comment_id: issue_comment.id,
        comment_type: IssueOrPullRequestHovercard::ISSUE_COMMENT_TYPE
      )
    end
  end

  test "preloading does not execute unexpected queries for a pull request review" do
    # Disable feature flag that explicitly bypasses scientist experiment
    GitHub.flipper[:use_simplified_pull_request_check_reviews_query].disable

    user = create(:user)
    repo = create(:repository, owner: user, from_example: :pull_request_source)
    issue = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: repo)
    pull_request = create(:pull_request, issue: issue, head_ref: "master-merged-topic")
    pull_request_review = create(:pull_request_review, pull_request: pull_request, user: user, body: "This looks great.")

    assert_queries %{
      issue_comments.has_timeline_items?
      issue_events
      notification_subscriptions
      notification_thread_subscriptions
      notification_thread_type_subscriptions
      primary_avatars
      protected_branches (review status context)
      pull_request_reviews (review status context)
      pull_request_reviews (review status context)
      pull_request_reviews (review status context)
      pull_request_reviews (review status context)
      repository_rulesets
      review_requests (review status context)
      review_requests (review status context)
      users
    } do
      Hovercard::Loader.new(
        pull_request,
        repo,
        user,
        cap_filter: cap_authorizing_filter,
        comment_id: pull_request_review.id,
        comment_type: IssueOrPullRequestHovercard::REVIEW_TYPE
      )
    end
  end

  test "does not load pull request review that does not belong to repo" do
    user = create(:user)
    repo = create(:repository, owner: user, from_example: :pull_request_source)
    pull_request = create(:pull_request,
      repository: repo,
      base_repository: repo,
      head_repository: repo,
      head_ref: "master-merged-topic"
    )
    pull_request_review = create(:pull_request_review, pull_request: pull_request, user: user, body: "This looks great.")

    other_repo = create(:repository, from_example: :pull_request_source)
    other_pull_request = create(:pull_request,
      repository: other_repo,
      base_repository: other_repo,
      head_repository: other_repo,
      head_ref: "master-merged-topic"
    )
    other_review = create(:pull_request_review, pull_request: other_pull_request)

    loader = Hovercard::Loader.load_for(
      pull_request,
      repo,
      user,
      cap_filter: cap_authorizing_filter,
      comment_id: other_review.id,
      comment_type: IssueOrPullRequestHovercard::REVIEW_TYPE,
    )
    assert_nil loader.comment
  end

  test "it does not fail on GitRPC::CommandBusy for ReviewStatus and reports error to Failbot" do
    owner = create(:user, login: "owner", plan: "micro")
    user = create(:user, login: "pr-creator")
    forker = create(:user, login: "forker")
    reviewer = create(:user, login: "reviewer")
    source = create(:private_repository, name: "repo", owner: owner, from_example: :pull_request_source)
    source.add_member forker, action: :write
    source.add_member user, action: :write
    source.add_member reviewer, action: :write
    a_fork, msg = source.fork(forker: forker)
    assert a_fork, "forking #{source} as #{forker} failed: #{msg.inspect}"

    example_repo :pull_request_fork,   a_fork

    pull_request = PullRequest.create_for!(source,
      base: "owner:master",
      head: "forker:topic",
      user: reviewer,
      title: "cross repo PR: merging forker:topic into master",
      body: "cross repo pull request",
    )

    pull_request.base_repository.refs.find(pull_request.base_ref_name).append_commit({ message: "Add CODEOWNERS file", committer: owner }, owner) do |files|
      files.add("CODEOWNERS", <<~CODEOWNERS)
      file11   @pr-creator
      file18   @forker
    CODEOWNERS
    end

    protected_branch = create(:protected_branch, repository: source, creator: user,
      pull_request_reviews_enforcement_level: :everyone,
      require_code_owner_review: true
    )

    exception = GitRPC::CommandBusy.new("GitRPC::CommandBusy error")
    PullRequest.any_instance.stubs(:async_changed_paths_for_codeowners).raises(exception)
    Failbot.expects(:report).with(exception)

    hovercard_adapter = Hovercard::Loader.load_for(
      pull_request,
      source,
      user,
      cap_filter: cap_authorizing_filter,
    )

    refute_nil hovercard_adapter.hovercard_contexts
    assert_equal [], hovercard_adapter.hovercard_contexts
  end

  test "it does not fail on GitHub::Spokes::ClientError for ReviewStatus and reports error to Failbot" do
    user = create(:user)
    repo = create(:repository, owner: user, from_example: :pull_request_source)
    pull_request = create(:pull_request,
      repository: repo,
      base_repository: repo,
      head_repository: repo,
      head_ref: "master-merged-topic"
    )

    pull_request_review = create(:pull_request_review, :approved, pull_request: pull_request, user: user, body: "This looks great.")

    exception = GitHub::Spokes::ClientError.new("Spokes is down for ReviewStatus!")
    IssueOrPullRequestHovercard::Contexts::ReviewStatus.stubs(:async_resolve).raises(exception)
    Failbot.expects(:report).with(exception)

    hovercard_adapter = Hovercard::Loader.load_for(
      pull_request,
      repo,
      user,
      cap_filter: cap_authorizing_filter,
      comment_id: pull_request_review.id,
      comment_type: IssueOrPullRequestHovercard::REVIEW_TYPE,
    )

    refute_nil hovercard_adapter.hovercard_contexts
    assert_equal [], hovercard_adapter.hovercard_contexts
  end

  test "it does not fail on GitHub::Spokes::ClientError for MergeState and reports error to Failbot" do
    user = create(:user)
    repo = create(:repository, owner: user, from_example: :pull_request_source)
    pull_request = create(:pull_request,
      repository: repo,
      base_repository: repo,
      head_repository: repo,
      head_ref: "master-merged-topic"
    )

    pull_request_review = create(:pull_request_review, :approved, pull_request: pull_request, user: user, body: "This looks great.")

    exception = GitHub::Spokes::ClientError.new("Spokes is down for MergeState!")
    PullRequest::MergeState.any_instance.stubs(:async_pull_request_review_policy_decision).raises(exception)
    Failbot.expects(:report).with(exception)

    hovercard_adapter = Hovercard::Loader.load_for(
      pull_request,
      repo,
      user,
      cap_filter: cap_authorizing_filter,
      comment_id: pull_request_review.id,
      comment_type: IssueOrPullRequestHovercard::REVIEW_TYPE,
    )

    refute_nil hovercard_adapter.hovercard_contexts
    assert_equal [], hovercard_adapter.hovercard_contexts
  end

  test "preloading does not execute unexpected queries for a pull request review comment" do
    # Disable feature flag that explicitly bypasses scientist experiment
    GitHub.flipper[:use_simplified_pull_request_check_reviews_query].disable

    user = create(:user)
    repo = create(:repository, owner: user, from_example: :pull_request_source)
    pull_request = create(:pull_request, repository: repo, base_repository: repo, head_repository: repo, head_ref: "master-merged-topic")
    pull_request_review_comment = create(:pull_request_review_comment, pull_request: pull_request, user: user)

    assert_queries %{
      issue_comments.has_timeline_items?
      issue_events
      notification_subscription_events
      notification_subscriptions
      notification_thread_subscriptions
      notification_thread_type_subscriptions
      primary_avatars
      protected_branches (review status context)
      pull_request_review_comments
      pull_request_reviews (review status context)
      pull_request_reviews (review status context)
      pull_request_reviews (review status context)
      repository_rulesets
      review_requests (review status context)
      review_requests (review status context)
      users
    } do
      Hovercard::Loader.new(
        pull_request,
        repo,
        user,
        cap_filter: cap_authorizing_filter,
        comment_id: pull_request_review_comment.id,
        comment_type: IssueOrPullRequestHovercard::REVIEW_COMMENT_TYPE
      )
    end
  end

  test "does not load pull request review comment that does not belong to repo" do
    user = create(:user)
    repo = create(:repository, owner: user, from_example: :pull_request_source)
    pull_request = create(:pull_request,
      repository: repo,
      base_repository: repo,
      head_repository: repo,
      head_ref: "master-merged-topic"
    )
    pull_request_review_comment = create(:pull_request_review_comment, pull_request: pull_request, user: user)

    other_repo = create(:repository, from_example: :pull_request_source)
    other_pull_request = create(:pull_request,
      repository: other_repo,
      base_repository: other_repo,
      head_repository: other_repo,
      head_ref: "master-merged-topic"
    )
    other_review_comment = create(:pull_request_review_comment, pull_request: other_pull_request)

    loader = Hovercard::Loader.load_for(
      pull_request,
      repo,
      user,
      cap_filter: cap_authorizing_filter,
      comment_id: other_review_comment.id,
      comment_type: IssueOrPullRequestHovercard::REVIEW_COMMENT_TYPE,
    )
    assert_nil loader.comment
  end
end
