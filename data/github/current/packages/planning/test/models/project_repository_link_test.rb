# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectRepositoryLinkTest < GitHub::TestCase
  fixtures do
    @admin = create(:user)
    @org = create(:organization, admin: @admin)
    @project = create(:project, owner: @org)
    @repo = create(:repository, owner: @org, name: "abundant-slowness")
  end

  setup do
    GitHub.context.push(actor_id: @admin.id)
  end

  context "validations" do
    test "errors if missing repository" do
      assert_raises ActiveRecord::RecordInvalid do
        create(:project_repository_link, project: @project, repository: nil, creator: @admin)
      end
    end

    test "errors if missing project" do
      assert_raises ActiveRecord::RecordInvalid do
        create(:project_repository_link, repository: @repo, project: nil, creator: @admin)
      end
    end

    test "errors if project and repo do not have the same owner" do
      assert_raises ActiveRecord::RecordInvalid do
        outside_project = create(:project, owner: @repo)
        create(:project_repository_link, project: outside_project, repository: @repo, creator: @admin)
      end
    end

    test "errors if project/repo link is not unique" do
      create(:project_repository_link, repository: @repo, project: @project, creator: @admin)

      assert_raises ActiveRecord::RecordInvalid do
        create(:project_repository_link, repository: @repo, project: @project, creator: @admin)
      end
    end

    test "errors if a project has the maximum number of links" do
      Project.stub_const(:MAX_REPOSITORY_LINKS, 3) do
        repos = create_list(:repository, Project::MAX_REPOSITORY_LINKS, owner: @org)
        repos.each { |repo| create(:project_repository_link, project: @project, repository: repo, creator: @admin) }

        assert_raises ActiveRecord::RecordInvalid do
          @project.link_repository(@repo, @admin)
        end
      end
    end

    test "errors if the repository is locked for migration" do
      @repo.lock_for_migration

      assert_raises ActiveRecord::RecordInvalid do
        create(:project_repository_link, repository: @repo, project: @project, creator: @admin)
      end
    end
  end

  context "metrics" do
    test "sends metrics to DataDog for new links" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      create(:project_repository_link)

      increments = GitHub.dogstats.increments("project_repository_link.created")
      assert_equal 1, increments.count
    end

    test "sends metrics to DataDog for deleted links" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      link = create(:project_repository_link)
      link.destroy

      increments = GitHub.dogstats.increments("project_repository_link.deleted")
      assert_equal 1, increments.count
    end

    test "does not send metrics to DataDog for deleted links if the associated project is already gone somehow" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      link = create(:project_repository_link)
      Project.where(id: link.project.id).delete_all
      link.reload.destroy

      increments = GitHub.dogstats.increments("project_repository_link.deleted")
      assert_equal 0, increments.count
    end
  end

  context "linkable_repos_for" do
    test "orders all visible repos by repo name" do
      taco_repo = create(:repository, name: "taco", owner: @org)
      sloth_repo = create(:repository, name: "sloth", owner: @org)

      results = ProjectRepositoryLink.linkable_repos_for(viewer: @admin, owner: @org)
      assert_equal [@repo, sloth_repo, taco_repo], results
    end

    test "excludes deleted repositories" do
      deleted_repo = create(:deleted_repository, owner: @org)
      results = ProjectRepositoryLink.linkable_repos_for(viewer: @admin, owner: @org)
      assert_equal [@repo], results
    end

    test "includes visible repos when viewing your own repos" do
      user = create(:paid_user)
      public_repo = create(:public_repository, name: "taco", owner: user)
      private_repo = create(:private_repository, name: "sloth", owner: user)

      results = ProjectRepositoryLink.linkable_repos_for(viewer: user, owner: user)
      assert_same_elements [public_repo, private_repo], results
    end

    test "includes visible repos when viewing another user's repos" do
      user = create(:paid_user)
      public_repo = create(:public_repository, name: "taco", owner: user)
      private_repo = create(:private_repository, name: "sloth", owner: user)
      accessible_repo = create(:private_repository, name: "zookeeper", owner: user)
      accessible_repo.add_member(@admin)

      results = ProjectRepositoryLink.linkable_repos_for(viewer: @admin, owner: user)
      assert_same_elements [public_repo, accessible_repo], results
    end

    test "excludes repos that do not match filter prefix" do
      create(:repository, name: "sloth-taco", owner: @org)
      taco_repo = create(:repository, name: "taco", owner: @org)

      results = ProjectRepositoryLink.linkable_repos_for(viewer: @admin, owner: @org, filter: "taco")
      assert_same_elements [taco_repo], results
    end

    test "excludes forks with a different parent" do
      taco_repo = create(:repository, name: "taco", owner: @org)
      forked_repo = create(:fork_repository, forker: @admin, fork_repo: taco_repo)
      forked_repo.has_issues = true
      forked_repo.save

      results = ProjectRepositoryLink.linkable_repos_for(viewer: @admin, owner: @org)
      assert_same_elements [@repo, taco_repo], results
    end

    test "allows forks with issues enabled that have the same parent" do
      taco_repo = create(:repository, name: "taco", owner: @admin)
      forked_repo = create(:fork_repository, forker: @admin, fork_repo: taco_repo, organization: @org)
      forked_repo.update!(has_issues: true)
      forked_repo.reload

      results = ProjectRepositoryLink.linkable_repos_for(viewer: @admin, owner: @org)
      assert_includes results, forked_repo
    end

    test "includes case insensitive filter matches" do
      sloth_taco_repo = create(:repository, name: "sloth-taco", owner: @org)
      sloth_repo = create(:repository, name: "SLOTH", owner: @org)

      results = ProjectRepositoryLink.linkable_repos_for(viewer: @admin, owner: @org, filter: "sLOt")
      assert_same_elements [sloth_repo, sloth_taco_repo], results
    end

    test "excludes repos not visible to viewer" do
      create(:private_repository, owner: @org)
      random_user = create(:user)

      results = ProjectRepositoryLink.linkable_repos_for(viewer: random_user, owner: @org)
      assert_same_elements [@repo], results
    end

    test "excludes repos with issues disabled" do
      create(:repository, owner: @org, has_issues: false)

      results = ProjectRepositoryLink.linkable_repos_for(viewer: @admin, owner: @org)
      assert_same_elements [@repo], results
    end

    test "returns nothing for a logged out user" do
      results = ProjectRepositoryLink.linkable_repos_for(viewer: nil, owner: @org)
      assert_empty results
    end
  end

  context "repository dependence" do
    test "destroyed when the repository is destroyed" do
      link = @project.link_repository(@repo, @admin)
      @repo.destroy

      assert_nil ProjectRepositoryLink.find_by(id: link.id)
    end
  end
end
