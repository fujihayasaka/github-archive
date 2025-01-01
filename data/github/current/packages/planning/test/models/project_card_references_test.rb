# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectCardReferencesTest < GitHub::TestCase

  fixtures do
    @owner = create(:user)
    @org = create(:organization, plan: "silver", admin: @owner)
    @team = create(:team, organization: @org)
    @team.add_member(@owner)

    @repo = create(:private_repository, owner: @org)
    @project = create(:project, owner: @repo)
    @issue = create(:issue, repository: @repo)
    @other_issue = create(:issue, repository: @repo)

    only = [Newsies::DeliverNotificationsJob]
    @post = perform_enqueued_jobs(only: only) { create(:discussion_post, team: @team) }
  end

  test "returns whether the text contains a single issue reference with no other text" do
    references = ProjectCardReferences.new(
      text: "##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_predicate references, :single_issue_reference?

    references = ProjectCardReferences.new(
      text: "#{@org}##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_predicate references, :single_issue_reference?

    references = ProjectCardReferences.new(
      text: "#{@repo.nwo}##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_predicate references, :single_issue_reference?

    references = ProjectCardReferences.new(
      text: "#{@issue.url}",
      viewer: @owner,
      project: @project,
    )
    assert_predicate references, :single_issue_reference?

    references = ProjectCardReferences.new(
      text: "##{@issue.number} ",
      viewer: @owner,
      project: @project,
    )
    assert_predicate references, :single_issue_reference?

    references = ProjectCardReferences.new(
      text: " ##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_predicate references, :single_issue_reference?

    references = ProjectCardReferences.new(
      text: "#{@owner}##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    refute_predicate references, :single_issue_reference?

    references = ProjectCardReferences.new(
      text: "##{@issue.number} ##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    refute_predicate references, :single_issue_reference?

    references = ProjectCardReferences.new(
      text: "##{@issue.number} ##{@other_issue.number}",
      viewer: @owner,
      project: @project,
    )
    refute_predicate references, :single_issue_reference?

    references = ProjectCardReferences.new(
      text: "fixing ##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    refute_predicate references, :single_issue_reference?

    references = ProjectCardReferences.new(
      text: "testing #{@repo.nwo}##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    refute_predicate references, :single_issue_reference?

    references = ProjectCardReferences.new(
      text: "a link to #{@issue.url}",
      viewer: @owner,
      project: @project,
    )
    refute_predicate references, :single_issue_reference?
  end

  test "returns referenced issues accessible to the viewer" do
    references = ProjectCardReferences.new(
      text: "read ##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_equal 1, references.issues.length
    assert_equal @issue, references.issues.first

    references = ProjectCardReferences.new(
      text: "read #{@org}/#{@repo}##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_equal 1, references.issues.length
    assert_equal @issue, references.issues.first

    references = ProjectCardReferences.new(
      text: "read #{GitHub.url}/#{@org}/#{@repo}/issues/#{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_equal 1, references.issues.length
    assert_equal @issue, references.issues.first
  end

  test "excludes references to issues not accessible to the viewer" do
    non_member = create(:user)

    references = ProjectCardReferences.new(
      text: "read #{@org}/#{@repo}##{@issue.number}",
      viewer: non_member,
      project: @project,
    )
    assert_empty references.issues

    references = ProjectCardReferences.new(
      text: "read #{@org}/#{@repo}##{@issue.number}",
      viewer: nil,
      project: @project,
    )
    assert_empty references.issues
  end

  test "excludes duplicate references" do
    references = ProjectCardReferences.new(
      text: "read ##{@issue.number} and ##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_equal 1, references.issues.length
    assert_equal @issue, references.issues.first
  end

  test "excludes references to non-existent issues" do
    references = ProjectCardReferences.new(
      text: "read ##{@other_issue.number.next}",
      viewer: @owner,
      project: @project,
    )
    assert_empty references.issues

    references = ProjectCardReferences.new(
      text: "read #{@owner}/#{@repo}##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_empty references.issues

    references = ProjectCardReferences.new(
      text: "read foo##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_empty references.issues
  end

  test "returns the single issue referenced in the text" do
    references = ProjectCardReferences.new(
      text: "##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_equal @issue, references.issue

    references = ProjectCardReferences.new(
      text: "fixing ##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_nil references.issue
  end

  test "returns whether non-issue references were included in the text" do
    references = ProjectCardReferences.new(
      text: "fixing ##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_predicate references, :non_reference_text?

    references = ProjectCardReferences.new(
      text: "fix ##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_predicate references, :non_reference_text?

    references = ProjectCardReferences.new(
      text: "[#{@org}/#{@repo}##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_predicate references, :non_reference_text?

    references = ProjectCardReferences.new(
      text: "##{@issue.number} ##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    assert_predicate references, :non_reference_text?

    references = ProjectCardReferences.new(
      text: "##{@issue.number}",
      viewer: @owner,
      project: @project,
    )
    refute_predicate references, :non_reference_text?
  end

  test "handles renamed repositories" do
    original_url = @issue.url
    @repo.rename("#{@repo.name}-plus")
    references = ProjectCardReferences.new(
      text: original_url,
      viewer: @owner,
      project: @project,
    )
    assert_equal @issue, references.issue

    @issue.reload
    references = ProjectCardReferences.new(
      text: @issue.url,
      viewer: @owner,
      project: @project,
    )
    assert_equal @issue, references.issue
  end

  context "discussion references" do
    test "includes referenced discussions" do
      references = ProjectCardReferences.new(
        text: @post.permalink,
        viewer: @owner,
        project: @project,
      )
      assert_equal @post, references.discussion
    end

    test "excludes references to non-existent discussions" do
      references = ProjectCardReferences.new(
        text: "read #{@team.permalink}/discussions/#{@post.number.next}",
        viewer: @owner,
        project: @project,
      )
      assert_empty references.discussions
    end

    test "excludes references to discussions not accessible to the viewer" do
      references = ProjectCardReferences.new(
        text: @post.permalink,
        viewer: nil,
        project: @project,
      )
      assert_empty references.discussions

      non_team_member = create(:user)
      @org.add_member(non_team_member)
      references = ProjectCardReferences.new(
        text: @post.permalink,
        viewer: non_team_member,
        project: @project,
      )
      assert_empty references.discussions

      other_team = create(:team, organization: @org)
      other_team_member = create(:user)
      other_team.add_member(other_team_member)
      references = ProjectCardReferences.new(
        text: @post.permalink,
        viewer: other_team_member,
        project: @project,
      )
      assert_empty references.discussions

      non_org_member = create(:user)
      references = ProjectCardReferences.new(
        text: @post.permalink,
        viewer: non_org_member,
        project: @project,
      )
      assert_empty references.discussions

      references = ProjectCardReferences.new(
        text: @post.permalink,
        viewer: nil,
        project: @project,
      )
      assert_empty references.discussions
    end

    test "includes all referenced discussions" do
      only = [Newsies::DeliverNotificationsJob]
      other_post = perform_enqueued_jobs(only: only) { create(:discussion_post, team: @team) }

      references = ProjectCardReferences.new(
        text: "Check out #{@post.permalink} and #{other_post.permalink}",
        viewer: @owner,
        project: @project,
      )
      assert_same_elements [@post, other_post], references.discussions
    end
  end

  context "project references" do
    test "excludes references to self" do
      references = ProjectCardReferences.new(
        text: "#{@repo.permalink}/projects/#{@project.number}",
        viewer: @owner,
        project: @project,
      )
      assert_nil references.project
    end

    test "excludes references to non-existent projects" do
      references = ProjectCardReferences.new(
        text: "#{@repo.permalink}/projects/#{@project.number.next}",
        viewer: @owner,
        project: @project,
      )
      assert_nil references.project
    end

    test "excludes references to projects not accessible to the viewer" do
      non_member = create(:user)
      repo_project = create(:project, owner: @repo)
      org_project = create(:project, owner: @org)

      references = ProjectCardReferences.new(
        text: "##{@repo.permalink}/projects/#{repo_project.number}",
        viewer: non_member,
        project: @project,
      )
      assert_empty references.projects

      references = ProjectCardReferences.new(
        text: "##{@repo.permalink}/projects/#{repo_project.number}",
        viewer: nil,
        project: @project,
      )
      assert_empty references.projects

      references = ProjectCardReferences.new(
        text: "#{GitHub.url}/orgs/#{@org}/projects/#{org_project.number}",
        viewer: non_member,
        project: @project,
      )
      assert_empty references.projects

      references = ProjectCardReferences.new(
        text: "#{GitHub.url}/orgs/#{@org}/projects/#{org_project.number}",
        viewer: nil,
        project: @project,
      )
      assert_empty references.projects
    end

    test "returns repo projects when the text contains a full project URL" do
      other_project = create(:project, owner: @repo)
      references = ProjectCardReferences.new(
        text: "#{@repo.permalink}/projects/#{other_project.number}",
        viewer: @owner,
        project: @project,
      )
      assert_equal other_project, references.project

      references = ProjectCardReferences.new(
        text: "#{@repo.permalink}/projects/#{other_project.number}#card-123456",
        viewer: @owner,
        project: @project,
      )
      assert_equal other_project, references.project
    end

    test "returns org projects when the text contains a full project URL" do
      other_project = create(:project, owner: @org)
      references = ProjectCardReferences.new(
        text: "#{GitHub.url}/orgs/#{@org}/projects/#{other_project.number}",
        viewer: @owner,
        project: @project,
      )
      assert_equal other_project, references.project

      references = ProjectCardReferences.new(
        text: "#{GitHub.url}/orgs/#{@org}/projects/#{other_project.number}?fullscreen=true",
        viewer: @owner,
        project: @project,
      )
      assert_equal other_project, references.project
    end

    test "includes all referenced projects" do
      repo_project = create(:project, owner: @repo)
      org_project = create(:project, owner: @org)

      references = ProjectCardReferences.new(
        text: "Check out #{@repo.permalink}/projects/#{repo_project.number} and #{GitHub.url}/orgs/#{@org}/projects/#{org_project.number}",
        viewer: @owner,
        project: @project,
      )
      assert_same_elements [repo_project, org_project], references.projects
    end
  end

  context "filtering unauthorized orgs" do
    test "filters out issue reference from unauthorized org" do
      references = ProjectCardReferences.new(
        text: "#{@org}/#{@repo}##{@issue.number}",
        viewer: @owner,
        project: @project,
      )

      assert_equal 1, references.issues.length
      assert_equal 1, references.accessible_reference_count
      assert_predicate references, :single_issue_reference?

      references.filter_unauthorized_orgs([@org.id])

      assert_equal 0, references.issues.length, "unexpected issue found"
      assert_equal 0, references.accessible_reference_count, "reference count not updated"
      refute_predicate references, :single_issue_reference?

      # unexpected but consistent behaviors
      assert_predicate references, :single_reference?
      refute_predicate references, :non_reference_text?
    end

    test "filters out discussion reference from unauthorized org" do
      references = ProjectCardReferences.new(
        text: @post.permalink,
        viewer: @owner,
        project: @project,
      )

      assert_equal 1, references.discussions.length
      assert_equal 1, references.accessible_reference_count
      assert_predicate references, :single_discussion_reference?

      references.filter_unauthorized_orgs([@org.id])

      assert_equal 0, references.discussions.length, "unexpected discussion found"
      assert_equal 0, references.accessible_reference_count, "reference count not updated"
      refute_predicate references, :single_discussion_reference?
    end

    test "filters out project reference from unauthorized org" do
      other_project = create(:project, owner: @repo)
      references = ProjectCardReferences.new(
        text: "#{@repo.permalink}/projects/#{other_project.number}",
        viewer: @owner,
        project: @project,
      )

      assert_equal 1, references.projects.length
      assert_equal 1, references.accessible_reference_count
      assert_predicate references, :single_project_reference?

      references.filter_unauthorized_orgs([@org.id])

      assert_equal 0, references.projects.length, "unexpected project found"
      assert_equal 0, references.accessible_reference_count, "reference count not updated"
      refute_predicate references, :single_project_reference?
    end
  end
end
