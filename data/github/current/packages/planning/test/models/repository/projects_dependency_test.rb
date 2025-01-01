# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryProjectsDependencyTest < GitHub::TestCase
  fixtures do
    @org_owner = create(:user, login: "org-owner")
    @org = create(:organization, admin: @org_owner)
    @repo = create(:repository, owner: @org)
  end

  context "validation" do
    test "project can't be created if owning repository has projects disabled" do
      @repo.disable_repository_projects(actor: @org_owner)
      refute_predicate @repo, :repository_projects_enabled?

      project = build(:project, owner: @repo, creator: @org_owner)
      refute_predicate project, :valid?
    end

    test "project can't be created if owning repository's owning organization has projects disabled" do
      @repo.disable_repository_projects(actor: @org_owner)
      refute_predicate @repo, :repository_projects_enabled?

      project = build(:project, owner: @repo, creator: @org_owner)
      refute_predicate project, :valid?
    end
  end

  context "can_enable_projects?" do
    test "true by default" do
      assert_predicate @repo, :can_enable_projects?
    end

    test "true for a user-owned repo" do
      user_owner = create(:user)
      assert_predicate create(:repository, owner: user_owner), :can_enable_projects?
    end

    test "true if the repo has projects disabled" do
      @repo.disable_repository_projects(actor: @org_owner)
      assert_predicate @repo, :can_enable_projects?
    end

    test "true if the repo's owning org has organization projects disabled" do
      @org.disable_organization_projects(actor: @org_owner)
      assert_predicate @repo, :can_enable_projects?
    end

    test "false if the repo's owning org has repository projects disabled" do
      @org.disable_repository_projects(actor: @org_owner)
      refute_predicate @repo, :can_enable_projects?
    end
  end

  context "disable_repository_projects" do
    test "disables repository projects" do
      @repo.enable_repository_projects(actor: @org_owner)
      @repo.disable_repository_projects(actor: @org_owner)
      @repo.reload

      refute_predicate @repo, :repository_projects_enabled?
    end
  end

  context "enable_repository_projects" do
    test "enables repository projects" do
      @repo.disable_repository_projects(actor: @org_owner)
      @repo.enable_repository_projects(actor: @org_owner)
      @repo.reload

      assert_predicate @repo, :repository_projects_enabled?
    end

    test "raises an error if repository projects are disabled at the org level" do
      @org.disable_repository_projects(actor: @org_owner)

      assert_raises(Repository::ProjectsDependency::CannotEnableProjectsError) do
        @repo.enable_repository_projects(actor: @org_owner)
      end
    end
  end
end
