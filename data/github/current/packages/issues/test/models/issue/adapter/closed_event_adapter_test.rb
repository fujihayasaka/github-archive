# typed: true
# frozen_string_literal: true

require "test_helper"

class ClosedEventAdapterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include GitHub::PullRequestTestHelpers

  test "adapting a closed event does not execute any queries" do
    user = create(:user)
    other_user = create(:user)
    repo = create(:repository, owner: user)
    create(:profile, user: user)
    issue = create(:issue, repository: repo, user: user)
    create(:issue_event, event: "closed", issue: issue, actor: other_user)

    Platform::Security::RepositoryAccess.with_viewer(user) do
      loader = Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      closed_event = loader.context.events.find { |e| e.event == "closed" }
      _adapted, queries = log_cleaned_queries do
        Issue::Adapter::ClosedEventAdapter.new(loader.context, event_id: closed_event.id)
      end
      assert_equal 0, queries.count
    end
  end

  test "adapting a closed event with a PR closer does not execute any queries" do
    pull = make_pr_and_repos
    repo = pull.repository
    issue = create(:issue, repository: repo)
    viewer = issue.user
    create(:profile, user: viewer)
    create(:profile, user: @make_pr_repo_owner)

    perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { pull.issue.update!(body: "Closes ##{issue.number}") }
    perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(viewer) }

    loader = Issue::ShowLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
    closed_event = loader.context.events.find { |e| e.event == "closed" }

    adapter = T.let(nil, T.nilable(Issue::Adapter::ClosedEventAdapter))
    _adapted, queries = log_cleaned_queries do
      adapter = Issue::Adapter::ClosedEventAdapter.new(loader.context, event_id: closed_event.id)
    end

    assert T.must(adapter).closer
    assert_equal 0, queries.count
  end

  test "Adapter does not shows closer when there is insufficient read permissions" do
    private_repo = create(:private_repository, from_example: :simple)
    private_repo_owner = private_repo.owner

    public_repo = create(:repository)
    public_repo_owner = public_repo.owner
    issue = create(:issue, repository: public_repo, user: private_repo_owner)

    create(:profile, user: private_repo_owner)
    create(:profile, user: public_repo_owner)

    pull = PullRequest.create_for!(private_repo,
      base: "master",
      head: "cr-line-endings",
      user: private_repo_owner,
      title: "convert to CR line ending",
      body: "Closes #{public_repo.nwo}##{issue.number}",
    )

    perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(private_repo_owner) }

    loader = Issue::ShowLoader.new issue, public_repo, public_repo_owner, cap_filter: cap_authorizing_filter

    closed_event = loader.context.events.find { |e| e.event == "closed" }

    adapter = T.let(nil, T.nilable(Issue::Adapter::ClosedEventAdapter))
    _adapted, queries = log_cleaned_queries do
      adapter = Issue::Adapter::ClosedEventAdapter.new(loader.context, event_id: closed_event.id)
    end

    assert_equal 0, queries.count
    refute T.must(adapter).closer
  end

  test "Adapter only shows closer when there is sufficient read permissions" do
    private_repo = create(:private_repository, from_example: :simple)
    private_repo_owner = private_repo.owner

    public_repo = create(:repository)
    public_repo_owner = public_repo.owner
    issue = create(:issue, repository: public_repo, user: private_repo_owner)

    create(:profile, user: private_repo_owner)
    create(:profile, user: public_repo_owner)

    pull = perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) do
      PullRequest.create_for!(private_repo,
        base: "master",
        head: "cr-line-endings",
        user: private_repo_owner,
        title: "convert to CR line ending",
        body: "Closes #{public_repo.nwo}##{issue.number}",
      )
    end

    perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { pull.merge(private_repo_owner) }

    loader = Issue::ShowLoader.new issue, public_repo, private_repo_owner, cap_filter: cap_authorizing_filter

    closed_event = loader.context.events.find { |e| e.event == "closed" }

    adapter = T.let(nil, T.nilable(Issue::Adapter::ClosedEventAdapter))
    _adapted, queries = log_cleaned_queries do
      adapter = Issue::Adapter::ClosedEventAdapter.new(loader.context, event_id: closed_event.id)
    end

    assert_equal 0, queries.count
    assert T.must(adapter).closer
  end

  test "adapting a closed event with a commit closer does not execute any queries" do
    pull = make_pr_and_repos
    repo = pull.repository
    issue = create(:issue, repository: repo)
    viewer = issue.user
    committer = create(:user)

    head_ref = pull.repository.heads.find_or_build(pull.head_ref)
    commit = append_dummy_commit(head_ref, commit_message: "Closes ##{issue.number}")

    # Theoretically, merging the PR like so:
    #
    # pull.merge(committer)
    #
    # should close the issue and add a closed event to the issue's timeline.
    #
    # In practice, this is not happening here. Maybe because there is a background job or something
    # like that, that makes this dance happen in the live website – I don't know.
    # Therefore, manually creating the closed event, with a reference to the commit's oid.
    create(:issue_event, event: "closed", issue: issue, actor: committer, commit_id: commit.oid)

    loader = Issue::ShowLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
    closed_event = loader.context.events.find { |e| e.event == "closed" }
    _adapted, queries = log_cleaned_queries do
      Issue::Adapter::ClosedEventAdapter.new(loader.context, event_id: closed_event.id)
    end
    assert_equal 0, queries.count
  end

  context "close reasons" do
    test "adapting a closed event with a reason works as expected" do
      user = create(:user)
      other_user = create(:user)
      repo = create(:repository, owner: user)
      create(:profile, user: user)
      issue = create(:issue, repository: repo, user: user)
      create(:issue_event, event: "closed", issue: issue, actor: other_user, state_reason: "not_planned")

      Platform::Security::RepositoryAccess.with_viewer(user) do
        loader = Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
        closed_event = loader.context.events.find { |e| e.event == "closed" }
        _adapted, queries = log_cleaned_queries do
          adapted = Issue::Adapter::ClosedEventAdapter.new(loader.context, event_id: closed_event.id)
          assert_equal "NOT_PLANNED", adapted.state_reason
        end
        assert_equal 0, queries.count
      end
    end
  end

  context "Auto-close project workflow" do
    test "adapting a closed event does not execute any queries" do
      org = create(:organization)
      org_repo = create(:repository, owner: org)
      user = create(:user).tap { |u| org.add_member(u) }
      collaborator = create(:collaborator, repository: org_repo).tap { |u| org.add_member(u) }
      issue = create(:issue, repository: org_repo, user: user)
      project = create(:memex_project, owner: org)
      MemexHelpers.setup_organization_wide_access_for_projects("project_reader")
      workflow = create(:memex_project_workflow, memex_project: project)
      workflow_action = workflow.actions.first

      memex_item = create(:memex_project_item, memex_project: project, content: issue)
      event = create(:issue_event, issue: memex_item.content, actor: collaborator, performed_by_project_workflow_action_id: workflow_action.id, column_name: "Done", event: "closed")

      Platform::Security::RepositoryAccess.with_viewer(user) do
        loader = Issue::ShowLoader.new issue, org_repo, user, cap_filter: cap_authorizing_filter
        closed_event = loader.context.events.find { |e| e.event == "closed" }
        adapter = T.let(nil, T.nilable(Issue::Adapter::ClosedEventAdapter))
        _adapted, queries = log_cleaned_queries do
          adapter = Issue::Adapter::ClosedEventAdapter.new(loader.context, event_id: closed_event.id)
          assert_equal "Done", adapter.column_name
        end
        assert T.must(adapter).closer
        assert_equal 0, queries.count
      end
    end

    test "Adapter does not show memex project event closer if insufficient read permissions" do
      org = create(:organization)
      org_repo = create(:repository, owner: org)
      project = create(:memex_project, owner: org)
      user = create(:user)
      issue = create(:issue, repository: org_repo)
      memex_item = create(:memex_project_item, memex_project: project, content: issue)

      workflow = create(:memex_project_workflow, memex_project: project)
      workflow_action = workflow.actions.first

      event = create(:issue_event, issue: memex_item.content, performed_by_project_workflow_action_id: workflow_action.id, column_name: "Done", event: "closed")
      loader = Issue::ShowLoader.new issue, org_repo, user, cap_filter: cap_authorizing_filter
      closed_event = loader.context.events.find { |e| e.event == "closed" }

      adapter = T.let(nil, T.nilable(Issue::Adapter::ClosedEventAdapter))
      _adapted, queries = log_cleaned_queries do
        adapter = Issue::Adapter::ClosedEventAdapter.new(loader.context, event_id: closed_event.id)
      end

      assert_equal 0, queries.count
      refute T.must(adapter).closer
    end
  end
end
