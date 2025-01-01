# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueSearchResultTest < GitHub::TestCase
  fixtures do
    setup_search

    @repo  = create(:repository)
    @owner = @repo.owner
    @user  = create(:user)
    @repo.add_member(@user)

    @issue = create :issue, repository: @repo, user: @owner

    @reviewer = create(:user, login: "reviewer")
    org = create :organization, login: "acme", admin: @owner
    @team = create(:team, organization: org, name: "Employee", privacy: :closed)

    @org_repo = create :repository, owner: org, from_example: :rebase_pull_request
    @org_repo.add_member @user
    @org_repo.add_member @reviewer
    @team.add_member @reviewer
    @team.add_repository(@org_repo, :push)

    pr_issue = create(:issue, repository: @org_repo, user: @user)

    @pull = create :pull_request,
      repository:       @org_repo,
      base_repository:  @org_repo,
      base_user:        @org_repo.owner,
      base_ref:         "master",
      head_repository:  @org_repo,
      head_user:        @org_repo.owner,
      head_ref:         "contrib",
      issue:            pr_issue,
      draft:            false
  end

  teardown_once do
    teardown_search
  end

  test "minimal search" do
    assert results = Issue::SearchResult.search(query: "state:open", repo: @repo)
    assert_kind_of Hash, results
    assert_kind_of Integer, results[:open_count]
    assert_kind_of Integer, results[:closed_count]
  end

  test "minimal search with parsed query" do
    query = [[:state, "open"]]
    assert results = Issue::SearchResult.search(query: query, repo: @repo)
    assert_kind_of Hash, results
    assert_kind_of Integer, results[:open_count]
    assert_kind_of Integer, results[:closed_count]
  end

  test "does not execute mysql search when it's disabled", feature_enabled: :disable_mysql_search do
    query = [[:state, "open"]]
    make_searchable(@repo, @issue)
    Issue::MysqlSearch.expects(:search).never
    assert Issue::SearchResult.search(query: query, repo: @repo)
  end

  test "queues up reindex on PR if state not in sync" do
    make_searchable(@org_repo, @pull)
    PullRequest.any_instance.expects(:synchronize_search_index).returns(true).once
    Issue::EsSearch.search(query: "is:pr is:open", repo: @org_repo)
    @pull.issue.update_column("state", "closed")
    Issue::EsSearch.search(query: "is:pr is:open", repo: @org_repo)
  end

  test "doesn't queue up reindex on PR if state is merged and issue is closed" do
    @pull.mark_as_merged
    @pull.save!
    make_searchable(@org_repo, @pull.reload)
    PullRequest.any_instance.expects(:synchronize_search_index).never
    Issue::EsSearch.search(query: "is:pr is:closed", repo: @org_repo)
  end

  test "queues up reindex on issue if state not in sync" do
    make_searchable(@repo, @issue)
    Issue.any_instance.expects(:synchronize_search_index).returns(true).once
    Issue::EsSearch.search(query: "is:issue is:open", repo: @repo)
    @issue.update_column("updated_at", 1.year.ago)
    Issue::EsSearch.search(query: "is:issue is:open", repo: @repo)
  end

  context "review-required" do
    test "can find a pull request with a review required from the user" do
      @pull.review_requests.create(reviewer: @reviewer)
      make_searchable(@pull)

      results = Issue::SearchResult.search(query: [[:"review-requested", @reviewer.login]], current_user: @reviewer)
      pull_requests = results[:issues].map(&:pull_request).compact

      assert_includes pull_requests, @pull
    end

    test "can find a pull request with a review required from a team" do
      @pull.review_requests.create(reviewer: @team)
      make_searchable(@pull)

      results = Issue::SearchResult.search(query: [[:"review-requested", @reviewer.login]], current_user: @reviewer)
      pull_requests = results[:issues].map(&:pull_request).compact

      assert_includes pull_requests, @pull
    end

    test "pull requests where the user is the author are excluded" do
      @team.add_member @pull.user, adder: @owner
      @pull.review_requests.create(reviewer: @team)
      make_searchable(@pull)

      results = Issue::SearchResult.search(query: [[:"review-requested", @pull.user.login]], current_user: @pull.user)
      pull_requests = results[:issues].map(&:pull_request).compact

      refute_includes pull_requests, @pull
      assert_equal 0, results[:open_count]
      assert_equal 0, results[:closed_count]
    end
  end

  context "has-closing-reference" do
    test "can find a pull request that has a linked issue" do
      @pull.close_issue_references.create!(issue: @issue, actor_id: @pull.user.id)
      make_searchable(@pull, @issue)

      results = Issue::SearchResult.search(query: [[:"linked", "issue"]])

      assert_includes results[:issues].map(&:pull_request), @pull
      refute_includes results[:issues], @issue
    end

    test "can find an issue that has a linked pull request" do
      @issue.close_issue_references.create!(pull_request: @pull, actor_id: @issue.user.id)
      make_searchable(@pull, @issue)

      results = Issue::SearchResult.search(query: [[:"linked", "pr"]])

      assert_includes results[:issues], @issue
      refute_includes results[:issues].map(&:pull_request), @pull
    end

    test "can exclude a pull request that has a linked issue" do
      @pull.close_issue_references.create!(issue: @issue, actor_id: @pull.user.id)
      make_searchable(@pull)

      results = Issue::SearchResult.search(query: [[:"-linked", "issue"]])

      refute_includes results[:issues].map(&:pull_request), @pull
    end

    test "can exclude an issue that has a linked pull request" do
      @issue.close_issue_references.create!(pull_request: @pull, actor_id: @pull.user.id)
      make_searchable(@issue)

      results = Issue::SearchResult.search(query: [[:"-linked", "pr"]])

      refute_includes results[:issues], @issue
    end

    test "can return regular pull request when trying to exclude one with a linked issue" do
      make_searchable(@pull)

      results = Issue::SearchResult.search(query: [[:"-linked", "issue"]])

      assert_empty @pull.close_issue_references
      assert_includes results[:issues].map(&:pull_request), @pull
    end

    test "can return regular issue when trying to exclude one with a linked pr" do
      make_searchable(@issue)

      results = Issue::SearchResult.search(query: [[:"-linked", "pr"]])

      assert_empty @issue.close_issue_references
      assert_includes results[:issues], @issue
    end

    test "does not return anything if search for issue xref from an issue" do
      @issue.close_issue_references.create!(pull_request: @pull, actor_id: @issue.user.id)
      make_searchable(@issue, @pull)

      results = Issue::SearchResult.search(query: [[:"is", "issue"], [:"linked", "issue"]])

      refute_includes results[:issues], @issue
      refute_includes results[:issues].map(&:pull_request), @pull
    end

    test "does not return anything if search for pr xref from a pr" do
      @issue.close_issue_references.create!(pull_request: @pull, actor_id: @issue.user.id)
      make_searchable(@issue, @pull)

      results = Issue::SearchResult.search(query: [[:"is", "pr"], [:"linked", "pr"]])

      refute_includes results[:issues], @issue
      refute_includes results[:issues].map(&:pull_request), @pull
    end

    test "does not return anything if search for excluding issue xref from an issue" do
      make_searchable(@issue)

      results = Issue::SearchResult.search(query: [[:"is", "issue"], [:"-linked", "issue"]])

      refute_includes results[:issues], @issue
    end

    test "does not return anything if search for excluding pr xref from a pr" do
      make_searchable(@pull)

      results = Issue::SearchResult.search(query: [[:"is", "pr"], [:"-linked", "pr"]])

      refute_includes results[:issues].map(&:pull_request), @pull
    end

    test "does not return anything if searching xref link with an unsupported type" do
      @issue.close_issue_references.create!(pull_request: @pull, actor_id: @issue.user.id)
      make_searchable(@issue)

      results = Issue::SearchResult.search(query: [[:"is", "open"], [:"linked", "blah"]])

      refute_includes results[:issues], @issue
    end

    test "does not return anything if searching exclude xref link with an unsupported type" do
      @issue.close_issue_references.create!(pull_request: @pull, actor_id: @issue.user.id)
      make_searchable(@issue)

      results = Issue::SearchResult.search(query: [[:"is", "open"], [:"-linked", "blah"]])

      refute_includes results[:issues], @issue
    end
  end

  context "assignee" do
    test "can find issues assigned to a particular user" do
      @repo.disable_feature(:disable_mysql_search)

      issue_assigned_to_user  = create(:issue, repository: @repo, assignee: @user)
      issue_assigned_to_other = create(:issue, repository: @repo, assignee: @owner)
      unassigned_issue        = create(:issue, repository: @repo)

      issue_assigned_to_user_and_other = create(:issue, repository: @repo)
      issue_assigned_to_user_and_other.assignees = [@user, @owner]
      issue_assigned_to_user_and_other.save

      issues = Issue::SearchResult.search(query: "assignee:#{@user.login}", repo: @repo)[:issues]

      assert_includes issues, issue_assigned_to_user
      assert_includes issues, issue_assigned_to_user_and_other
      refute_includes issues, issue_assigned_to_other
      refute_includes issues, unassigned_issue
    end

    test "can exclude issues assigned to a particular user when they're referred to by assignee_id" do
      @repo.disable_feature(:disable_mysql_search)

      issue_assigned_to_user  = create(:issue, repository: @repo, assignee: @user)
      issue_assigned_to_other = create(:issue, repository: @repo, assignee: @owner)
      unassigned_issue        = create(:issue, repository: @repo)

      issue_assigned_to_user_and_other = create(:issue, repository: @repo, assignee: @user)
      issue_assigned_to_user_and_other.add_assignees(@owner)
      issue_assigned_to_user_and_other.save

      issues = Issue::SearchResult.search(query: "-assignee:#{@user.login}", repo: @repo)[:issues]

      refute_includes issues, issue_assigned_to_user
      refute_includes issues, issue_assigned_to_user_and_other
      assert_includes issues, issue_assigned_to_other
      assert_includes issues, unassigned_issue
    end

    test "can exclude issues assigned to a particular user when they're referred to by an assignment record" do
      @repo.disable_feature(:disable_mysql_search)

      issue_assigned_to_user  = create(:issue, repository: @repo, assignee: @user)
      issue_assigned_to_other = create(:issue, repository: @repo, assignee: @owner)
      unassigned_issue        = create(:issue, repository: @repo)

      issue_assigned_to_user_and_other = create(:issue, repository: @repo, assignee: @owner)
      issue_assigned_to_user_and_other.add_assignees(@user)
      issue_assigned_to_user_and_other.save

      issues = Issue::SearchResult.search(query: "-assignee:#{@user.login}", repo: @repo)[:issues]

      refute_includes issues, issue_assigned_to_user
      refute_includes issues, issue_assigned_to_user_and_other
      assert_includes issues, issue_assigned_to_other
      assert_includes issues, unassigned_issue
    end

    test "can find issues not assigned to anyone" do
      @repo.disable_feature(:disable_mysql_search)

      issue_assigned_to_user  = create(:issue, repository: @repo, assignee: @user)
      issue_assigned_to_other = create(:issue, repository: @repo, assignee: @owner)
      unassigned_issue        = create(:issue, repository: @repo)

      issue_assigned_to_user_and_other = create(:issue, repository: @repo)
      issue_assigned_to_user_and_other.assignees = [@user, @owner]
      issue_assigned_to_user_and_other.save

      issues = Issue::SearchResult.search(query: "no:assignee", repo: @repo)[:issues]

      refute_includes issues, issue_assigned_to_user
      refute_includes issues, issue_assigned_to_user_and_other
      refute_includes issues, issue_assigned_to_other
      assert_includes issues, unassigned_issue
    end
  end

  context "private profiles" do
    context "when a repository has been passed in" do
      test "can find issues associated with a private profile" do
        GitHub.flipper[:invalidate_private_profile_searches].enable
        private_profile = create(:user, private_profile: true)
        @repo.add_member(private_profile)
        issue = create(:issue, user: private_profile, repository: @repo)
        make_searchable(issue)

        results = Issue::SearchResult.search(query: [[:"involves", private_profile.login]], current_user: @reviewer, repo: @repo)
        result_issues = results[:issues]

        assert_equal [issue], result_issues
      end
    end

    context "when a repository has not been passed in" do
      test "can not find issues associated with a private profile" do
        GitHub.flipper[:invalidate_private_profile_searches].enable
        private_profile = create(:user, private_profile: true)
        @repo.add_member(private_profile)
        issue = create(:issue, user: private_profile, repository: @repo)

        make_searchable(issue)

        results = Issue::SearchResult.search(query: [[:"involves", private_profile.login]], current_user: @reviewer)
        result_issues = results[:issues]

        assert_equal [], result_issues
      end
    end
  end

  context "org" do
    test "only includes issues belonging to repositories owned by the specified org" do
      included_org = create(:organization, login: "included-org")
      included_repo = create(:repository, owner: included_org)
      included_issue = create(:issue, repository: included_repo)
      excluded_org = create(:organization, login: "excluded-org")
      excluded_repo = create(:repository, owner: excluded_org)
      excluded_issue = create(:issue, repository: excluded_repo)
      make_searchable(included_issue, excluded_issue)

      viewer = create(:user, login: "viewer")
      included_org.add_admin(viewer)
      excluded_org.add_admin(viewer)

      issues = Issue::SearchResult.search(query: "org:#{included_org.login}", current_user: viewer)[:issues]

      assert_same_elements [included_issue], issues
    end
  end

  context "labels" do
    test "can find issues with a particular label" do
      bug_label = create(:label, repository: @repo, name: "bug")
      task_label = create(:label, repository: @repo, name: "task")

      issue_with_bug_label = create(:issue, repository: @repo, created_at: 3.seconds.ago, labels: [bug_label])
      issue_with_task_label = create(:issue, repository: @repo, created_at: 2.seconds.ago, labels: [task_label])
      issue_with_both_labels = create(:issue, repository: @repo, created_at: 1.second.ago, labels: [bug_label, task_label])
      issue_without_labels = create(:issue, repository: @repo, labels: [])
      make_searchable(issue_with_bug_label, issue_with_task_label, issue_with_both_labels, issue_without_labels)

      issues = Issue::SearchResult.search(query: "label:bug", repo: @repo)[:issues]

      assert_includes issues, issue_with_bug_label
      refute_includes issues, issue_with_task_label
      assert_includes issues, issue_with_both_labels
      refute_includes issues, issue_without_labels
    end
  end

  context "datadog" do
    test "includes context tag if present in keyword args" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      context = "foo"
      Issue::SearchResult.search(query: "label:bug", repo: @repo, context: context)[:issues]

      assert_equal 1, GitHub.dogstats.distributions("issue.search.query.time", "tags": ["context:#{context}"]).size
    end
  end
end
