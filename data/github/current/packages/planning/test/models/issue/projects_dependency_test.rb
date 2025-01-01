# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueProjectsTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner)
    @issue = create(:issue, repository: @repo)
    @project = create(:project, owner: @repo)
    @project_column = create(:project_column, project: @project)
    @project_card = create(:project_card, column: @project_column, content: @issue)
    @project_column.prioritize_card!(@project_card)
  end

  context "associations" do
    test "has projects" do
      assert_same_elements [@project], @issue.projects
    end

    test "has project columns" do
      assert_same_elements [@project_column], @issue.project_columns
    end
  end

  context "visible_projects_for" do
    test "includes projects that the issue is in and that the user has access to" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo)
      viewer = create(:user, login: "viewer")
      org.add_member(viewer)

      project = create(:project, owner: org)
      project.update_org_permission(nil)
      project.update_user_permission(viewer, :read)

      column = create(:project_column, project: project)
      create(:project_card, column: column, content: issue)

      assert_same_elements [project], issue.visible_projects_for(viewer)
    end

    test "excludes projects that the issue is in but that the user does not have access to" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo)
      viewer = create(:user, login: "viewer")
      org.add_member(viewer)

      project = create(:project, owner: org)
      project.update_org_permission(nil)

      column = create(:project_column, project: project)
      create(:project_card, column: column, content: issue)

      assert_empty issue.visible_projects_for(viewer)
    end

    test "excludes projects that the user has access to but that the issue is not in" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo)
      viewer = create(:user, login: "viewer")
      org.add_member(viewer)

      project = create(:project, owner: org)
      project.update_org_permission(nil)
      project.update_user_permission(viewer, :read)

      assert_empty issue.visible_projects_for(viewer)
    end
  end

  context "potential_projects_for" do
    test "returns repo projects" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo)
      viewer = create(:user, login: "viewer")

      project = create(:project, owner: repo)
      repo.add_member(viewer, action: :write)

      assert_same_elements [project], issue.potential_projects_for(viewer, ids: [project.id])
    end

    test "returns org projects" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo)
      viewer = create(:user, login: "viewer")

      project = create(:project, owner: org)
      project.update_user_permission(viewer, :write)

      assert_same_elements [project], issue.potential_projects_for(viewer, ids: [project.id])
    end

    test "excludes projects the viewer can't see" do
      org = create(:organization, plan: "bronze")
      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo)
      viewer = create(:user, login: "viewer")

      project = create(:project, owner: org, public: false)

      assert_empty issue.potential_projects_for(viewer, ids: [project.id])
    end

    test "excludes projects not included in the ids list" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo)
      viewer = create(:user, login: "viewer")

      project_in_list = create(:project, owner: org)
      project_in_list.update_user_permission(viewer, :write)

      project_not_in_list = create(:project, owner: org)
      project_not_in_list.update_user_permission(viewer, :write)

      assert_same_elements [project_in_list], issue.potential_projects_for(viewer, ids: [project_in_list.id])
    end
  end
end

class IssueAssociatedCardsTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)

    @org = create(:organization, plan: "silver", admin: @owner)
    @org_project = create(:project, owner: @org)
    @org_project_column = create(:project_column, project: @org_project)

    @private_repository = create(:private_repository, owner: @org)
    @repository_project = create(:project, owner: @private_repository)
    @repository_project_column = create(:project_column, project: @repository_project)
    @issue = create(:issue, repository: @private_repository)
  end

  test "includes cards from projects owned by the issue repo" do
    repo = create(:repository, owner: @owner)
    project = create(:project, owner: repo)
    issue = create(:issue, repository: repo)
    card = create(:project_card, content: issue, project: project)

    assert_includes issue.associated_cards, card
  end

  test "includes cards from projects owned by the issue repo's organization" do
    org = create(:organization)
    project = create(:project, owner: org)
    org_repo = create(:repository, owner: org)
    issue = create(:issue, repository: org_repo)
    card = create(:project_card, content: issue, project: project)

    assert_includes issue.associated_cards, card
  end

  test "deleting issue is deleting cards in the background" do
    repo = create(:repository, owner: @owner)
    project = create(:project, owner: repo)
    issue = create(:issue, repository: repo)
    card = create(:project_card, content: issue, project: project)

    issue.destroy
    perform_enqueued_jobs(only: [DestroyDependentRecordsJob])

    assert_equal 0, ProjectCard.all.size
  end

  context "`only_for_enabled_projects` argument" do
    test "includes card from project whose owning repo has projects enabled" do
      @private_repository.enable_repository_projects(actor: @owner)
      card = create(:project_card, content: @issue, column: @repository_project_column)

      assert_includes @issue.associated_cards(only_for_enabled_projects: true), card
    end

    test "excludes card from project whose owning repo has projects disabled" do
      # disable after creating card to ensure model validation passes
      card = create(:project_card, content: @issue, column: @repository_project_column)
      @private_repository.disable_repository_projects(actor: @owner)

      refute_includes @issue.associated_cards(only_for_enabled_projects: true), card
      # assert that passing `only_for_enabled_projects: true` is what changes visibility in this case
      assert_includes @issue.associated_cards(only_for_enabled_projects: false), card
    end

    test "includes card from project whose owning org has org projects enabled" do
      @org.enable_organization_projects(actor: @owner)
      card = create(:project_card, content: @issue, column: @org_project_column)

      assert_includes @issue.associated_cards(only_for_enabled_projects: true), card
    end

    test "excludes card from project whose owning org has org projects disabled" do
      # disable after creating card to ensure model validation passes
      card = create(:project_card, content: @issue, column: @org_project_column)
      @org.disable_organization_projects(actor: @owner)

      refute_includes @issue.associated_cards(only_for_enabled_projects: true), card
      # assert that passing `only_for_enabled_projects: true` is what changes visibility in this case
      assert_includes @issue.associated_cards(only_for_enabled_projects: false), card
    end

    test "excludes card from project whose owning repo's org has repo projects disabled" do
      # disable after creating card to ensure model validation passes
      card = create(:project_card, content: @issue, column: @repository_project_column)
      @org.disable_repository_projects(actor: @owner)

      refute_includes @issue.associated_cards(only_for_enabled_projects: true), card
      # assert that passing `only_for_enabled_projects: true` is what changes visibility in this case
      assert_includes @issue.associated_cards(only_for_enabled_projects: false), card
    end

    test "ignores unrelated configuration entries with projects enabled" do
      @private_repository.enable_repository_projects(actor: @owner)
      @private_repository.set_force_push_rejection("default", @owner)
      card = create(:project_card, content: @issue, column: @repository_project_column)

      assert_includes @issue.associated_cards(only_for_enabled_projects: true), card
    end

    test "ignores unrelated configuration entries with projects disabled" do
      # disable after creating card to ensure model validation passes
      card = create(:project_card, content: @issue, column: @repository_project_column)
      @private_repository.disable_repository_projects(actor: @owner)
      @private_repository.set_force_push_rejection("default", @owner)

      refute_includes @issue.associated_cards(only_for_enabled_projects: true), card
    end
  end
end
