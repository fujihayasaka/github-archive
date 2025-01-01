# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectCardPrefillerTest < GitHub::TestCase
  include RepositoriesTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @owner = create :user, plan: "large"
    @org = create :organization, admin: @owner, plan: "bronze"
    @user = create(:user)
    @repo = create :private_repository, owner: @org, from_example: :commits_controller_test

    @milestone = create :milestone, repository: @repo, created_by: @owner
    @repo2 = create :repository, owner: @owner, from_example: :pull_request_source
    @otherissue = create :issue, repository: @repo, user: @owner
    @label_bug = create :label, repository: @repo, name: "bug"
    @label_feature = create :label, repository: @repo, name: "feature"
    @label_api = create :label, repository: @repo, name: "api"

    @day = 1.year.ago

    @bug = create :issue, repository: @repo, user: @owner,
      created_at: (@day += 1.day),
      state: "closed",
      milestone: @milestone
    @bug.labels << @label_bug
    create :issue_event, issue: @bug, event: "mentioned"

    @apibug = create :issue, repository: @repo, user: @owner,
      created_at: (@day += 1.day),
      assignee: @owner,
      milestone: @milestone
    @apibug.labels << @label_bug
    @apibug.labels << @label_api
    create :issue_event, issue: @apibug, event: "mentioned"

    @apibug2 = create :issue, repository: @repo, user: @owner,
      created_at: (@day += 1.day),
      assignee: @owner,
      state: "closed"
    @apibug2.labels << @label_bug
    @apibug2.labels << @label_api

    @feature = create :issue, repository: @repo, user: @owner,
      created_at: (@day += 1.day)
    @feature.labels << @label_feature
    create :issue_event, issue: @feature, event: "mentioned"

    @import1 = create :import_item, user: @owner, repository: @repo
    @import2 = create :import_item, user: @owner, repository: @repo

    @comment = create :issue_comment, issue: @bug
    @comment2 = create :issue_comment, :with_edit, issue: @apibug, user: @user
    @comment3 = create :issue_comment, issue: @apibug2, user: @user

    @pr_issue = create :issue, repository: @repo, user: @owner
    @pr = PullRequest.create_for!(@repo, user: @owner,
                                         base: "master",
                                         head: "topic",
                                         title: "some other silly changes",
                                         issue: @pr_issue)
    @pr_issue.pull_request = @pr
    @pr_issue.labels << @label_bug

    create(:issue_comment, issue: @pr.issue)
    create(:commit_comment, repository: @repo,
                       user: @user,
                       body: "legit commit comment no edit",
                       commit_id: "fc128af28cb263bf1f524f84609a7a75ffa27a9b")
    create(:commit_comment, :with_edit, repository: @repo,
                       user: @user,
                       body: "legit commit comment",
                       commit_id: "fc128af28cb263bf1f524f84609a7a75ffa27a9b")
    create :legacy_pull_request_review_comment, :with_edit, pull_request: @pr, user: @user
    create :legacy_pull_request_review_comment, pull_request: @pr, user: @user

    @project = create(:project, owner: @repo2, creator: @owner)
    @column  = create(:project_column, project: @project)

    pr_issue = create(:issue, repository: @repo2, user: @owner)
    pr = PullRequest.create_for!(@repo2, user: @repo2.owner,
                                         base: "master",
                                         head: "master-forward-2",
                                         title: "Project Polish #1337",
                                         issue: pr_issue)
    pr_issue.pull_request = pr
    create(:project_card, column: @column, content: pr_issue)
    referenced_issue1 = create(:issue, repository: @repo2, user: @owner)
    referenced_issue2 = create(:issue, repository: @repo2, user: @owner)
    referenced_issue3 = create(:issue, repository: @repo2, user: @owner)
    create(:project_card, column: @column, note: "Referencing #{referenced_issue1.url} and also #{referenced_issue2.url}")
    create(:project_card, column: @column, note: "Referencing #{referenced_issue3.url}")
    referenced_project = create(:project, owner: @repo2)
    @project_reference_card = create(:project_card, column: @column, note: "Referencing #{referenced_project.owner.permalink}/projects/#{referenced_project.number}")

    discussion_org = create(:organization, plan: "silver", admin: @owner)
    discussion_team = create(:team, organization: discussion_org)
    only = [Newsies::DeliverNotificationsJob]
    discussion_post = perform_enqueued_jobs(only: only) { create(:discussion_post, team: discussion_team) }
    @discussion_card = create(:project_card, column: @column, note: discussion_post.permalink)
  end

  test "prefill projects" do
    prefiller = ProjectCardPrefiller.new(@project, @column.cards, viewer: @owner)
    cards = @column.cards
    cards.each do |card|
      refute_predicate card.association(:creator), :loaded?
      refute_predicate card.association(:project), :loaded?
      refute_predicate card.project.association(:owner), :loaded?

      next if [@discussion_card, @project_reference_card].include?(card)

      issues = if card.is_note?
        card.references(viewer: @owner).issues
      else
        [card.content]
      end
      refute_empty issues

      issues.each do |issue|
        refute_predicate issue.association(:pull_request), :loaded? if issue.pull_request_id
        refute_predicate issue.association(:assignments), :loaded?
        refute_predicate issue.association(:user), :loaded?
        refute_predicate issue.association(:assignee), :loaded?
        refute_predicate issue.association(:labels), :loaded?

        if issue.milestone_id
          refute_predicate issue.association(:milestone), :loaded?
          refute_predicate issue.milestone.association(:created_by), :loaded?
          refute_predicate issue.milestone.association(:repository), :loaded?
        end
      end
    end

    discussions = cards.map { |card| card.references(viewer: @owner).discussions }.flatten
    refute_empty discussions

    discussions.each do |discussion|
      refute_predicate discussion.association(:user), :loaded?
    end

    prefiller.cards # this performs the prefill

    projects = cards.map { |card| card.references(viewer: @owner).projects }.flatten
    refute_empty projects

    projects.each do |project|
      assert_predicate project.association(:owner), :loaded?
    end

    cards.each do |card|
      assert_predicate card.association(:creator), :loaded?
      assert_predicate card.association(:project), :loaded?
      assert_predicate card.project.association(:owner), :loaded?

      next if [@discussion_card, @project_reference_card].include?(card)

      issues = if card.is_note?
        card.references(viewer: @owner).issues
      else
        [card.content]
      end
      refute_empty issues

      issues.each do |issue|
        if issue.pull_request_id
          assert_predicate issue.association(:pull_request), :loaded?
          assert_predicate issue.pull_request.association(:issue), :loaded?
          assert_predicate issue.pull_request.association(:repository), :loaded?
          assert_predicate issue.pull_request.association(:base_repository), :loaded?
          assert_predicate issue.pull_request.association(:head_repository), :loaded?
          assert_predicate issue.pull_request.base_repository.association(:owner), :loaded?
          assert_predicate issue.pull_request.head_repository.association(:owner), :loaded?
          assert_predicate issue.pull_request.base_repository.association(:network), :loaded?
          assert_predicate issue.pull_request.head_repository.association(:network), :loaded?
          assert_predicate issue.pull_request.association(:base_user), :loaded?
          assert_predicate issue.pull_request.association(:head_user), :loaded?
          assert_predicate issue.pull_request.association(:user), :loaded?
        end

        assert_predicate issue.association(:assignments), :loaded?
        assert_predicate issue.association(:assignees), :loaded?
        assert issue.assignments.all? { |assignment| assignment.association(:assignee).loaded? }
        assert_predicate issue.association(:user), :loaded?
        assert_predicate issue.association(:labels), :loaded?

        if issue.milestone_id
          refute_predicate issue.association(:milestone), :loaded?
          refute_predicate issue.milestone.association(:created_by), :loaded?
          refute_predicate issue.milestone.association(:repository), :loaded?
        end
      end
    end

    discussions.each do |discussion|
      assert_predicate discussion.association(:user), :loaded?
      assert_predicate discussion.association(:team), :loaded?
    end
  end

  test "prefill projects handles pull request cards with deleted repository refs" do
    # Create pull request card with a destroyed head_repository
    example_repo :simple, @repo2
    forked_repo = fast_fork_repo(@repo2, owner: @user, name: "glorious-fork")
    example_repo :simple, forked_repo
    ref = forked_repo.heads.find_or_build("master")
    ref.append_commit({ message: "some changes", committer: @user }, @user) do |files|
      files.add("file001", "foo")
    end
    forked_pull = create(:pull_request,
      repository: @repo2,
      base_repository: @repo2,
      base_user: @repo2.owner,
      base_ref: "master",
      head_repository: forked_repo,
      head_user: forked_repo.owner,
      head_ref: ref.name,
      user: @user,
    )
    create(:project_card, column: @column, content: forked_pull.issue)

    forked_repo.destroy!
    refute forked_pull.reload.head_repository.present?

    # Perform prefill
    ProjectCardPrefiller.new(@project, @column.cards, viewer: @owner).cards

    cards = @column.cards
    cards.each do |card|
      next if card.is_note?
      next unless card.content.pull_request_id

      assert card.content.pull_request.association(:base_repository), :loaded?
      assert card.content.pull_request.association(:head_repository), :loaded?
    end
  end
end
