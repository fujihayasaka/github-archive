# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationRepositoryFilterTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "theowner"
    @member = create :user, login: "member"
    @public_member = create :user, login: "public-member"
    @org = create :organization, login: "theorg", admin: @owner
    @team = create :team, organization: @org, name: "the-team"
    @team.add_member @member
    @team.add_member @public_member
    @org.publicize_member @public_member
    @public_repo = create(:public_repository, owner: @org, name: "public-repo")
    @private_repo = create(:private_repository, owner: @org, name: "private-repo")
  end

  context "results" do
    test "returning only public repositories via phrase" do
      filter = Organization::RepositoryFilter.new(@org, viewer: @owner, phrase: "only:public")
      assert_equal [@public_repo], filter.results
    end

    test "returning only public repositories via type" do
      filter = Organization::RepositoryFilter.new(@org, viewer: @owner, type: "public")
      assert_equal [@public_repo], filter.results
    end

    test "returning only private repositories via phrase" do
      filter = Organization::RepositoryFilter.new(@org, viewer: @owner, phrase: "only:private")
      assert_equal [@private_repo], filter.results
    end

    test "returning only private repositories via type" do
      filter = Organization::RepositoryFilter.new(@org, viewer: @owner, type: "private")
      assert_equal [@private_repo], filter.results
    end

    if GitHub.mirrors_enabled?
      test "returning only mirror repositories via phrase" do
        mirror = create(:mirror_repository, owner: @org)
        filter = Organization::RepositoryFilter.new(@org, viewer: @owner, phrase: "only:mirror")
        assert_equal [mirror], filter.results
      end

      test "returning only mirror repositories via type" do
        mirror = create(:mirror_repository, owner: @org)
        filter = Organization::RepositoryFilter.new(@org, viewer: @owner, type: "mirror")
        assert_equal [mirror], filter.results
      end
    end

    test "returning only forks via phrase" do
      forked_repo = create(:fork_repository, forker: @org.admins.first, fork_repo: create(:public_repository, name: "forked-repo"), organization: @org)
      filter = Organization::RepositoryFilter.new(@org, viewer: @owner, phrase: "only:forks")
      assert_equal [forked_repo], filter.results
    end

    test "returning only forks via type" do
      forked_repo = create(:fork_repository, forker: @org.admins.first, fork_repo: create(:public_repository, name: "forked-repo"), organization: @org)
      filter = Organization::RepositoryFilter.new(@org, viewer: @owner, type: "fork")
      assert_equal [forked_repo], filter.results
    end

    test "returning only sources via phrase" do
      forked_repo = create(:fork_repository, forker: @org.admins.first, fork_repo: create(:public_repository, name: "forked-repo"), organization: @org)
      filter = Organization::RepositoryFilter.new(@org, viewer: @owner, phrase: "only:sources")
      assert_same_elements [@public_repo, @private_repo], filter.results
    end

    test "returning only sources via type" do
      forked_repo = create(:fork_repository, forker: @org.admins.first, fork_repo: create(:public_repository, name: "forked-repo"), organization: @org)
      filter = Organization::RepositoryFilter.new(@org, viewer: @owner, type: "source")
      assert_same_elements [@public_repo, @private_repo], filter.results
    end

    test "does not return repositories user doesn't have access to" do
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:none, actor: @owner) }
      other_private_repo = create(:private_repository, :minimal, owner: @org, name: "other-private")
      collaborator = create(:user)
      collaborator_team = create :team, organization: @org, name: "collaborator-team"
      collaborator_team.add_member collaborator
      collaborator_team.add_repository other_private_repo, :pull

      filter = Organization::RepositoryFilter.new(@org, viewer: collaborator, phrase: "only:private")
      assert_equal [other_private_repo], filter.results
    end

    test "does not leak private repos" do
      private_repo = create(:private_repository, :minimal, owner: @org, name: "other-private")
      filter = Organization::RepositoryFilter.new(@org, viewer: create(:user), phrase: "only:private")
      assert_empty filter.results
    end

    test "accepts a scope of repositories from which to filter" do
      included_repo = create(:repository, :minimal, owner: @org, name: "included-repo")
      not_included_repo = create(:repository, :minimal, owner: @org, name: "not-included-repo")
      filter = Organization::RepositoryFilter.new(@org, viewer: create(:user), phrase: "included-repo",
                                                  scope: Repository.where(id: included_repo.id))
      assert_equal [included_repo], filter.results
    end

    test "matches a private repo owner's login if it's not the current org" do
      @org.allow_private_repository_forking(actor: @org.admins.first)

      forker = @org.admins.first
      fork = create(:fork_repository, forker: forker, fork_repo: @private_repo)

      # Search for the forker's login
      filter = Organization::RepositoryFilter.new(@org, viewer: @owner, phrase: forker.login)

      assert_equal [fork], filter.results
    end

    test "doesn't match the repo owner's login if it's the current org" do
      repo_named_after_org = create(:repository, :minimal, owner: @org, name: @org.login)

      # Search for the org's login
      filter = Organization::RepositoryFilter.new(@org, viewer: @owner, phrase: @org.login)

      assert_equal [repo_named_after_org], filter.results
    end
  end
end
