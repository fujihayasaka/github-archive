# typed: true
# frozen_string_literal: true

require "test_helper"

class UserAssociatedRepositoryIdsTest < GitHub::TestCase

  fixtures do
    @user = create :paid_user, login: "user"

    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
      @org = create :organization, login: "org"
      @org.update_default_repository_permission(:none, actor: @org.admins.first)
    end
    @org_team = create(:team, organization: @org)

    @other_user = create :paid_user, login: "other-user"

    @foreign_user = create :user, login: "foreign-user"
    @foreign_org = create :organization, login: "foreign-org", admin: @foreign_user

    # public repositories:
    @user_public_repo  = create :repository, owner: @user, name: "user-public-repo", from_example: :simple
    @other_public_repo = create :repository, owner: @other_user, name: "other-public-repo", from_example: :simple
    @user_fork         = fork_repo @other_public_repo, @user
    @org_public_repo   = create :repository, owner: @org, name: "org-public-repo"

    # private repositories:
    @user_private_repo  = create :private_repository, owner: @user, name: "user-private-repo", from_example: :simple
    @other_private_repo = create :private_repository, owner: @other_user, name: "other-private-repo", from_example: :simple
    @org_private_repo   = create :private_repository, owner: @org, name: "org-private-repo", from_example: :simple

    # Allow private repository forking
    @org.allow_private_repository_forking(actor: @org.admins.first, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

    # Resulting in:
    #
    # user/user-public-repo
    # user/user-private-repo
    #
    # other-user/other-public-repo
    #   |
    #   ` user/other-public-repo
    # other-user/other-private-repo
    #
    # org/org-public-repo
    # org/org-private-repo

    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
      @biz_org = create(:enterprise_linked_organization)
      @biz_org.update_default_repository_permission(:none, actor: @biz_org.admins.first)
    end
    @internal_repo = create(:internal_repository, owner: @biz_org)

    # all repo role fixtures
    @arr_user = create(:user)
    @arr_org = create :business_plus_organization
    @arr_org.add_member(@arr_user)

    @arr_org_repo = create :repository, owner: @arr_org
    @arr_org_repo_2 = create :repository, owner: @arr_org

    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
      @arr_org.update_default_repository_permission(:none, actor: @arr_org.admins.first)
    end

    @arr_team = create(:team, organization: @arr_org)
    @arr_team.add_member(@arr_user)

    @custom_org_write_role = create(:custom_all_repo_role, base_role_id: Role.write_role.id, owner_id: @arr_org.id, owner_type: "Organization")
    @custom_org_read_role = create(:custom_all_repo_role, base_role_id: Role.read_role.id, owner_id: @arr_org.id, owner_type: "Organization")
  end

  def fork_repo(repo, forker, opts = {})
    if opts.delete(:inline)
      only = [RepositoryAddTeamsJob]
      forked, status = perform_enqueued_jobs(only: only) { repo.fork(opts.merge(forker: forker)) }
    else
      forked, status = repo.fork(opts.merge(forker: forker))
    end

    assert_equal :created, status
    forked
  end

  context "#relationship_to" do
    test "returns :none when user has no connection to repository" do
      assert_equal :none, create(:user).relationship_to(create :repository)
    end

    test "returns :owner when user owns repository" do
      user = create(:user)
      repo = create(:repository, owner: user)

      assert_equal :owner, user.relationship_to(repo)
    end

    test "returns :member when user has read access to the repository" do
      repo = create(:repository)
      user = create(:user)
      repo.add_member(user)

      assert_equal :member, user.relationship_to(repo)
    end

    test "returns :member when user has write access to the repository" do
      repo = create(:repository)
      user = create(:user)
      repo.add_member(user, action: :write)

      assert_equal :member, user.relationship_to(repo)
    end
  end

  context "argument validation" do
    test "raises ArgumentError for invalid 'min_action' value" do
      user = create(:user)

      assert_raises(ArgumentError) do
        user.associated_repository_ids(min_action: :bogus)
      end

      user.associated_repository_ids(min_action: :read)
    end

    test "raises ArgumentError for invalid 'including' value" do
      user = create(:user)

      assert_raises(ArgumentError) do
        user.associated_repository_ids(including: :bogus)
      end

      assert_raises(ArgumentError) do
        user.associated_repository_ids(including: [:bogus])
      end

      user.associated_repository_ids(including: :owned)

      user.associated_repository_ids(including: [:owned])
    end

    test "raises ArgumentError for unknown option key" do
      assert_raises(ArgumentError) do
        @user.associated_repository_ids(owner_affiliations: [:owned])
      end
    end
  end

  context "timing" do
    test "tracks calls with no repository_ids" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @user.associated_repository_ids

      timings = GitHub.dogstats.distributions("associated_repository_ids.calculate_ids.dist")
      assert_equal ["includes_repository_ids:false", "use_db_repository_filter:false", "includes_organization:false", "org_admin:false", "many_repos:false"], timings.first.tags.to_a
    end

    test "tracks calls with minimal repository_ids" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @user.associated_repository_ids(repository_ids: [])

      timings = GitHub.dogstats.distributions("associated_repository_ids.calculate_ids.dist")
      assert_equal ["includes_repository_ids:true", "use_db_repository_filter:true", "includes_organization:false", "org_admin:false", "many_repos:false"], timings.first.tags.to_a
    end

    test "tracks calls with more repository_ids" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      Repositories::AssociatedRepositoriesDependency::AssociatedRepositories.stub_const(:RUBY_INTERSECTION_THRESHOLD, 1) do
        @user.associated_repository_ids(repository_ids: [@user_public_repo.id, @user_private_repo.id, @user_fork.id])
      end

      timings = GitHub.dogstats.distributions("associated_repository_ids.calculate_ids.dist")
      assert_equal ["includes_repository_ids:true", "use_db_repository_filter:false", "includes_organization:false", "org_admin:false", "many_repos:true"], timings.first.tags.to_a
    end
  end

  context "distribution" do
    test "tracks calls with no repository_ids" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @user.associated_repository_ids
      dist = GitHub.dogstats.distributions("associated_repository_ids.dist")
      tags = ["includes_repository_ids:false", "use_db_repository_filter:false", "includes_organization:false", "org_admin:false", "many_repos:false", "include_repo_count_bracket:0", "result_count_bracket:0", "including:[:direct, :indirect, :owned]", "min_action:undefined", "include_indirect_forks:true", "include_oopfs:true"]
      assert_equal tags, dist.first.tags.to_a
    end

    test "tracks calls with min_action" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @user.associated_repository_ids(min_action: :write)
      dist = GitHub.dogstats.distributions("associated_repository_ids.dist")
      tags = ["includes_repository_ids:false", "use_db_repository_filter:false", "includes_organization:false", "org_admin:false", "many_repos:false", "include_repo_count_bracket:0", "result_count_bracket:0", "including:[:direct, :indirect, :owned]", "min_action:write", "include_indirect_forks:true", "include_oopfs:true"]
      assert_equal tags, dist.first.tags.to_a
    end

    test "tracks calls with indirect_forks and include_oopfs" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @user.associated_repository_ids(include_indirect_forks: false, include_oopfs: false)
      dist = GitHub.dogstats.distributions("associated_repository_ids.dist")
      tags = ["includes_repository_ids:false", "use_db_repository_filter:false", "includes_organization:false", "org_admin:false", "many_repos:false", "include_repo_count_bracket:0", "result_count_bracket:0", "including:[:direct, :indirect, :owned]", "min_action:undefined", "include_indirect_forks:false", "include_oopfs:false"]
      assert_equal tags, dist.first.tags.to_a
    end

    test "tracks calls with including" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @user.associated_repository_ids(including: :direct)
      dist = GitHub.dogstats.distributions("associated_repository_ids.dist")
      tags = ["includes_repository_ids:false", "use_db_repository_filter:false", "includes_organization:false", "org_admin:false", "many_repos:false", "include_repo_count_bracket:0", "result_count_bracket:0", "including:[:direct]", "min_action:undefined", "include_indirect_forks:true", "include_oopfs:true"]
      assert_equal tags, dist.first.tags.to_a
    end

    test "clusters repo count into brackets" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      Repositories::AssociatedRepositoriesDependency::AssociatedRepositories.stub_const(:COUNT_BRACKET, 1) do
        @user.associated_repository_ids(repository_ids: [@user_public_repo.id, @user_private_repo.id, @user_fork.id])
      end
      dist = GitHub.dogstats.distributions("associated_repository_ids.dist")
      tags = ["includes_repository_ids:true", "use_db_repository_filter:true", "includes_organization:false", "org_admin:false", "many_repos:false", "include_repo_count_bracket:3", "result_count_bracket:3", "including:[:direct, :indirect, :owned]", "min_action:undefined", "include_indirect_forks:true", "include_oopfs:true"]
      assert_equal tags, dist.first.tags.to_a
    end

    test "uses clustering limit to avoid unbounded tag values" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      Repositories::AssociatedRepositoriesDependency::AssociatedRepositories.stub_const(:COUNT_BRACKET, 1) do
        Repositories::AssociatedRepositoriesDependency::AssociatedRepositories.stub_const(:COUNT_BRACKET_LIMIT, 2) do
          @user.associated_repository_ids(repository_ids: [@user_public_repo.id, @user_private_repo.id, @user_fork.id])
        end
      end
      dist = GitHub.dogstats.distributions("associated_repository_ids.dist")
      tags = ["includes_repository_ids:true", "use_db_repository_filter:true", "includes_organization:false", "org_admin:false", "many_repos:false", "include_repo_count_bracket:2", "result_count_bracket:2", "including:[:direct, :indirect, :owned]", "min_action:undefined", "include_indirect_forks:true", "include_oopfs:true"]
      assert_equal tags, dist.first.tags.to_a
    end
  end

  context "optimization" do
    test "filters successfully using database if there are a low number of records to filter by" do
      repo_id = @user_private_repo.id

      with_mysql_instrumentation_tracking do
        Repositories::AssociatedRepositoriesDependency::AssociatedRepositories.stub_const(:RUBY_INTERSECTION_THRESHOLD, 100) do
          ids = @user.associated_repository_ids(repository_ids: [repo_id])
          assert_equal [repo_id], ids
        end

        query_count = GitHub::MysqlInstrumenter.queries.map(&:sql).count { |s| s =~ /IN \('#{repo_id}'\)/ }
        assert query_count > 0
      end
    end

    test "filters successfully using ruby intersections if there are many records to filter by" do
      repo_id = @user_private_repo.id

      with_mysql_instrumentation_tracking do
        Repositories::AssociatedRepositoriesDependency::AssociatedRepositories.stub_const(:RUBY_INTERSECTION_THRESHOLD, 0) do
          ids = @user.associated_repository_ids(repository_ids: [repo_id])
          assert_equal [repo_id], ids
        end

        query_count = GitHub::MysqlInstrumenter.queries.map(&:sql).count { |s| s =~ /IN \('#{repo_id}'\)/ }
        assert_equal 0, query_count
      end
    end
  end

  context "default return value" do
    test "includes personally-owned repos and forks" do
      assert_same_elements [@user_public_repo.id, @user_private_repo.id, @user_fork.id], @user.associated_repository_ids
    end

    test "only includes repositories matching the given repository ids" do
      assert_same_elements [@user_public_repo.id], @user.associated_repository_ids(repository_ids: [@user_public_repo.id])
      assert_same_elements [@user_public_repo.id, @user_private_repo.id], @user.associated_repository_ids(repository_ids: [@user_public_repo.id, @user_private_repo.id])

      assert_same_elements [], @user.associated_repository_ids(repository_ids: [])

      assert_same_elements [], @user.associated_repository_ids(repository_ids: [@other_private_repo.id])
      assert_same_elements [], @user.associated_repository_ids(repository_ids: [@other_public_repo.id])

      assert_same_elements [@user_public_repo.id], @user.associated_repository_ids(repository_ids: [@user_public_repo.id, @other_public_repo.id])
    end

    test "includes forks of personal private repos" do
      @user_private_repo.add_member @other_user
      other_fork = fork_repo @user_private_repo, @other_user
      assert_includes @user.associated_repository_ids, other_fork.id
    end

    test "excludes forks of personal public repos" do
      other_fork = fork_repo @user_public_repo, @other_user
      refute_includes @user.associated_repository_ids, other_fork.id
    end

    test "excludes root of personally-owned public fork" do
      assert_includes @user.associated_repository_ids, @user_fork.id
      refute_includes @user.associated_repository_ids, @user_fork.parent.id
    end

    test "includes personal repos where user is a collaborator" do
      refute_includes @user.associated_repository_ids, @other_public_repo.id
      @other_public_repo.add_member @user
      @user.reload

      assert_includes @user.associated_repository_ids, @other_public_repo.id
      refute_includes @user.associated_repository_ids, @other_private_repo.id

      @other_private_repo.add_member @user
      @user.reload
      assert_includes @user.associated_repository_ids, @other_private_repo.id
    end

    test "includes forks of personal private repos where user is a collaborator only on the root" do
      @other_private_repo.add_member @user
      @other_private_repo.add_member @foreign_user

      foreign_fork = fork_repo @other_private_repo, @foreign_user
      assert_includes @user.associated_repository_ids, foreign_fork.id
    end

    test "excludes forks of personal public repos where user is a collaborator only on the root" do
      foreign_fork = fork_repo @other_public_repo, @foreign_user
      refute_includes @user.associated_repository_ids, foreign_fork.id
    end

    test "excludes root of personal repos where user is a collaborator only on the fork" do
      @other_private_repo.add_member @foreign_user
      public_fork = fork_repo @other_public_repo, @foreign_user
      private_fork = fork_repo @other_private_repo, @foreign_user

      public_fork.add_member @user
      private_fork.add_member @user

      assert_includes @user.associated_repository_ids, public_fork.id
      assert_includes @user.associated_repository_ids, private_fork.id
      refute_includes @user.associated_repository_ids, @other_public_repo.id
      refute_includes @user.associated_repository_ids, @other_private_repo.id
    end

    test "includes org repos where user is an admin of the org" do
      refute_includes @user.associated_repository_ids, @org_public_repo.id
      refute_includes @user.associated_repository_ids, @org_private_repo.id
      @org.add_admin @user
      @user.reload

      assert_includes @user.associated_repository_ids, @org_public_repo.id
      assert_includes @user.associated_repository_ids, @org_private_repo.id
    end

    test "Default includes org repos when user granted all repo role" do
      assert_empty @arr_user.associated_repository_ids
      @arr_org.grant_org_role(assignee: @arr_user, role: @custom_org_write_role)
      @arr_user.reload

      assert_includes @arr_user.associated_repository_ids, @arr_org_repo.id
      assert_includes @arr_user.associated_repository_ids, @arr_org_repo_2.id
    end

    test "Default includes org repos when team granted all repo role" do
      assert_empty @arr_user.associated_repository_ids
      @arr_org.grant_org_role(assignee: @arr_team, role: @custom_org_write_role)
      @arr_user.reload

      assert_includes @arr_user.associated_repository_ids, @arr_org_repo.id
      assert_includes @arr_user.associated_repository_ids, @arr_org_repo_2.id
    end

    test "Includes org repos via all repo role when :indirect specified" do
      assert_empty @arr_user.associated_repository_ids
      @arr_org.grant_org_role(assignee: @arr_user, role: @custom_org_write_role)

      assert_includes @arr_user.associated_repository_ids(including: [:indirect]), @arr_org_repo.id
      assert_includes @arr_user.associated_repository_ids(including: [:indirect]), @arr_org_repo_2.id
    end

    test "Does not include org repos via all repo role when :direct specified" do
      @arr_org.grant_org_role(assignee: @arr_user, role: @custom_org_write_role)
      assert_equal 2, @arr_user.associated_repository_ids.count

      @arr_org_repo.add_member(@arr_user)
      @arr_user.reload
      assert_equal 1, @arr_user.associated_repository_ids(including: [:direct]).count
    end

    test "Includes org repos via all repo role when :indirect_via_all_repo_role specified" do
      assert_empty @arr_user.associated_repository_ids
      @arr_org.grant_org_role(assignee: @arr_user, role: @custom_org_write_role)

      assert_equal 2, @arr_user.associated_repository_ids(including: [:indirect_via_all_repo_role]).count
    end

    test "Includes org repos via all repo role when read/write/admin level specified" do
      assert_empty @arr_user.associated_repository_ids
      @arr_org.grant_org_role(assignee: @arr_user, role: @custom_org_read_role)

      assert_equal 2, @arr_user.associated_repository_ids(min_action: :read).count
      assert_empty @arr_user.associated_repository_ids(min_action: :write)
      assert_empty @arr_user.associated_repository_ids(min_action: :admin)
    end

    test "Includes all repo roles repos only when in repo list provided" do
      @arr_org.grant_org_role(assignee: @arr_user, role: @custom_org_write_role)
      assert_equal 2, @arr_user.associated_repository_ids.count

      assert_equal 1, @arr_user.associated_repository_ids(repository_ids: [@arr_org_repo.id]).count
      assert_includes @arr_user.associated_repository_ids(repository_ids: [@arr_org_repo.id]), @arr_org_repo.id

      assert_equal 1, @arr_user.associated_repository_ids(repository_ids: [@arr_org_repo_2.id]).count
      assert_includes @arr_user.associated_repository_ids(repository_ids: [@arr_org_repo_2.id]), @arr_org_repo_2.id

      assert_equal 0, @arr_user.associated_repository_ids(repository_ids: [@user_public_repo.id, @other_public_repo.id]).count
    end

    test "works with all repo role team assignment + filtering" do
      GitHub.flipper[:filter_arr_user_associated_repos].enable
      assert_empty @arr_user.associated_repository_ids
      @arr_org.grant_org_role(assignee: @arr_team, role: @custom_org_write_role)

      @arr_user.reload
      assert_equal 2, @arr_user.associated_repository_ids.count

      @arr_user.reload
      assert_equal 2, @arr_user.associated_repository_ids(repository_ids: [@arr_org_repo.id, @arr_org_repo_2.id]).count
    end

    test "includes org-owned forks of private repos owned by an org that the user is an admin of" do
      GitHub.flipper[:bypass_oopfs_query].disable
      GitHub.flipper[:bypass_oopfs_query_org].disable

      @org_team.add_member @foreign_user
      @org_team.add_repository @org_private_repo, :pull

      oopf = fork_repo @org_private_repo, @foreign_user, org: @foreign_org

      refute_includes @user.associated_repository_ids, oopf.id

      @org.add_admin @user

      @user.reload

      assert_includes @user.associated_repository_ids, oopf.id

      GitHub.flipper[:bypass_oopfs_query].enable
      @user.reload
      refute_includes @user.associated_repository_ids, oopf.id
    end

    test "excludes root of org-owned fork where user is an admin or team member of the forking org" do
      @org_team.add_member @foreign_user
      admin = @org.admin
      @org.add_admin @user

      public_fork = fork_repo @other_public_repo, admin, org: @org
      @org_team.add_repository public_fork, :pull

      assert_includes @user.associated_repository_ids, public_fork.id
      refute_includes @user.associated_repository_ids, @other_public_repo.id

      @other_private_repo.add_member admin
      private_fork = fork_repo @other_private_repo, admin, org: @org
      res = @org_team.add_repository private_fork, :pull

      assert_equal [public_fork.id, private_fork.id], @foreign_user.reload.associated_repository_ids

      assert_includes @user.reload.associated_repository_ids, private_fork.id
      refute_includes @user.associated_repository_ids, @other_private_repo.id
    end

    test "excludes forks of public org repo where user is an admin or team member of the owning org" do
      @org.add_admin @user
      @org_team.add_repository @org_public_repo, :pull
      example_repo :simple, @org_public_repo
      @org_team.add_member @other_user

      public_fork = fork_repo @org_public_repo, @foreign_user

      assert_includes @user.associated_repository_ids, @org_public_repo.id
      refute_includes @user.associated_repository_ids, public_fork.id

      assert_includes @other_user.associated_repository_ids, @org_public_repo.id
      refute_includes @other_user.associated_repository_ids, public_fork.id
    end

    test "includes org repos accessible via regular team membership" do
      refute_includes @user.associated_repository_ids, @org_public_repo.id
      refute_includes @user.associated_repository_ids, @org_private_repo.id

      @org_team.add_member @user
      @org_team.add_repository @org_public_repo, :pull
      @org_team.add_repository @org_private_repo, :pull

      @user.reload

      assert_includes @user.associated_repository_ids, @org_public_repo.id
      assert_includes @user.associated_repository_ids, @org_private_repo.id
    end

    test "excludes org-owned forks of private org repo where user only has regular team membership access to the root" do
      @org_team.add_member @user
      @org_team.add_member @foreign_user
      @org_team.add_repository @org_private_repo, :pull

      oopf = fork_repo @org_private_repo, @foreign_user, org: @foreign_org

      assert_includes @user.associated_repository_ids, @org_private_repo.id
      refute_includes @user.associated_repository_ids, oopf.id
    end

    test "includes forks of org-owned repos that are owned by other users and the user has indirect access to" do
      forker = create(:user, login: "forker")
      @org_team.add_member(forker)
      @org_team.add_member(@user)
      @org_team.add_repository(@org_private_repo, :pull)

      org_private_repo_fork = fork_repo(@org_private_repo, forker, inline: true)

      assert_includes @user.associated_repository_ids, org_private_repo_fork.id
    end

    test "includes org's private repositories when that org has a default repository permission" do
      @org.add_member(@user)

      refute_includes @user.associated_repository_ids, @org_private_repo.id

      @org_private_repo.add_organization(@org, action: :read)

      @user.reload

      assert_includes @user.associated_repository_ids, @org_private_repo.id
    end

    test "filters repos based on .using_oauth?" do
      user   = create(:user)
      app    = create :oauth_application

      access = make_oauth user, %w(repo), app
      personal_access = create :personal_token_oauth_access_with_token, user: user,
        scopes: %w(repo)

      org    = create :organization, admin: user
      team   = create(:team, organization: org, permission: "admin")
      repo   = create(:repository, owner: org)

      team.add_member(user)
      team.add_repository(repo, :admin)

      assert_includes user.associated_repository_ids, repo.id

      # Same user, using OAuth
      oauth = User.with_oauth_hashed_token(access.hashed_token)
      assert_includes oauth.associated_repository_ids, repo.id

      # Now with restrictions enabled
      org.enable_oauth_application_restrictions
      oauth.reload
      refute_includes oauth.associated_repository_ids, repo.id

      # With a personal access token
      oauth = User.with_oauth_hashed_token(personal_access.hashed_token)
      oauth.reload
      assert_includes oauth.associated_repository_ids, repo.id
    end if GitHub.oauth_application_policies_enabled?

    test "can explicitly ignore repos based on .using_oauth?" do
      user   = create(:user)
      app    = create :oauth_application

      access = make_oauth user, %w(repo), app
      personal_access = create :personal_token_oauth_access_with_token, user: user,
        scopes: %w(repo)

      org    = create :organization, admin: user
      team   = create(:team, organization: org, permission: "admin")
      repo   = create(:repository, owner: org)

      team.add_member(user)
      team.add_repository(repo, :admin)

      assert_includes user.associated_repository_ids, repo.id

      # Same user, using OAuth
      oauth = User.with_oauth_hashed_token(access.hashed_token)
      assert_includes oauth.associated_repository_ids, repo.id

      # Now with restrictions enabled
      org.enable_oauth_application_restrictions
      assert_includes oauth.associated_repository_ids(include_oauth_restriction: false), repo.id

      # With a personal access token
      oauth = User.with_oauth_hashed_token(personal_access.hashed_token)
      assert_includes oauth.associated_repository_ids, repo.id
    end if GitHub.oauth_application_policies_enabled?

    test "filters private org forks of user-owned repos based on .using_oauth?" do
      user   = create :user, plan: "medium"
      app    = create :oauth_application

      access = make_oauth user, %w(repo), app
      personal_access = create :personal_token_oauth_access_with_token, user: user,
        scopes: %w(repo)

      org    = create :organization, admin: user
      org.add_admin(user)

      repo   = create(:private_repository, owner: user)

      org_priv_fork, status = repo.fork(forker: user, org: org)
      assert_equal :created, status
      assert_equal repo, org_priv_fork.parent

      assert org_priv_fork.adminable_by?(user)

      assert_includes user.associated_repository_ids, org_priv_fork.id

      # Same user, using OAuth
      oauth = User.with_oauth_hashed_token(access.hashed_token)
      assert_includes oauth.associated_repository_ids, org_priv_fork.id

      # Now with restrictions enabled
      org.enable_oauth_application_restrictions
      oauth.reload
      refute_includes oauth.associated_repository_ids, org_priv_fork.id

      # With a personal access token
      oauth = User.with_oauth_hashed_token(personal_access.hashed_token)
      assert_includes oauth.associated_repository_ids, org_priv_fork.id
    end if GitHub.oauth_application_policies_enabled?

    test "does not return duplicate repositories" do
      @org_team.add_member @foreign_user
      @org_team.add_repository @org_private_repo, :pull
      other_team = create(:team, organization: @org)
      other_team.add_member @foreign_user
      other_team.add_repository @org_private_repo, :pull

      assert_equal [@org_private_repo.id], @foreign_user.associated_repository_ids
    end

    test "returns repositories that are accessible through team ancestors" do
      parent_team = create :team, organization: @org, privacy: :closed
      child_team = create :team, organization: @org, privacy: :closed, name: "child", parent_team_id: parent_team.id
      child_team.add_member @foreign_user
      parent_team.add_repository @org_private_repo, :pull

      assert_equal [@org_private_repo.id], @foreign_user.associated_repository_ids
    end
  end

  context "only repos owned by the user" do
    test "includes personally-owned repos" do
      assert_includes @user.associated_repository_ids, @user_public_repo.id
      assert_includes @user.associated_repository_ids(including: [:owned]), @user_public_repo.id
    end

    test "includes forks the owns" do
      assert_includes @user.associated_repository_ids, @user_fork.id
      assert_includes @user.associated_repository_ids(including: [:owned]), @user_fork.id
    end

    test "excludes personal repos where user is only a collaborator" do
      refute_includes @user.associated_repository_ids, @other_public_repo.id
      @other_public_repo.add_member @user

      @user.reload
      assert_includes @user.associated_repository_ids, @other_public_repo.id
      refute_includes @user.associated_repository_ids(including: [:owned]), @other_public_repo.id
    end

    test "excludes private org repos where user is an admin of the owning org" do
      @org.add_admin @user
      assert_includes @user.associated_repository_ids, @org_public_repo.id
      assert_includes @user.associated_repository_ids, @org_private_repo.id
      refute_includes @user.associated_repository_ids(including: [:owned]), @org_public_repo.id
      refute_includes @user.associated_repository_ids(including: [:owned]), @org_private_repo.id
    end

    test "excludes org repos accessible via regular team membership" do
      @org_team.add_repository @org_private_repo, :pull
      @org_team.add_member @user

      assert @org_private_repo.pullable_by?(@user)

      assert_includes @user.associated_repository_ids, @org_private_repo.id
      refute_includes @user.associated_repository_ids(including: [:owned]), @org_private_repo.id
    end
  end

  context "only repos where the user is a direct collaborator" do
    test "excludes personally-owned repos" do
      assert_includes @user.associated_repository_ids, @user_public_repo.id
      refute_includes @user.associated_repository_ids(including: [:direct]), @user_public_repo.id
    end

    test "includes personal repos where user is a collaborator" do
      assert_equal [], @user.associated_repository_ids(including: [:direct])

      @other_private_repo.add_member(@user)

      assert_includes @user.associated_repository_ids, @other_private_repo.id
      assert_equal [@other_private_repo.id], @user.associated_repository_ids(including: [:direct])
    end

    test "excludes org repos where user is an admin of the owning org" do
      @org.add_admin @user
      assert_includes @user.associated_repository_ids, @org_private_repo.id
      refute_includes @user.associated_repository_ids(including: [:direct]), @org_private_repo.id
    end

    test "excludes org repos accessible via regular team membership" do
      @org_team.add_member(@user)
      @org_team.add_repository(@org_private_repo, :pull)

      assert_includes @user.associated_repository_ids, @org_private_repo.id
      refute_includes @user.associated_repository_ids(including: [:direct]), @org_private_repo.id
    end
  end

  context "only repos where the user has an indirect ability grant" do
    test "excludes personally-owned repos" do
      assert_includes @user.associated_repository_ids, @user_private_repo.id
      refute_includes @user.associated_repository_ids(including: [:indirect]), @user_private_repo.id
    end

    test "excludes personal repos where user is a collaborator" do
      @other_private_repo.add_member @user

      assert_includes @user.associated_repository_ids, @other_private_repo.id
      refute_includes @user.associated_repository_ids(including: [:indirect]), @other_private_repo.id
    end

    test "includes org repos where user is an admin of the owning org" do
      refute_includes @user.associated_repository_ids, @org_private_repo.id

      @org.add_admin @user

      @user.reload

      assert_includes @user.associated_repository_ids, @org_private_repo.id
      assert_includes @user.associated_repository_ids(including: [:indirect]), @org_private_repo.id
    end

    test "includes org repos accessible via regular team membership" do
      refute_includes @user.associated_repository_ids, @org_private_repo.id

      @org_team.add_repository @org_private_repo, :pull
      @org_team.add_member @user

      @user.reload

      assert_includes @user.associated_repository_ids, @org_private_repo.id
      assert_includes @user.associated_repository_ids(including: [:indirect]), @org_private_repo.id
    end

    test "includes forks of private org-owned repo where user is an admin of the owning org" do
      GitHub.flipper[:bypass_oopfs_query].disable
      GitHub.flipper[:bypass_oopfs_query_org].disable

      @org_team.add_member @foreign_user
      @org_team.add_repository @org_private_repo, :pull

      oopf = fork_repo @org_private_repo, @foreign_user, org: @foreign_org

      refute_includes @user.associated_repository_ids, oopf.id

      @org.add_admin @user

      @user.reload

      assert_includes @user.associated_repository_ids, oopf.id
      assert_includes @user.associated_repository_ids(including: [:indirect]), oopf.id

      GitHub.flipper[:bypass_oopfs_query].enable
      @user.reload
      refute_includes @user.associated_repository_ids, oopf.id
      refute_includes @user.associated_repository_ids(including: [:indirect]), oopf.id
    end

    test "excludes forks of private org repo where user only has regular team membership access to the root" do
      @org_team.add_member @foreign_user
      @org_team.add_repository @org_private_repo, :pull

      oopf = fork_repo @org_private_repo, @foreign_user, org: @foreign_org

      @org_team.add_member @user
      refute oopf.pullable_by?(@user)

      refute_includes @user.associated_repository_ids, oopf.id
      refute_includes @user.associated_repository_ids(including: [:indirect]), oopf.id
    end

    test "can include only repositories granted via adminship" do
      adminned_org = perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
        org = create :organization
        org.update_default_repository_permission(:none, actor: org.admins.first)
        org
      end
      adminned_org_private_repo = create :private_repository, owner: adminned_org

      user_associated_repository_ids = @user.associated_repository_ids
      refute_includes user_associated_repository_ids, @org_private_repo.id
      refute_includes user_associated_repository_ids, adminned_org_private_repo.id

      adminned_org.add_admin @user
      @org_team.add_member @user
      @org_team.add_repository @org_private_repo, :pull

      @user.reload

      user_associated_repository_ids = @user.associated_repository_ids(including: :indirect_via_adminship)
      refute_includes user_associated_repository_ids, @org_private_repo.id, "should not include team grant"
      assert_includes user_associated_repository_ids, adminned_org_private_repo.id, "should include adminned repo"
    end

    test "can include only repositories granted via membership" do
      adminned_org = perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
        org = create :organization
        org.update_default_repository_permission(:none, actor: org.admins.first)
        org
      end
      adminned_org_private_repo = create :private_repository, owner: adminned_org

      user_associated_repository_ids = @user.associated_repository_ids
      refute_includes user_associated_repository_ids, @org_private_repo.id
      refute_includes user_associated_repository_ids, adminned_org_private_repo.id

      adminned_org.add_admin @user
      @org_team.add_member @user
      @org_team.add_repository @org_private_repo, :pull

      @user.reload

      user_associated_repository_ids = @user.associated_repository_ids(including: :indirect_via_membership)
      assert_includes user_associated_repository_ids, @org_private_repo.id, "should include team grant"
      refute_includes user_associated_repository_ids, adminned_org_private_repo.id, "should not include adminned repo"
    end
  end

  context "only repos with a minimum ability action" do
    test "read/write/admin actions include personally-owned repos" do
      assert_includes @user.associated_repository_ids, @user_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :read), @user_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :write), @user_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :admin), @user_private_repo.id
    end

    test "read/write actions include forks of personally-owned private repos" do
      @user_private_repo.add_member @other_user
      forked = fork_repo @user_private_repo, @other_user

      assert_includes @user.associated_repository_ids, forked.id
      assert_includes @user.associated_repository_ids(min_action: :read), forked.id
      assert_includes @user.associated_repository_ids(min_action: :write), forked.id
      refute_includes @user.associated_repository_ids(min_action: :admin), forked.id
    end

    test "read/write actions include personal repos where user is a collaborator" do
      @other_private_repo.add_member @user

      assert_includes @user.associated_repository_ids, @other_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :read), @other_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :write), @other_private_repo.id
      refute_includes @user.associated_repository_ids(min_action: :admin), @other_private_repo.id
    end

    test "read/write actions include forks of personal private repos where user is a collaborator only on the root" do
      @other_private_repo.add_member @user
      @other_private_repo.add_member @foreign_user

      forked = fork_repo @other_private_repo, @foreign_user

      assert_includes @user.associated_repository_ids, forked.id
      assert_includes @user.associated_repository_ids(min_action: :read), forked.id
      assert_includes @user.associated_repository_ids(min_action: :write), forked.id
      refute_includes @user.associated_repository_ids(min_action: :admin), forked.id
    end

    test "read/write/admin actions include org-owned repos where user is an admin of the owning org" do
      refute_includes @user.associated_repository_ids, @org_private_repo.id

      @org.add_admin @user

      @user.reload

      assert_includes @user.associated_repository_ids, @org_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :read), @org_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :write), @org_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :admin), @org_private_repo.id
    end

    test "only read action includes forks of private org-owned repo where user is an admin of the owning org" do
      GitHub.flipper[:bypass_oopfs_query].disable
      GitHub.flipper[:bypass_oopfs_query_org].disable

      @org_team.add_member @foreign_user
      @org_team.add_repository @org_private_repo, :pull

      oopf = fork_repo @org_private_repo, @foreign_user, org: @foreign_org

      refute_includes @user.associated_repository_ids, oopf.id

      @org.add_admin @user

      @user.reload

      assert_includes @user.associated_repository_ids, oopf.id
      assert oopf.pullable_by?(@user)
      assert_includes @user.associated_repository_ids(min_action: :read), oopf.id
      refute oopf.pushable_by?(@user)
      refute_includes @user.associated_repository_ids(min_action: :write), oopf.id
      refute oopf.adminable_by?(@user)
      refute_includes @user.associated_repository_ids(min_action: :admin), oopf.id

      GitHub.flipper[:bypass_oopfs_query].enable
      @user.reload
      refute_includes @user.associated_repository_ids(min_action: :read), oopf.id
    end

    test "read action includes org repos accessible via regular team membership for team with 'pull' permissions" do
      @org_team.update permission: "pull"
      @org_team.add_member @user
      @org_team.add_repository @org_private_repo, :pull

      assert_includes @user.associated_repository_ids, @org_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :read), @org_private_repo.id
      refute_includes @user.associated_repository_ids(min_action: :write), @org_private_repo.id
      refute_includes @user.associated_repository_ids(min_action: :admin), @org_private_repo.id
    end

    test "read/write actions include org repos accessible via regular team membership for team with 'push' permissions" do
      @org_team.update permission: "push"
      @org_team.add_member @user
      @org_team.add_repository @org_private_repo, :push

      assert_includes @user.associated_repository_ids, @org_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :read), @org_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :write), @org_private_repo.id
      refute_includes @user.associated_repository_ids(min_action: :admin), @org_private_repo.id
    end

    test "read/write/admin actions include org repos accessible via regular team membership for team with 'admin' permissions" do
      @org_team.update permission: "admin"
      @org_team.add_repository @org_private_repo, :admin

      refute_includes @user.associated_repository_ids, @org_private_repo.id

      @org_team.add_member @user

      @user.reload

      assert_includes @user.associated_repository_ids, @org_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :read), @org_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :write), @org_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :admin), @org_private_repo.id
    end

    test "handles repos where abilities permissions are less than the legacy team permission level" do
      @org_team.add_member(@user)
      assert @org_team.add_repository(@org_private_repo, "pull").success?

      assert_includes @user.associated_repository_ids, @org_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :read), @org_private_repo.id
      refute_includes @user.associated_repository_ids(min_action: :write), @org_private_repo.id
      refute_includes @user.associated_repository_ids(min_action: :admin), @org_private_repo.id
    end

    test "handles repos where abilities permissions are greater than the legacy team permission level" do
      refute_includes @user.associated_repository_ids, @org_private_repo.id

      @org_team.add_member(@user)
      assert @org_team.add_repository(@org_private_repo, "admin").success?

      @user.reload

      assert_includes @user.associated_repository_ids, @org_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :read), @org_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :write), @org_private_repo.id
      assert_includes @user.associated_repository_ids(min_action: :admin), @org_private_repo.id
    end
  end

  context "excluding indirect forks" do
    test "excludes forks of org-owned repos that are owned by other users and the user has indirect access to" do
      forker = create(:user, login: "forker")
      @org_team.add_member(forker)
      @org_team.add_member(@user)
      @org_team.add_repository(@org_private_repo, :pull)

      org_private_repo_fork = fork_repo(@org_private_repo, forker)

      refute_includes @user.associated_repository_ids(include_indirect_forks: false), org_private_repo_fork.id
    end

    test "includes forks of org-owned repos that are owned by other users and the user has direct access to" do
      forker = create(:user, login: "forker")
      @org.add_member(forker)
      @org_team.add_member(forker)
      @org.add_member(@user)
      @org_team.add_member(@user)
      @org_team.add_repository(@org_private_repo, :pull)

      org_private_repo_fork = fork_repo(@org_private_repo, forker)
      org_private_repo_fork.add_member(@user)

      assert_includes @user.associated_repository_ids(include_indirect_forks: false), org_private_repo_fork.id
    end

    test "includes forks of org-owned repos that are owned by the user" do
      @org_team.add_member(@user)
      @org_team.add_repository(@org_private_repo, :pull)

      org_private_repo_fork = fork_repo(@org_private_repo, @user)

      assert_includes @user.associated_repository_ids(include_indirect_forks: false), org_private_repo_fork.id
    end

    test "excludes forks of org-owned repos that are owned by the user when restricted to indirect access" do
      @org_team.add_member(@user)
      @org_team.add_repository(@org_private_repo, :pull)

      org_private_repo_fork = fork_repo(@org_private_repo, @user)

      refute_includes @user.associated_repository_ids(including: [:indirect], include_indirect_forks: false), org_private_repo_fork.id
    end

    test "excludes org-owned forks of private repos owned by an org that the user is an admin of" do
      @org_team.add_member @foreign_user
      @org_team.add_repository @org_private_repo, :pull

      oopf = fork_repo @org_private_repo, @foreign_user, org: @foreign_org

      refute_includes @user.associated_repository_ids(include_indirect_forks: false), oopf.id

      @org.add_admin @user

      refute_includes @user.associated_repository_ids(include_indirect_forks: false), oopf.id
    end
  end

  context "excluding org-owned forks of private org-owned repos" do
    test "works when the source repo is owned by an org that the user is an admin of" do
      GitHub.flipper[:bypass_oopfs_query].disable
      GitHub.flipper[:bypass_oopfs_query_org].disable

      @org_team.add_member @foreign_user
      @org_team.add_repository @org_private_repo, :pull

      oopf = fork_repo @org_private_repo, @foreign_user, org: @foreign_org

      refute_includes @user.associated_repository_ids, oopf.id
      refute_includes @user.associated_repository_ids(include_oopfs: false), oopf.id

      @org.add_admin @user

      @user.reload

      assert_includes @user.associated_repository_ids, oopf.id
      refute_includes @user.associated_repository_ids(include_oopfs: false), oopf.id

      GitHub.flipper[:bypass_oopfs_query].enable
      @user.reload
      refute_includes @user.associated_repository_ids, oopf.id
      refute_includes @user.associated_repository_ids(include_oopfs: false), oopf.id
    end
  end

  test "excludes org-owned forks of private org-owned repos when bypass flag is enabled" do
    GitHub.flipper[:bypass_oopfs_query].disable
    GitHub.flipper[:bypass_oopfs_query_org_killswitch].enable

    # Setup a scenario where a @user is admin of two orgs, both have private repos that have been forked into
    # a third org. One of the orgs has the bypass flag enabled, the other does not. We should only see the fork
    # from the org that does not have the bypass flag enabled.
    @org.add_admin @user
    @org_team.add_member @foreign_user
    @org_team.add_repository @org_private_repo, :pull
    oopf = fork_repo @org_private_repo, @foreign_user, org: @foreign_org

    another_org = perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
      o = create(:organization)
      o.add_admin @user
      o.update_default_repository_permission(:none, actor: @org.admins.first)
      o
    end
    another_org.allow_private_repository_forking(actor: @user, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
    another_team = create(:team, organization: another_org)
    another_team.add_member @foreign_user
    another_repo = create(:private_repository, owner: another_org)
    another_team.add_repository another_repo, :pull
    oopf2 = fork_repo another_repo, @foreign_user, org: @foreign_org

    @user.reload

    GitHub.flipper[:bypass_oopfs_query_org].enable(@org)
    GitHub.flipper[:bypass_oopfs_query_org].disable(another_org)

    ari = @user.associated_repository_ids
    refute_includes ari, oopf.id
    assert_includes ari, oopf2.id
  end

  context "scoping to an organization" do
    test "includes only directs from the organization when scoping" do
      collab_user = create(:user)

      foreign_org_private_repo = create :private_repository, owner: @foreign_org, from_example: :simple

      @org_private_repo.add_member(collab_user)
      foreign_org_private_repo.add_member(collab_user)

      assert_includes collab_user.associated_repository_ids(including: [:direct], organization: @org), @org_private_repo.id
      refute_includes collab_user.associated_repository_ids(including: [:direct], organization: @org), foreign_org_private_repo.id
    end

    test "includes all directs when not scoping" do
      collab_user = create(:user)

      foreign_org_private_repo = create :private_repository, owner: @foreign_org, from_example: :simple

      @org_private_repo.add_member(collab_user)
      foreign_org_private_repo.add_member(collab_user)

      assert_includes collab_user.associated_repository_ids(including: [:direct]), @org_private_repo.id
      assert_includes collab_user.associated_repository_ids(including: [:direct]), foreign_org_private_repo.id
    end

    test "excludes indirect forks when scoping" do
      org_admin = @org.admins.first
      forker = create(:user, login: "forker")
      @org_team.add_member(forker)
      @org_team.add_repository(@org_private_repo, :pull)

      org_private_repo_fork = fork_repo(@org_private_repo, forker)

      refute_includes org_admin.associated_repository_ids(include_indirect_forks: true, organization: @org), org_private_repo_fork.id
    end

    test "includes indirect forks when not scoping" do
      org_admin = @org.admins.first
      forker = create(:user, login: "forker")
      @org_team.add_member(forker)
      @org_team.add_repository(@org_private_repo, :pull)

      org_private_repo_fork = fork_repo(@org_private_repo, forker)

      assert_includes org_admin.associated_repository_ids(include_indirect_forks: true), org_private_repo_fork.id
    end

    test "includes only adminship indirects for the specified organization when scoping" do
      foreign_org_private_repo = create :private_repository, owner: @foreign_org, from_example: :simple

      @org.add_admin @user
      @foreign_org.add_admin @user
      @user.reload

      associated_repo_ids_with_indirects_default = @user.associated_repository_ids(organization: @org)
      associated_repo_ids_with_indirects_enabled = @user.associated_repository_ids(organization: @org, including: [:indirect])

      assert_includes associated_repo_ids_with_indirects_default, @org_private_repo.id
      assert_includes associated_repo_ids_with_indirects_enabled, @org_private_repo.id
      refute_includes associated_repo_ids_with_indirects_default, foreign_org_private_repo.id
      refute_includes associated_repo_ids_with_indirects_enabled, foreign_org_private_repo.id
    end

    test "includes only adminship indirects for the specified organization when scoping and repository_ids are provided" do
      foreign_org_private_repo = create :private_repository, owner: @foreign_org, from_example: :simple

      @org.add_admin @user
      @foreign_org.add_admin @user
      @user.reload

      associated_repo_ids_with_indirects_default = @user.associated_repository_ids(organization: @org, repository_ids: [@org_private_repo.id, foreign_org_private_repo.id])
      associated_repo_ids_with_indirects_enabled = @user.associated_repository_ids(organization: @org, including: [:indirect], repository_ids: [@org_private_repo.id, foreign_org_private_repo.id])

      assert_includes associated_repo_ids_with_indirects_default, @org_private_repo.id
      assert_includes associated_repo_ids_with_indirects_enabled, @org_private_repo.id
      refute_includes associated_repo_ids_with_indirects_default, foreign_org_private_repo.id
      refute_includes associated_repo_ids_with_indirects_enabled, foreign_org_private_repo.id
    end

    test  "includes all adminship indirects when not scoping" do
      foreign_org_private_repo = create :private_repository, owner: @foreign_org, from_example: :simple

      @org.add_admin @user
      @foreign_org.add_admin @user
      @user.reload

      associated_repo_ids_with_indirects_default = @user.associated_repository_ids
      associated_repo_ids_with_indirects_enabled = @user.associated_repository_ids(including: [:indirect])

      assert_includes associated_repo_ids_with_indirects_default, @org_private_repo.id
      assert_includes associated_repo_ids_with_indirects_enabled, @org_private_repo.id
      assert_includes associated_repo_ids_with_indirects_default, foreign_org_private_repo.id
      assert_includes associated_repo_ids_with_indirects_enabled, foreign_org_private_repo.id
    end

    test "includes only the specified organization's oopfs when scoping" do
      GitHub.flipper[:bypass_oopfs_query].disable

      foreign_org_admin = @foreign_org.admins.first
      other_org = create(:organization, admin: foreign_org_admin)

      @org.add_admin @user
      @org.add_admin foreign_org_admin

      scoped_org_oopf = fork_repo @org_private_repo, foreign_org_admin, org: @foreign_org
      other_org_oopf = fork_repo @org_private_repo, foreign_org_admin, org: other_org

      associated_repo_ids_with_oopfs_default = @user.associated_repository_ids(organization: @foreign_org)
      associated_repo_ids_with_oopfs_enabled = @user.associated_repository_ids(organization: @foreign_org, include_oopfs: true)

      assert_includes associated_repo_ids_with_oopfs_default, scoped_org_oopf.id
      assert_includes associated_repo_ids_with_oopfs_enabled, scoped_org_oopf.id
      refute_includes associated_repo_ids_with_oopfs_default, other_org_oopf.id
      refute_includes associated_repo_ids_with_oopfs_enabled, other_org_oopf.id

      GitHub.flipper[:bypass_oopfs_query].enable
      @user.reload
      associated_repo_ids_with_oopfs_default = @user.associated_repository_ids(organization: @foreign_org)
      associated_repo_ids_with_oopfs_enabled = @user.associated_repository_ids(organization: @foreign_org, include_oopfs: true)
      refute_includes associated_repo_ids_with_oopfs_default, scoped_org_oopf.id
      refute_includes associated_repo_ids_with_oopfs_enabled, scoped_org_oopf.id
      refute_includes associated_repo_ids_with_oopfs_default, other_org_oopf.id
      refute_includes associated_repo_ids_with_oopfs_enabled, other_org_oopf.id
    end

    test "includes all oopfs when not scoping" do

      @org.add_admin @user
      @foreign_org.add_admin @user
      other_org = create(:organization, admin: @user)

      @user.reload

      scoped_org_oopf = fork_repo @org_private_repo, @user, org: @foreign_org
      other_org_oopf = fork_repo @org_private_repo, @user, org: other_org

      associated_repo_ids_with_oopfs_default = @user.associated_repository_ids
      associated_repo_ids_with_oopfs_enabled = @user.associated_repository_ids(include_oopfs: true)

      assert_includes associated_repo_ids_with_oopfs_default, scoped_org_oopf.id
      assert_includes associated_repo_ids_with_oopfs_enabled, scoped_org_oopf.id
      assert_includes associated_repo_ids_with_oopfs_default, other_org_oopf.id
      assert_includes associated_repo_ids_with_oopfs_enabled, other_org_oopf.id
    end
  end

  context "internal repositories" do
    test "internal repos user isn't otherwise associated with are not included in results" do
      user = create(:user)
      biz_org = create(:enterprise_linked_organization)
      another_biz_org = create(:enterprise_linked_organization, business: biz_org.business)
      create(:internal_repository, owner: biz_org)

      # to truly test internal repos we must not be a member of the org with the internal repo
      another_biz_org.add_member(user)

      assert_empty user.associated_repository_ids(including: [:indirect])
    end

    test "internal repos that the user is directly associated with are included in the results for business members" do
      # this test case asserts implicit access over the repo
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
        # if base role was none, internal repos would only be visible to members with explicit access
        @biz_org.update_default_repository_permission(:read, actor: @biz_org.admins.first)
      end

      assert_equal [], @user.associated_repository_ids(including: [:indirect])

      @biz_org.add_member(@user)
      assert_equal [@internal_repo.id], @user.associated_repository_ids(including: [:indirect])
    end

    test "internal repos that the user is directly associated with are included in the results for business members with team membership" do
      # this test case asserts explicit indirect access over the repo
      assert_equal [], @user.associated_repository_ids(including: [:indirect])

      team = create(:team, organization: @biz_org)
      team.add_repository(@internal_repo, :push)
      team.add_member(@user)

      assert_equal [@internal_repo.id], @user.associated_repository_ids(including: [:indirect])
    end

    test "internal repos that the user is directly associated with are included in the results for business members with direct access" do
      # this test case asserts explicit direct access over the repo
      assert_equal [], @user.associated_repository_ids(including: [:direct])

      @internal_repo.add_member(@user)
      assert_equal [@internal_repo.id], @user.associated_repository_ids(including: [:direct])
    end

    test "internal repos that the user is directly associated with are not included in the results for business members flagged as contractors" do
      # this test case refutes implicit access over the repo
      EnterpriseAttestation.stubs(contractor?: true)

      # perform_enqueued_jobs do
      # TODO: ensuring the contractorship attestation overrides org base roles is out of the scope of the first iteration
      # @biz_org.update_default_repository_permission(:read, actor: @biz_org.admins.first)
      # end

      assert_empty @user.associated_repository_ids(including: [:indirect])

      @biz_org.add_member(@user)
      assert_empty @user.associated_repository_ids(including: [:indirect])
    end

    test "internal repos that the user is directly associated with are included in the results for business members flagged as contractors with team membership" do
      # this test case asserts explicit indirect access over the repo
      EnterpriseAttestation.stubs(contractor?: true)

      assert_equal [], @user.associated_repository_ids(including: [:indirect])

      team = create(:team, organization: @biz_org)
      team.add_repository(@internal_repo, :push)
      team.add_member(@user)

      assert_equal [@internal_repo.id], @user.associated_repository_ids(including: [:indirect])
    end

    test "internal repos that the user is directly associated with are included in the results for business members flagged as contractors with direct access" do
      # this test case asserts explicit direct access over the repo
      EnterpriseAttestation.stubs(contractor?: true)

      assert_equal [], @user.associated_repository_ids(including: [:direct])

      @internal_repo.add_member(@user)
      assert_equal [@internal_repo.id], @user.associated_repository_ids(including: [:direct])
    end
  end

  context "with an explicitly empty including clause" do
    test "returns nothing" do
      assert_equal [], @user.associated_repository_ids(including: [])
    end
  end

  context "with a new user" do
    test "returns nothing" do
      user = User.new
      assert_equal [], user.associated_repository_ids
    end
  end

  context "conditional memoization" do
    test "memoizes the IDs if no options are passed" do
      memoized_ids = @user.associated_repository_ids

      assert_no_queries do
        assert_equal memoized_ids, @user.associated_repository_ids
      end
    end

    test "memoizes the IDs if options are passed but not overridden from the defaults" do
      memoized_ids = @user.associated_repository_ids

      assert_no_queries do
        assert_equal memoized_ids, @user.associated_repository_ids(include_oopfs: true)
      end
    end

    test "doesn't memoize the IDs if options are overridden from the defaults" do
      # Cache the IDs with the default options
      @user.associated_repository_ids

      assert_queries do
        @user.associated_repository_ids(include_oopfs: false)
      end
    end
  end

  def with_mysql_instrumentation_tracking
    GitHub::MysqlInstrumenter.reset_stats

    before = GitHub::MysqlInstrumenter.tracking?
    GitHub::MysqlInstrumenter.track!
    yield
  ensure
    GitHub::MysqlInstrumenter.send(before ? :track! : :untrack!)
  end
end

class UserUnlockedRepositoryIdsTest < GitHub::TestCase
  fixtures do
    @general_user = create(:user)
    @staff_user = create :staff_admin_user
    @unlocker = create :staff_admin_user, stafftools_roles: ["can-unlock-repos-with-owners-permission"]

    @repo = create(:private_repository)
    @unlocked_repo = create(:private_repository)
  end

  test "returns the IDs of repos currently unlocked by this user" do
    admin_unlock_repo(@unlocker, @unlocked_repo)

    assert_includes @unlocker.unlocked_repository_ids, @unlocked_repo.id
    refute_includes @unlocker.unlocked_repository_ids, @repo.id
  end

  test "returns [] for a staff user who can't unlock" do
    assert_equal @staff_user.can_unlock_repos?, GitHub.enterprise?
    assert_empty @staff_user.unlocked_repository_ids
  end

  test "returns [] for a normal user" do
    assert_empty @general_user.unlocked_repository_ids
  end
end
