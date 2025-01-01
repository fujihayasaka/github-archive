# typed: true
# frozen_string_literal: true

require "test_helper"

class PrefillingIssueEventsTest < GitHub::TestCase
  fixtures do
    @repo  = create(:repository, from_example: :pull_request_source)
    @repo2 = create(:repository, from_example: :pull_request_fork)

    @user  = @repo.owner
    @user2 = @repo2.owner

    @spammer   = create(:user, spammy: true)
    @suspended = create(:user, suspended_at: 1.day.ago)

    @issue = create(:issue, repository: @repo, user: @user)
    @issue.close(@user)
    @issue.open(@user)

    # exist in both repos
    @master_oid = @repo.heads.find("master").target_oid
    @topic_oid = @repo2.heads.find("topic").target_oid
    @topic_parent_oid = @repo2.heads.find("topic").target.parent_oids.first

    # only exists in the fork repo
    @rebased_topic_oid = @repo2.heads.find("topic-rebased-on-master").target_oid

    @issue.reference_from_commit(@user2,  @master_oid)
    @issue.reference_from_commit(@user2, @topic_oid, @repo2)
    @issue.reference_from_commit(@user2, @topic_parent_oid, @repo)
    @issue.reference_from_commit(@user2, @rebased_topic_oid)

    create :commit_comment, repository: @repo,  commit_id: @master_oid, user: @user
    create :commit_comment, repository: @repo,  commit_id: @master_oid, user: @spammer
    create :commit_comment, repository: @repo,  commit_id: @topic_oid,  user: @user
    create :commit_comment, repository: @repo2, commit_id: @topic_oid,  user: @user
    create :commit_comment, repository: @repo2, commit_id: @topic_oid,  user: @spammer
    create :commit_comment, repository: @repo,  commit_id: @topic_oid,  user: @user
    create :commit_comment, repository: @repo2, commit_id: @topic_parent_oid,  user: @user
    create :commit_comment, repository: @repo,  commit_id: @topic_parent_oid,  user: @spammer
    create :commit_comment, repository: @repo2, commit_id: @rebased_topic_oid, user: @user
  end

  test "does not raise when there are no events" do
    # This should not raise
    IssueEventPrefiller.prefill([])
  end

  test "sets the correct associations (including commit comments on commit-reference events)" do
    events = IssueEvent.where(issue: @issue).order(:id)
    assert_equal 6, events.length
    commit_events = events.select(&:commit?)
    assert_equal 4, commit_events.length

    events.each do |event|
      refute event.association(:issue).loaded?
      refute event.association(:repository).loaded?
      refute event.association(:actor).loaded?
    end

    commit_events.each do |event|
      refute event.association(:commit_repository).loaded?
      # not testing commit, because it's not an AR association and so doesn't
      # have `association(:commit).loaded?`, and it's not easy to clear
    end

    IssueEventPrefiller.prefill(events)

    events.each do |event|
      assert event.association(:issue).loaded?
      assert_equal @issue, event.issue

      assert event.association(:repository).loaded?
      assert_equal @repo, event.repository

      assert event.association(:actor).loaded?
      if event.event == "referenced"
        assert_equal @user2, event.actor
      else
        assert_equal @user, event.actor
      end
    end

    expected_repos = [nil, @repo2, @repo, nil]
    expected_commit_repos = [@repo, @repo2, @repo, @repo]
    expected_commits = [@master_oid, @topic_oid, @topic_parent_oid, nil]
    expected_comment_counts = if GitHub.spamminess_check_enabled?
      [1, 1, 0, nil]
    else
      [2, 2, 1, nil]
    end

    commit_events.each_with_index do |event, i|
      assert event.association(:commit_repository).loaded?
      if expected_repos[i].nil?
        assert_nil event.commit_repository
      else
        assert_equal expected_repos[i], event.commit_repository
      end
      assert_equal expected_commit_repos[i], event.repository_for_commit

      if oid = expected_commits[i]
        assert_equal oid, event.commit.oid
        assert_equal expected_commit_repos[i], event.commit.repository
        assert_equal expected_comment_counts[i], event.commit.comment_count
      else
        assert_nil event.commit
      end
    end
  end

  test "prefills milestone" do
    milestone = create(:milestone, repository: @repo, title: "Fake")
    events = @issue.events

    milestoned_event = events.first
    milestoned_event.milestone_id = milestone.id
    milestoned_event.event = "milestoned"
    milestoned_event.save!

    demilestoned_event = events.second
    demilestoned_event.milestone_title = milestone.title
    demilestoned_event.event = "demilestoned"
    demilestoned_event.save!

    IssueEventPrefiller.prefill(events)

    assert_equal milestone, events.first.milestone
    assert_equal milestone, events.second.milestone
  end

  context "memex_projects" do
    test "prefills memex_projects for auto-close events" do
      org = create(:organization)
      org_repo = create(:repository, owner: org)
      member = create(:collaborator, repository: org_repo).tap { |u| org.add_member(u) }
      project = create(:memex_project, owner: org)
      workflow = create(:memex_project_workflow, memex_project: project)
      workflow_action = workflow.actions.first
      project_2 = create(:memex_project, owner: org)
      workflow_2 = create(:memex_project_workflow, memex_project: project_2)
      workflow_action_2 = workflow_2.actions.first
      MemexHelpers.setup_organization_wide_access_for_projects("project_reader")

      issue = create(:issue, repository: org_repo)

      memex_item = create(:memex_project_item, memex_project: project, content: issue)
      memex_item.content.close(member, attributes: { performed_by_project_workflow_action_id: workflow_action.id, closing_status_in_project: "Done" })
      memex_item.content.open(member)
      memex_item.content.close(member, attributes: { performed_by_project_workflow_action_id: workflow_action.id, closing_status_in_project: "To do" })
      memex_item.content.open(member)
      memex_item.content.close(member, attributes: { performed_by_project_workflow_action_id: workflow_action_2.id, closing_status_in_project: "In progress" })

      IssueEventPrefiller.prefill(issue.events)

      closed_events = issue.events.where(event: "closed")
      expected_closers = [project, project, project_2]
      closed_events.each_with_index do |event, i|
        assert expected_closers[i], event.closer
      end
    end

    test "does not prefills memex_projects if there are none" do
      IssueEventPrefiller.prefill(@issue.events)

      @issue.events.each_with_index do |event|
        assert_nil event.closer
      end
    end
  end

  context "project events" do
    test "prefills project subjects" do
      project = create(:project, owner: @repo, name: "Fried Chicken")
      column = create(:project_column, project: project, name: "KFC")
      create(:project_card, content: @issue, column: column, creator: @repo.owner)

      events = @issue.events.where(event: "added_to_project")
      IssueEventPrefiller.prefill(events)
      event = events.first

      assert event.issue_event_detail.instance_variable_defined?(:@subject),
        "Expected for subject to be preloaded but it wasn't"
      assert_equal project, event.issue_event_detail.instance_variable_get(:@subject)
      assert_equal project, event.subject
    end
  end

  test "prefills performed_via_integration" do
    integration = create(:integration)
    @issue.modifying_integration = integration
    @issue.add_labels([create(:label, repository: @issue.repository)])

    events = @issue.events.labels
    IssueEventPrefiller.prefill(events)
    event = events.first

    assert event.association(:performed_via_integration).loaded?,
      "Expected for performed_via_integration to be preloaded but it wasn't"
  end
end
