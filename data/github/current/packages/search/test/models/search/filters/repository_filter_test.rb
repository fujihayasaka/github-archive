# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/api_programmatic_grant_helpers"

class SearchFiltersRepositoryFilterTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers
  include AuthndClientTestHelpers

  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")
    @org     = create(:organization, login: "an-org", admin: @defunkt)
    @verified_user = create(:verified_user)

    @org_repo   = create(:repository, name: "an-repo", owner: @org)
    @owned_repo = create(:repository, name: "facebox", owner: @defunkt)
    @other_repo = create(:repository, name: "grit", owner: @mojombo)

    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
      @biz_org = create(:enterprise_linked_organization)
      @biz_org.update_default_repository_permission(:none, actor: @biz_org.admins.first)
    end
    @biz = @biz_org.business
    @biz_owner = @biz.owners.first
    @biz_member = create(:user)
    @biz_org.add_member(@biz_member)
    @biz_internal_repo = create(:internal_repository, owner: @biz_org)

    # Created but deliberately never used. These exist to ensure they don't appear to members of @biz.
    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
      @biz2_org = create(:enterprise_linked_organization)
      @biz2_org.update_default_repository_permission(:none, actor: @biz_org.admins.first)
    end
    @biz2_member = create(:user)
    @biz2_org.add_member(@biz2_member)
    @biz2_internal_repo = create(:internal_repository, owner: @biz2_org)
  end

  setup do
    @quals = Search::ParsedQuery.qualifiers
    setup_authnd_stub
  end

  teardown do
    remove_authnd_stub
  end

  context "without a current user" do
    test "creates a public-only filter" do
      filter = Search::Filters::RepositoryFilter.new qualifiers: @quals

      assert_equal({ term: { public: true } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
      assert filter.global?
    end

    test "can view others' public repos" do
      qualifiers = [:user, :owner, :org]
      qualifiers.each do |qualifier|
        clear_quals
        @quals[qualifier].must "defunkt"
        filter = Search::Filters::RepositoryFilter.new qualifiers: @quals

        assert_equal({ term: { repo_id: @owned_repo.id } }, filter.must, "expected filter.must to match for qualifier: #{qualifier}")
        assert_nil(filter.must_not, "expected must_not to be nil for qualifier: #{qualifier}")
        assert(filter.valid?, "expected filter to be valid for qualifier: #{qualifier}")
        assert(!filter.global?, "expected filter to not be global for qualifier: #{qualifier}")
      end
    end

    test "cannot view others' private repos" do
      @owned_repo.update!(public: false)
      qualifiers = [:user, :owner, :org]
      qualifiers.each do |qualifier|
        clear_quals
        @quals[qualifier].must "defunkt"
        filter = Search::Filters::RepositoryFilter.new qualifiers: @quals

        assert_equal({ term: { public: true } }, filter.must, "expected filter.must to match for qualifier: #{qualifier}")
        assert_nil(filter.must_not, "expected must_not to be nil for qualifier: #{qualifier}")
        assert(!filter.valid?, "expected filter to be invalid for qualifier: #{qualifier}")
        assert(filter.global?, "expected filter to be global for qualifier: #{qualifier}")
      end
    end

    test "can view public repos" do
      @quals[:repo].must %w[defunkt/facebox mojombo/grit]
      filter = Search::Filters::RepositoryFilter.new qualifiers: @quals

      assert_equal({ terms: { repo_id: [@owned_repo.id, @other_repo.id] } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
      assert !filter.global?
    end

    test "cannot view private repos" do
      @owned_repo.update!(public: false)
      @quals[:repo].must %w[defunkt/facebox mojombo/grit]
      filter = Search::Filters::RepositoryFilter.new qualifiers: @quals

      assert_equal({ term: { repo_id: @other_repo.id } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
      assert !filter.global?

      clear_quals
      @quals[:repo].must "defunkt/facebox"
      filter = Search::Filters::RepositoryFilter.new qualifiers: @quals

      assert_equal({ term: { public: true } }, filter.must)
      assert_nil filter.must_not
      assert !filter.valid?
      assert filter.global?
    end
  end

  context "with a current user" do
    test "exclude public repos for the current user" do
      [@defunkt, oauthed_user(@defunkt)].each do |user|
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)
        assert_equal({ term: { public: true } }, filter.must)
        assert_nil filter.must_not
        assert filter.valid?
        assert filter.global?
      end
    end

    test "include private repos for the current user" do
      @owned_repo.update!(public: false)
      [@defunkt, oauthed_user(@defunkt, ["repo"])].each do |user|
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)
        assert_equal({ bool: { should: [
            { term: { public: true } },
            { term: { repo_id: @owned_repo.id } },
        ] } }, filter.must)
        assert_nil filter.must_not
        assert filter.valid?
        assert filter.global?
      end
    end

    test "exclude private repos for the current user without repo scope" do
      @owned_repo.update!(public: false)
      user = oauthed_user(@defunkt)
      filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

      assert_equal({ term: { public: true } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
      assert filter.global?
    end

    test "include internal repos for business member" do
      [@biz_member, oauthed_user(@biz_member, ["repo"])].each do |user|
        clear_quals
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        if GitHub.single_business_environment?
          assert_equal 2, filter.must[:bool][:should].count
          assert filter.must[:bool][:should][0][:term][:public]
          assert_same_elements [@biz_internal_repo.id, @biz2_internal_repo.id], filter.must[:bool][:should][1][:terms][:repo_id]
        else
          assert_equal({ bool: { should: [
            { term: { public: true } },
            { term: { repo_id: @biz_internal_repo.id } }
          ] } }, filter.must)
        end
        assert_nil filter.must_not
        assert filter.valid?
        assert filter.global?
      end
    end

    test "include internal repos for business owner" do
      [@biz_owner, oauthed_user(@biz_owner, ["repo"])].each do |user|
        clear_quals
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        if GitHub.single_business_environment?
          assert_equal 2, filter.must[:bool][:should].count
          assert filter.must[:bool][:should][0][:term][:public]
          assert_same_elements [@biz_internal_repo.id, @biz2_internal_repo.id], filter.must[:bool][:should][1][:terms][:repo_id]
        else
          assert_equal({ bool: { should: [
            { term: { public: true } },
            { term: { repo_id: @biz_internal_repo.id } }
          ] } }, filter.must)
        end
        assert_nil filter.must_not
        assert filter.valid?
        assert filter.global?
      end
    end

    test "can view others public repos" do
      @quals[:user].must "mojombo"

      [@defunkt, oauthed_user(@defunkt)].each do |user|
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        assert_equal({ term: { repo_id: @other_repo.id } }, filter.must)
        assert_nil filter.must_not
        assert filter.valid?
        assert !filter.global?
      end
    end

    test "cannot view others private repos" do
      @other_repo.update!(public: false)
      @quals[:user].must "mojombo"

      [@defunkt, oauthed_user(@defunkt, ["repo"])].each do |user|
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        assert_equal({ term: { public: true } }, filter.must)
        assert_nil filter.must_not
        assert !filter.valid?
        assert filter.global?
      end
    end

    test "can view own repos" do
      @quals[:user].must "defunkt"

      [@defunkt, oauthed_user(@defunkt)].each do |user|
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        assert_equal({ term: { repo_id: @owned_repo.id } }, filter.must)
        assert_nil filter.must_not
        assert filter.valid?
        assert !filter.global?
      end
    end

    test "can view own private repos" do
      @owned_repo.update!(public: false)
      @quals[:user].must "defunkt"

      [@defunkt, oauthed_user(@defunkt, ["repo"])].each do |user|
        act_as(user)
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        assert_equal({ term: { repo_id: @owned_repo.id } }, filter.must)
        assert_nil filter.must_not
        assert filter.valid?
        assert !filter.global?
      end
    end

    test "can view own repos with repo scope" do
      @owned_repo.update!(public: false)
      @quals[:repo].must @owned_repo.nwo

      optimized_queries = nil
      long_queries = nil

      [@defunkt, oauthed_user(@defunkt, ["repo"])].each do |user|
        filter, queries = log_queries do
          Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)
        end

        assert queries.size > 6
        assert_equal({ term: { repo_id: @owned_repo.id } }, filter.must)
        assert_nil filter.must_not
        assert filter.valid?
        assert !filter.global?
      end
    end

    test "viewing own repos excludes org repos" do
      org = create(:organization, admin: @defunkt, plan: "bronze")
      org_repo = create(:private_repository, owner: org)
      assert org.adminable_by?(@defunkt)

      @quals[:user].must "defunkt"
      [@defunkt, oauthed_user(@defunkt, ["repo"])].each do |user|
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)
        assert_equal({ term: { repo_id: @owned_repo.id } }, filter.must)
      end
    end

    test "cannot view own private repos without repo scope" do
      @owned_repo.update!(public: false)
      @quals[:user].must "defunkt"
      user = oauthed_user(@defunkt, ["gist"])
      filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

      refute filter.repo_id
      assert_equal({ term: { public: true } }, filter.must)
      assert_nil filter.must_not
      assert !filter.valid?
      assert filter.global?
    end

    test "can view public repos we do not own" do
      @quals[:repo].must "mojombo/grit"

      [@verified_user, oauthed_user(@verified_user, ["repo"])].each do |user|
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        assert_equal({ term: { repo_id: @other_repo.id } }, filter.must)
        assert_nil filter.must_not
        assert filter.valid?
        assert !filter.global?
      end
    end

    test "cannot view private repos we do not own" do
      @other_repo.update!(public: false)

      [@verified_user, oauthed_user(@verified_user, ["repo"])].each do |user|
        clear_quals
        @quals[:repo].must %w[defunkt/facebox mojombo/grit]
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        assert_equal({ term: { repo_id: @owned_repo.id } }, filter.must)
        assert_nil filter.must_not
        assert filter.valid?
        assert !filter.global?

        clear_quals
        @quals[:repo].must "defunkt/facebox"
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        assert_equal({ term: { repo_id: @owned_repo.id } }, filter.must)
        assert_nil filter.must_not
        assert filter.valid?
        assert !filter.global?

        clear_quals
        @quals[:repo].must "mojombo/grit"
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        assert_equal({ term: { public: true } }, filter.must)
        assert_nil filter.must_not
        assert !filter.valid?
        assert filter.global?
      end
    end

    test "provides the set of accessible private repositories" do
      @other_repo.update!(public: false)
      @quals[:repo].must %w[defunkt/facebox mojombo/grit]
      filter = Search::Filters::RepositoryFilter.new(current_user: @defunkt, qualifiers: @quals)

      set = Set.new [@owned_repo.id]
      assert_equal set, filter.accessible_repository_ids
      assert filter.accessible_repository?(@owned_repo)
    end

    test "truncates the list of private repos when it is larger than MAX_REPO_FILTER_SIZE" do
      @org.allow_private_repository_forking(actor: @defunkt)
      @org.add_admin(@mojombo)

      private_repo_1 = create(:private_repository, owner: @org, updated_at: 10.days.ago, pushed_at: 10.days.ago)
      private_repo_2 = create(:private_repository, owner: @org, updated_at: 100.days.ago, pushed_at: 9.days.ago)
      private_repo_3 = create(:private_repository, owner: @org, updated_at: 9.days.ago, pushed_at: 100.days.ago)

      private_repo_fork_1 = create(:fork_repository, forker: @mojombo, fork_repo: private_repo_1)
      private_repo_fork_1.update!(updated_at: 8.days.ago, pushed_at: nil)
      private_repo_fork_2 = create(:fork_repository, forker: @mojombo, fork_repo: private_repo_2)
      private_repo_fork_1.update!(updated_at: 7.days.ago, pushed_at: nil)

      Search::Filters::RepositoryFilter.stub_const(:MAX_REPO_FILTER_SIZE, 4) do
        filter = Search::Filters::RepositoryFilter.new(current_user: @defunkt, qualifiers: @quals)

        # We expect the repos to be in order of sources, then max(pushed_at, updated_at), then forks, then max(pushed_at, updated_at)
        expected_repos = [
          private_repo_3,
          private_repo_2,
          private_repo_1,
          private_repo_fork_2,
        ]
        assert_equal expected_repos.map(&:id).to_set, filter.accessible_repository_ids
        expected_repos.each do |repo|
          assert filter.accessible_repository?(repo)
        end
      end
    end

    test "does not truncate when the number of repositories is smaller than MAX_REPO_FILTER_SIZE" do
      @org.allow_private_repository_forking(actor: @defunkt)
      @org.add_admin(@mojombo)

      private_repo_1 = create(:private_repository, owner: @org, updated_at: 10.days.ago)
      private_repo_2 = create(:private_repository, owner: @org, updated_at: 9.days.ago)
      private_repo_fork, rest = private_repo_1.fork(forker: @mojombo)

      assert private_repo_fork, rest.inspect

      filter = Search::Filters::RepositoryFilter.new(current_user: @defunkt, qualifiers: @quals)

      # We expect the repos to be truncated in order of sources, then max(pushed_at, updated_at), then forks, then max(pushed_at, updated_at)
      # However, the #accessible_repository_ids returns a set so I guess we can't check that order.
      expected_repos = [
        private_repo_2,
        private_repo_1,
        private_repo_fork,
      ]
      assert_equal expected_repos.map(&:id).to_set, filter.accessible_repository_ids
      expected_repos.each do |repo|
        assert filter.accessible_repository?(repo)
      end
    end

    test "only considers up to MAX_CONSIDERED_REPOSITORY_IDS repositories" do
      create(:private_repository, owner: @org)

      Search::Filters::RepositoryFilter.stub_const(:MAX_CONSIDERED_REPOSITORY_IDS, 0) do
        filter = Search::Filters::RepositoryFilter.new(current_user: @defunkt, qualifiers: @quals)
        assert_empty filter.accessible_repository_ids
      end
    end

    test "applies org OAuth app policy to accessible repositories" do
      oauth_user = oauthed_user(@defunkt, %w(repo))

      @org_repo.update!(public: false)

      @quals[:org].must "an-org"

      filter = Search::Filters::RepositoryFilter.new(current_user: oauth_user, qualifiers: @quals)
      assert_includes filter.accessible_repository_ids, @org_repo.id
      assert filter.accessible_repository?(@org_repo)

      @org.enable_oauth_application_restrictions
      filter = Search::Filters::RepositoryFilter.new(current_user: oauth_user, qualifiers: @quals)
      refute_includes filter.accessible_repository_ids, @org_repo.id
      refute filter.accessible_repository?(@org_repo)
    end if GitHub.oauth_application_policies_enabled?

    test "excluded repos are removed before truncation" do
      # There was a bug that caused the repository_filter id list to be truncated more than it should be
      # Effectively the repo list was being truncated BEFORE the excluded repos were being removed from the list
      # Details here https://github.com/github/code-search/issues/2135
      #
      # I have to create these in a particular order so that the repos that should not be truncated are returned last
      # in the call to `current_user.associated_repository_ids`
      persondude = create(:user, login: "persondude", email: "person@dude.com")
      some_org = create(:organization, login: "some-org", admin: persondude)

      some_repo = create(:private_repository, name: "some_repo", owner: some_org)
      dude_repo1 = create(:private_repository, name: "dude_repo1", owner: persondude)
      dude_repo2 = create(:private_repository, name: "dude_repo2", owner: persondude)

      cap_filter = mock
      cap_filter.stubs(:unauthorized_resources).returns([some_org])
      cap_filter.stubs(:authorized_resource_ids).returns([])
      Search::Filters::RepositoryFilter.any_instance.stubs(:cap_filter).returns(cap_filter)

      @quals[:repo].must_not ["persondude/dude_repo1"]

      Search::Filters::RepositoryFilter.stub_const(:MAX_CONSIDERED_REPOSITORY_IDS, 2) do
        act_as(persondude)
        filter = Search::Filters::RepositoryFilter.new(current_user: persondude, qualifiers: @quals)
        assert_equal Set.new([dude_repo2.id]), filter.accessible_repository_ids
        refute filter.accessible_repository?(dude_repo1)
        assert filter.accessible_repository?(dude_repo2)
      end

    end

    test "limits the repo_id for a user when limit_to_repo_ids is provided" do
      repo1 = create(:repository, owner: @mojombo)
      repo2 = create(:private_repository, owner: @mojombo)
      repo3 = create(:repository, owner: @mojombo)
      @quals[:user].clear.must @mojombo.display_login

      act_as(@mojombo)
      filter = Search::Filters::RepositoryFilter.new(
        current_user: @mojombo, qualifiers: @quals, limit_to_repo_ids: [repo1.id, repo2.id]
      )

      assert_equal({ terms: { repo_id: [repo1.id, repo2.id] } }, filter.must)
    end

    test "limits the repo_id for an org when limit_to_repo_ids is provided" do
      repo1 = create(:repository, owner: @biz_org)
      repo2 = create(:private_repository, owner: @biz_org)
      @quals[:org].clear.must @biz_org.display_login

      filter = Search::Filters::RepositoryFilter.new(
        current_user: @biz_org.admins.first, qualifiers: @quals, limit_to_repo_ids: [repo1.id, @biz_internal_repo.id]
      )

      assert_equal({ terms: { repo_id: [repo1.id, @biz_internal_repo.id] } }, filter.must)
    end

    context "GitHub Apps" do
      context "server-to-server" do
        test "can view a private repo, when the specified resource is accessible" do
          installation = make_integration_installation(repository: @org_repo, permissions: { "issues" => :read })
          bot = installation.bot

          @org_repo.update!(public: false)
          assert_predicate @org_repo, :private?, "expected #{@org_repo} to be private"

          @quals[:repo].must [@org_repo.nwo]
          filter = Search::Filters::RepositoryFilter.new(current_user: bot, qualifiers: @quals, resource: "issues")

          assert_equal({ term: { repo_id: @org_repo.id } }, filter.must)
          assert_nil filter.must_not
          assert_predicate filter, :valid?, "expected the filter to be valid"
          refute_predicate filter, :global?, "expected the filter to not be global"
        end

        test "provides the set of private repositories, where the resource is accessible" do
          installation = make_integration_installation(repository: @org_repo, permissions: { "issues" => :read })
          bot = installation.bot

          @org_repo.update!(public: false)
          assert_predicate @org_repo, :private?

          @quals[:repo].must %w[an-org/an-repo]
          filter = Search::Filters::RepositoryFilter.new(current_user: bot, qualifiers: @quals, resource: "issues")

          set = Set.new [@org_repo.id]
          assert_equal set, filter.accessible_repository_ids
          assert filter.accessible_repository?(@org_repo)
        end

        test "includes private repositories where the resource is accessible and user filter is provided" do
          private_repo = create(:private_repository, owner: @org)

          installation = make_integration_installation(repository: private_repo, permissions: { "contents" => :read })
          bot = installation.bot

          @quals[:user].must %w[an-org]
          filter = Search::Filters::RepositoryFilter.new(current_user: bot, qualifiers: @quals)

          set = Set.new [@org_repo.id, private_repo.id]
          assert_equal set, filter.accessible_repository_ids
          assert filter.accessible_repository?(@org_repo)
          assert filter.accessible_repository?(private_repo)
        end

        test "excludes private repositories where the resource is inaccessible and user filter is provided" do
          private_repo = create(:private_repository, owner: @org)

          installation = make_integration_installation(repository: private_repo)
          bot = installation.bot

          @quals[:user].must %w[an-org]
          filter = Search::Filters::RepositoryFilter.new(current_user: bot, qualifiers: @quals)

          set = Set.new [@org_repo.id]
          assert_equal set, filter.accessible_repository_ids
          assert filter.accessible_repository?(@org_repo)
        end
      end

      context "user-to-server" do
        test "includes private repositories for the current_user where the resource is accessible" do
          private_repo = create(:private_repository, owner: @defunkt)
          installation = make_integration_installation(target: @defunkt, permissions: { "contents" => :read })

          grant = installation.integration.grant(@defunkt)
          @defunkt.oauth_access = grant

          filter = Search::Filters::RepositoryFilter.new(current_user: @defunkt, qualifiers: @quals)

          set = Set.new [private_repo.id]
          assert_equal set, filter.accessible_repository_ids
          assert filter.accessible_repository?(private_repo)
        end

        test "includes private repositories for an organization the current_user has access to" do
          private_repo = create(:private_repository, owner: @org)
          installation = make_integration_installation(target: @org, permissions: { "contents" => :read })

          assert private_repo.readable_by?(@defunkt), "expected #{@defunkt} to be able to see #{private_repo}"
          assert private_repo.resources.contents.readable_by?(installation), \
            "expected #{installation} to be able to read #{private_repo}'s contents"

          grant = installation.integration.grant(@defunkt)
          @defunkt.oauth_access = grant

          filter = Search::Filters::RepositoryFilter.new(current_user: @defunkt, qualifiers: @quals)

          set = Set.new [private_repo.id]
          assert_equal set, filter.accessible_repository_ids
          assert filter.accessible_repository?(private_repo)
        end

        test "excludes private repositories for the current_user where the resource is inaccessible" do
          private_repo = create(:private_repository, owner: @defunkt)
          integration = create(:integration)

          grant = integration.grant(@defunkt)
          @defunkt.oauth_access = grant

          filter = Search::Filters::RepositoryFilter.new(current_user: @defunkt, qualifiers: @quals)

          assert_empty filter.accessible_repository_ids
          refute filter.accessible_repository?(private_repo)
        end

        test "excludes private repositories for an organization when the installation doesn't have access" do
          accessible_private_repo   = create(:private_repository, owner: @org)
          inaccessible_private_repo = create(:private_repository, owner: @org)

          installation = make_integration_installation(repository: accessible_private_repo, permissions: { "contents" => :read })

          assert accessible_private_repo.readable_by?(@defunkt),   "expected #{@defunkt} to be able to see #{accessible_private_repo}"
          assert inaccessible_private_repo.readable_by?(@defunkt), "expected #{@defunkt} to be able to see #{inaccessible_private_repo}"

          assert accessible_private_repo.resources.contents.readable_by?(installation), \
            "expected #{installation} to be able to read #{accessible_private_repo}'s contents"

          refute inaccessible_private_repo.resources.contents.readable_by?(installation), \
            "expected #{installation} to not be able to read #{inaccessible_private_repo}'s contents"

          grant = installation.integration.grant(@defunkt)
          @defunkt.oauth_access = grant

          filter = Search::Filters::RepositoryFilter.new(current_user: @defunkt, qualifiers: @quals)

          set = Set.new [accessible_private_repo.id]
          assert_equal set, filter.accessible_repository_ids
          assert filter.accessible_repository?(accessible_private_repo)
          refute filter.accessible_repository?(inaccessible_private_repo)
        end

        test "includes private repositories where the resource is accessible and the repo filter is provided" do
          private_repo = create(:private_repository, owner: @defunkt)
          installation = make_integration_installation(target: @defunkt, permissions: { "contents" => :read })

          grant = installation.integration.grant(@defunkt)
          @defunkt.oauth_access = grant

          @quals[:repo].must [private_repo.nwo]
          filter = Search::Filters::RepositoryFilter.new(current_user: @defunkt, qualifiers: @quals)

          set = Set.new [private_repo.id]
          assert_equal set, filter.accessible_repository_ids
          assert filter.accessible_repository?(private_repo)
        end

        test "excludes private repositories where the resource is inaccessible and the repo filter is provided" do
          private_repo = create(:private_repository, owner: @defunkt)
          installation = make_integration_installation(target: @defunkt)

          grant = installation.integration.grant(@defunkt)
          @defunkt.oauth_access = grant

          @quals[:repo].must [private_repo.nwo]
          filter = Search::Filters::RepositoryFilter.new(current_user: @defunkt, qualifiers: @quals)

          assert_empty filter.accessible_repository_ids
          refute filter.accessible_repository?(private_repo)
        end

        test "includes private repositories where the resource is accessible and user filter is provided" do
          private_repo = create(:private_repository, owner: @org)
          installation = make_integration_installation(target: @org, permissions: { "contents" => :read })

          grant = installation.integration.grant(@defunkt)
          @defunkt.oauth_access = grant

          @quals[:user].must %w[an-org]
          filter = Search::Filters::RepositoryFilter.new(current_user: @defunkt, qualifiers: @quals)

          set = Set.new [@org_repo.id, private_repo.id]
          assert_equal set, filter.accessible_repository_ids
          assert filter.accessible_repository?(@org_repo)
          assert filter.accessible_repository?(private_repo)
        end

        test "excludes private repositories where the resource is inaccessible and user filter is provided" do
          private_repo = create(:private_repository, owner: @org)

          integration = create(:integration, default_permissions: { "metadata" => :read })

          grant = integration.grant(@defunkt)
          @defunkt.oauth_access = grant

          @quals[:user].must %w[an-org]
          filter = Search::Filters::RepositoryFilter.new(current_user: @defunkt, qualifiers: @quals)

          set = Set.new [@org_repo.id]
          assert_equal set, filter.accessible_repository_ids
          assert filter.accessible_repository?(@org_repo)
          refute filter.accessible_repository?(private_repo)
        end
      end
    end

    context "with a programmatic actor" do
      test "includes private repositories for the current_user where the resource is accessible" do
        private_repo = create(:private_repository, owner: @defunkt)
        pat = create(:user_programmatic_access, owner: @defunkt)
        make_programmatic_access_grant(
          access: pat,
          permissions: { "contents" => :read },
          repositories: [private_repo]
        )

        @defunkt.programmatic_access = pat

        filter = Search::Filters::RepositoryFilter.new(
          current_user: @defunkt,
          qualifiers: @quals
        )

        set = Set.new [private_repo.id]
        assert_equal set, filter.accessible_repository_ids
        assert filter.accessible_repository?(private_repo)
      end

      test "excludes private repositories where the resource is inaccessible and the repo qualf is provided" do
        private_repo = create(:private_repository, owner: @defunkt)
        pat = create(:user_programmatic_access, owner: @defunkt)

        @defunkt.programmatic_access = pat

        @quals[:repo].must [private_repo.nwo]
        filter = Search::Filters::RepositoryFilter.new(
          current_user: @defunkt,
          qualifiers: @quals
        )

        assert_empty filter.accessible_repository_ids
        refute filter.accessible_repository?(private_repo)
      end

      test "repo qualifier restricts to granted private repos" do
        private_repo = create(:private_repository, owner: @defunkt)
        other_private_repo = create(:private_repository, owner: @defunkt)

        pat = create(:user_programmatic_access, owner: @defunkt)
        make_programmatic_access_grant(
          access: pat,
          permissions: { "contents" => :read },
          repositories: [private_repo, other_private_repo]
        )

        @defunkt.programmatic_access = pat

        @quals[:repo].must [private_repo.nwo]
        filter = Search::Filters::RepositoryFilter.new(
          current_user: @defunkt,
          qualifiers: @quals
        )

        set = Set.new [private_repo.id]
        assert_equal set, filter.accessible_repository_ids
        assert filter.accessible_repository?(private_repo)
        refute filter.accessible_repository?(other_private_repo)
      end

      test "excludes private repositories where the resource is inaccessible and user filter is provided" do
        private_repo = create(:private_repository, owner: @org)
        pat = create(:user_programmatic_access, owner: @defunkt)

        @defunkt.programmatic_access = pat

        @quals[:user].must %w[an-org]
        filter = Search::Filters::RepositoryFilter.new(
          current_user: @defunkt,
          qualifiers: @quals
        )

        set = Set.new [@org_repo.id]
        assert_equal set, filter.accessible_repository_ids
        assert filter.accessible_repository?(@org_repo)
        refute filter.accessible_repository?(private_repo)
      end
    end

    context "include internal repository when user is member of enterprise org" do
      test "include internal repo for business members who inherited base role `No permission`" do
        clear_quals

        session = create(:user_session, user: @biz2_member)

        qualifiers = Search::ParsedQuery.qualifiers
        qualifiers[:repo].must(@biz2_internal_repo.nwo)

        filter = Search::Filters::RepositoryFilter.new(current_user: @biz2_member, qualifiers: qualifiers, resource: "issues", user_session: session)

        assert filter.must, { term: { repo_id: @biz2_internal_repo.id } }
        assert_nil filter.must_not
        assert filter.valid?
      end

      test "does not include private repos for business members who inherited base role `No permission`" do
        clear_quals

        session = create(:user_session, user: @biz2_member)
        biz2_private_repo = create(:private_repository, owner: @biz2_org)

        qualifiers = Search::ParsedQuery.qualifiers
        qualifiers[:repo].must(biz2_private_repo.nwo)

        filter = Search::Filters::RepositoryFilter.new(current_user: @biz2_member, qualifiers: qualifiers, resource: "issues", user_session: session)

        assert filter.must, { term: { repo_id: biz2_private_repo.id } }
        assert_nil filter.must_not
        refute filter.valid?
      end

      test "non-business members cannot see internal business repos" do
        clear_quals

        non_emu_user = create(:verified_user, skip_enterprise_managed_user: true)

        session = create(:user_session, user: non_emu_user)

        qualifiers = Search::ParsedQuery.qualifiers
        qualifiers[:repo].must(@biz2_internal_repo.nwo)

        filter = Search::Filters::RepositoryFilter.new(current_user: non_emu_user, qualifiers: qualifiers, resource: "issues", user_session: session)

        assert filter.must, { term: { repo_id: @biz2_internal_repo.id } }
        assert_nil filter.must_not
        refute filter.valid?
      end
    end
  end

  context "when negated" do
    test "negates a users public repos" do
      @quals[:user].must_not "defunkt"
      filter = Search::Filters::RepositoryFilter.new(qualifiers: @quals)

      assert_equal({ term: { public: true } }, filter.must)
      assert_equal({ term: { repo_id: @owned_repo.id } }, filter.must_not)
      assert filter.valid?
      assert filter.global?
    end

    test "does not negate a users private repos" do
      @owned_repo.update!(public: false)
      @quals[:user].must_not "defunkt"
      filter = Search::Filters::RepositoryFilter.new(qualifiers: @quals)

      assert_equal({ term: { public: true } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
      assert filter.global?
    end

    test "a user can negate themselves" do
      @quals[:user].must_not "defunkt"

      [@defunkt, oauthed_user(@defunkt, ["repo"])].each do |user|
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        assert_equal({ term: { public: true } }, filter.must)
        assert_equal({ term: { repo_id: @owned_repo.id } }, filter.must_not)
        assert filter.valid?
        assert filter.global?
      end
    end

    test "a user can negate their own private repos" do
      @owned_repo.update!(public: false)

      [@defunkt, oauthed_user(@defunkt, ["repo"])].each do |user|
        clear_quals
        @quals[:org].must_not "defunkt"
        act_as(user)
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        assert_equal({ term: { public: true } }, filter.must)
        assert_equal({ term: { repo_id: @owned_repo.id } }, filter.must_not)
        assert filter.valid?
        assert filter.global?

        clear_quals
        @quals[:repo].must_not "defunkt/facebox"
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        assert_equal({ term: { public: true } }, filter.must)
        assert_equal({ term: { repo_id: @owned_repo.id } }, filter.must_not)
        assert filter.valid?
        assert filter.global?
      end
    end

    test "negates a specific repo" do
      @quals[:repo].must_not "mojombo/grit"
      filter = Search::Filters::RepositoryFilter.new(qualifiers: @quals)

      assert_equal({ term: { public: true } }, filter.must)
      assert_equal({ term: { repo_id: @other_repo.id } }, filter.must_not)
      assert filter.valid?
      assert filter.global?

      [@defunkt, oauthed_user(@defunkt, ["repo"])].each do |user|
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        assert_equal({ term: { public: true } }, filter.must)
        assert_equal({ term: { repo_id: @other_repo.id } }, filter.must_not)
        assert filter.valid?
        assert filter.global?
      end
    end

    test "does not negate private repos" do
      @other_repo.update!(public: false)
      @quals[:repo].must_not "mojombo/grit"
      filter = Search::Filters::RepositoryFilter.new(qualifiers: @quals)

      assert_equal({ term: { public: true } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
      assert filter.global?

      [@defunkt, oauthed_user(@defunkt, ["repo"])].each do |user|
        filter = Search::Filters::RepositoryFilter.new(current_user: user, qualifiers: @quals)

        assert_equal({ term: { public: true } }, filter.must)
        assert_nil filter.must_not
        assert filter.valid?
        assert filter.global?
      end
    end
  end

  context "degenerate queries" do
    test "handles including and excluding the same user" do
      @quals[:user].must "mojombo"
      @quals[:user].must_not "mojombo"
      filter = Search::Filters::RepositoryFilter.new(qualifiers: @quals)

      assert filter.valid?,  "filter should be valid"
      assert filter.global?, "filter should include the public restriction"

      assert_equal({ term: { public: true } }, filter.must)
      assert_equal({ term: { repo_id: @other_repo.id } }, filter.must_not)
    end

    test "handles including and excluding the same repo" do
      @quals[:repo].must "mojombo/grit"
      @quals[:repo].must_not "mojombo/grit"
      filter = Search::Filters::RepositoryFilter.new(qualifiers: @quals)

      assert filter.valid?,  "filter should be valid"
      assert filter.global?, "filter should include the public restriction"

      assert_equal({ term: { public: true } }, filter.must)
      assert_equal({ term: { repo_id: @other_repo.id } }, filter.must_not)
    end

    test "handles a mix of includes and excludes" do
      @quals[:repo].must "mojombo/grit"
      @quals[:user].must_not "mojombo"
      filter = Search::Filters::RepositoryFilter.new(qualifiers: @quals)

      assert filter.valid?,  "filter should be valid"
      assert filter.global?, "filter should include the public restriction"

      assert_equal({ term: { public: true } }, filter.must)
      assert_equal({ term: { repo_id: @other_repo.id } }, filter.must_not)
    end
  end

  context "when a repo ID is provided" do
    test "ignores :repo and :user qualifiers" do
      @quals[:repo].must "defunkt/facebox"
      @quals[:user].must_not "mojombo"
      filter = Search::Filters::RepositoryFilter.new(qualifiers: @quals, repo_id: 1234)

      assert_equal({ term: { repo_id: 1234 } }, filter.must)
      assert_nil filter.must_not
      assert filter.valid?
      assert !filter.global?
    end
  end

  context "when a resource is provided" do
    test "removes :resource option, if it is not an allowed name" do
      @quals[:repo].must "defunkt/facebox"
      filter = Search::Filters::RepositoryFilter.new(qualifiers: @quals, resource: "not-a-real-resource")

      refute_includes filter.options.keys, :resource
      assert filter.valid?
    end

    test "persists :resource option, if it is an allowed name" do
      @quals[:repo].must "defunkt/facebox"
      filter = Search::Filters::RepositoryFilter.new(qualifiers: @quals, resource: "issues")

      assert_equal "issues", filter.options[:resource]
      assert filter.valid?
    end
  end

  def oauthed_user(user = create(:user), scopes = [])
    User.with_oauth_hashed_token(make_oauth(user, scopes).hashed_token)
  end

  def clear_quals
    @quals[:repo].clear
    @quals[:user].clear
  end
end

class RepositoryFilterActiveExternalIdentityEnforcementTest < GitHub::TestCase
  skip_unless :external_identity_session_enforcement_enabled?

  fixtures do
    @saml_session  = create :external_identity_session
    @user_session  = @saml_session.user_session
    @saml_identity = @saml_session.external_identity
    @saml_org      = @saml_identity.target
    @saml_user     = @saml_identity.user
    @saml_repo     = create(:private_repository, owner: @saml_org)
  end

  setup do
    @quals = Search::ParsedQuery.qualifiers
  end

  test "excludes SAML-protected private organization repositories without a SAML session" do
    @saml_session.destroy
    act_as(@saml_user)
    filter = Search::Filters::RepositoryFilter.new current_user: @saml_user, user_session: @user_session, qualifiers: @quals

    assert_equal({ term: { public: true } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "includes SAML-protected private organization repositories with a SAML session" do
    filter = Search::Filters::RepositoryFilter.new current_user: @saml_user, user_session: @user_session, qualifiers: @quals

    assert_equal({ bool: { should: [{ term: { public: true } }, { term: { repo_id: @saml_repo.id } }] } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "includes SAML-protected private organization repositories when accessed by a server-to-server GitHub Apps integration" do
    @saml_org.saml_provider.enforce!
    installation = make_integration_installation(target: @saml_org, permissions: { "contents" => :read })
    bot = installation.bot
    filter = Search::Filters::RepositoryFilter.new current_user: bot, qualifiers: @quals

    assert_equal({ bool: { should: [{ term: { public: true } }, { term: { repo_id: @saml_repo.id } }] } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "does not include SAML-protected private organization repositories when accessed by a user-to-server GitHub Apps integration" do
    @saml_org.saml_provider.enforce!
    installation = make_integration_installation(target: @saml_org, permissions: { "contents" => :read })
    grant = installation.integration.grant(@saml_user)
    @saml_user.oauth_access = grant
    act_as(@saml_user)
    filter = Search::Filters::RepositoryFilter.new current_user: @saml_user, qualifiers: @quals

    assert_equal({ term: { public: true } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "drop-in CAP filter: dangling SAML provider on Free org returns correct results" do
    user = create(:user)
    user_session = create(:user_session, user: user)

    org = create(:organization, billing_type: "invoice", plan: "business_plus")
    org.add_member(user)

    saml_provider = create(:organization_saml_provider, organization: org)
    saml_provider.enforce!
    assert_equal saml_provider, org.saml_provider
    assert_predicate org, :saml_sso_enabled?

    # force the downgrade to a non SAML plan without removing the SAML provider
    assert_predicate org.plan, :business_plus?
    result = Billing::ChangeSubscription.perform(org, plan: "free", actor: create(:staff_admin_user))
    assert result.success?
    assert_predicate org.reload.plan, :free?

    # the provider is still present but SSO is disabled due to Free plan not supporting it
    assert_equal saml_provider, org.saml_provider
    refute_predicate org, :saml_sso_enabled?

    # we need an repo in the target org so that #protected_org_names is called
    saml_repo = create(:private_repository, owner: org)

    filter = Search::Filters::RepositoryFilter.new current_user: user, user_session: user_session, qualifiers: @quals

    assert_equal({ bool: { should: [{ term: { public: true } }, { term: { repo_id: saml_repo.id } }] } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "drop-in CAP filter: combination of authorized and unauthorized orgs returns correct results" do
    org = create(:organization)
    org.add_member(@saml_user)
    @saml_org.add_member(@saml_user)

    # we need an repo in the target org so that #protected_org_names is called
    repo = create(:private_repository, owner: org)

    @saml_session.destroy
    act_as(@saml_user)
    filter = Search::Filters::RepositoryFilter.new current_user: @saml_user, user_session: @user_session, qualifiers: @quals

    # response does not contain the @saml_repo
    assert_equal({ bool: { should: [{ term: { public: true } }, { term: { repo_id: repo.id } }] } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end
end

class RepositoryFilterBusinessExternalIdentityEnforcementTest < GitHub::TestCase
  skip_unless :external_identity_session_enforcement_enabled?

  fixtures do
    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
      @org = create :enterprise_linked_organization
      @biz = @org.business
      @org.update_default_repository_permission(:none, actor: @org.admins.first)

      @org2 = create :enterprise_linked_organization, business: @biz
      @org2.update_default_repository_permission(:none, actor: @org2.admins.first)
    end

    @org_member = create :user
    @org.add_member(@org_member)
    @org_repo = create :internal_repository, owner: @org

    @org2_repo = create :internal_repository, owner: @org2
  end

  test "internal repos under SAML-enabled business are excluded without valid session" do
    biz_provider = create :business_saml_provider, business: @biz
    org_member_identity = create :external_identity, user: @org_member, provider: biz_provider

    filter = Search::Filters::RepositoryFilter.new current_user: @org_member,
      qualifiers: Search::ParsedQuery.qualifiers

    assert_equal({ term: { public: true } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "internal repos under SAML-enabled business are included with valid session" do
    biz_provider = create :business_saml_provider, business: @biz
    org_member_identity = create :external_identity, user: @org_member, provider: biz_provider

    Timecop.freeze do
      session = create :user_session, user: @org_member
      create :external_identity_session, user_session: session, external_identity: org_member_identity

      filter = Search::Filters::RepositoryFilter.new current_user: @org_member,
        qualifiers: Search::ParsedQuery.qualifiers,
        user_session: session

      assert_equal 2, filter.must[:bool][:should].count
      assert filter.must[:bool][:should][0][:term][:public]
      assert_same_elements [@org_repo.id, @org2_repo.id], filter.must[:bool][:should][1][:terms][:repo_id]

      assert_nil filter.must_not
      assert_nil filter.should
      assert filter.valid?
      assert filter.global?
    end
  end

  test "internal repos visible only from orgs with valid sessions" do
    org_provider = create :organization_saml_provider, organization: @org
    org_member_identity = create :external_identity, user: @org_member, provider: org_provider
    @org2.add_member @org_member
    org2_provider = create :organization_saml_provider, organization: @org2
    org2_member_identity = create :external_identity, user: @org_member, provider: org2_provider

    filter = Search::Filters::RepositoryFilter.new current_user: @org_member,
      qualifiers: Search::ParsedQuery.qualifiers
    assert_equal({ term: { public: true } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?

    Timecop.freeze do
      session = create :user_session, user: @org_member
      create :external_identity_session, user_session: session, external_identity: org_member_identity

      filter = Search::Filters::RepositoryFilter.new current_user: @org_member,
        user_session: session, qualifiers: Search::ParsedQuery.qualifiers
      assert_equal({ bool: { should: [{ term: { public: true } }, { term: { repo_id: @org_repo.id } }] } }, filter.must)
      assert_nil filter.must_not
      assert_nil filter.should
      assert filter.valid?
      assert filter.global?
    end

    Timecop.freeze do
      session = create :user_session, user: @org_member
      create :external_identity_session, user_session: session, external_identity: org2_member_identity

      filter = Search::Filters::RepositoryFilter.new current_user: @org_member,
        user_session: session, qualifiers: Search::ParsedQuery.qualifiers
      assert_equal({ bool: { should: [{ term: { public: true } }, { term: { repo_id: @org2_repo.id } }] } }, filter.must)
      assert_nil filter.must_not
      assert_nil filter.should
      assert filter.valid?
      assert filter.global?
    end

    Timecop.freeze do
      session = create :user_session, user: @org_member
      create :external_identity_session, user_session: session, external_identity: org_member_identity
      create :external_identity_session, user_session: session, external_identity: org2_member_identity

      filter = Search::Filters::RepositoryFilter.new current_user: @org_member,
        user_session: session, qualifiers: Search::ParsedQuery.qualifiers

      assert_equal 2, filter.must[:bool][:should].count
      assert filter.must[:bool][:should][0][:term][:public]
      assert_same_elements [@org_repo.id, @org2_repo.id], filter.must[:bool][:should][1][:terms][:repo_id]
      assert_nil filter.must_not
      assert_nil filter.should
      assert filter.valid?
      assert filter.global?
    end
  end

  test "when business admin but not org member" do
    saml_provider = create(:business_saml_provider)
    business = saml_provider.business
    business.add_organization(create(:organization))

    biz_admin = business.admins.first
    external_identity = create :external_identity, provider: saml_provider, user: biz_admin

    session = create :user_session, user: biz_admin
    create :external_identity_session, user_session: session, external_identity: external_identity
    filter = Search::Filters::RepositoryFilter.new current_user: biz_admin,
      qualifiers: Search::ParsedQuery.qualifiers,
      user_session: session

    assert_equal({ term: { public: true } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "when business admin without a SAML session" do
    saml_provider = create(:business_saml_provider)
    business = saml_provider.business
    biz_admin = business.admins.first

    org = create(:organization)
    business.add_organization(org)
    org.add_member(biz_admin)

    external_identity = create :external_identity, provider: saml_provider, user: biz_admin
    session = create :user_session, user: biz_admin
    filter = Search::Filters::RepositoryFilter.new current_user: biz_admin,
      qualifiers: Search::ParsedQuery.qualifiers,
      user_session: session

    assert_equal({ term: { public: true } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "when business billing manager but not org member" do
    saml_provider = create(:business_saml_provider)
    business = saml_provider.business
    business.add_organization(create(:organization))

    biz_admin = business.admins.first
    billing_manager = create(:user)
    external_identity = create :external_identity, provider: saml_provider, user: billing_manager
    business.billing.add_manager(billing_manager, actor: biz_admin)

    session = create :user_session, user: billing_manager
    create :external_identity_session, user_session: session, external_identity: external_identity
    filter = Search::Filters::RepositoryFilter.new current_user: billing_manager,
      qualifiers: Search::ParsedQuery.qualifiers,
      user_session: session

    assert_equal({ term: { public: true } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "internal repos visible only from orgs that have blessed the PAT" do
    @org.add_admin @org_member
    create :organization, business: @biz, admin: @org_member
    biz_provider = create :business_saml_provider, business: @biz
    create :external_identity, user: @org_member, provider: biz_provider

    pat = make_personal_access_token(@org_member, scopes = %w(repo))
    Organization::CredentialAuthorization.grant(organization: @org, credential: pat, actor: @org_member)
    user = User.with_oauth_hashed_token(pat.hashed_token)

    filter = Search::Filters::RepositoryFilter.new current_user: user, qualifiers: Search::ParsedQuery.qualifiers

    assert_equal({ term: { public: true } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end
end

class RepositoryFilterIpAllowListEnforcementTest < GitHub::TestCase
  skip_unless :ip_allowlists_available?

  fixtures do
    @allowed_ip = "8.8.8.8"
    @disallowed_ip = "1.2.3.4"
    @user = create :user
    @org = create :business_plus_org, admin: @user
    @org.enable_ip_allowlist actor: @user
    create :ip_allowlist_entry, owner: @org, allow_list_value: "8.8.8.0/22"
    @repo = create :private_repository, owner: @org

    @emu = create :emu
    @emu_business = @emu.enterprise_managed_business
    GitHub.flipper[:ip_allowlist_user_level_enforcement].enable(@emu_business)
    create :ip_allowlist_entry, owner: @emu_business, allow_list_value: "8.8.8.0/22"
    @emu_business.enable_ip_allowlist actor: @emu_business.owners.first
    @emu_business.enable_ip_allowlist_user_level_enforcement actor: @emu_business.owners.first
    @emu_repo = create :private_repository, owner: @emu
  end

  setup do
    @quals = Search::ParsedQuery.qualifiers
  end

  test "excludes IP allow list-protected private organization repositories without an allowed IP address" do
    act_as(@user)
    filter = Search::Filters::RepositoryFilter.new \
      current_user: @user, ip: @disallowed_ip, qualifiers: @quals

    assert_equal({ term: { public: true } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "includes IP allow list-protected private organization repositories with an allowed IP" do
    filter = Search::Filters::RepositoryFilter.new \
      current_user: @user, ip: @allowed_ip, qualifiers: @quals

    assert_equal({ bool: { should: [{ term: { public: true } }, { term: { repo_id: @repo.id } }] } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "excludes EMU-owned repositories without an allowed IP address" do
    act_as(@emu)
    filter = Search::Filters::RepositoryFilter.new \
      current_user: @emu, ip: @disallowed_ip, qualifiers: @quals

    assert_equal({ term: { public: true } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "includes EMU-owned repositories with an allowed IP address" do
    filter = Search::Filters::RepositoryFilter.new \
      current_user: @emu, ip: @allowed_ip, qualifiers: @quals

    assert_equal({ bool: { should: [{ term: { public: true } }, { term: { repo_id: @emu_repo.id } }] } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "includes IP allow list-protected private organization repositories when accessed by a server-to-server GitHub Apps integration" do
    installation = make_integration_installation(target: @org, permissions: { "contents" => :read })
    bot = installation.bot
    filter = Search::Filters::RepositoryFilter.new current_user: bot, qualifiers: @quals

    assert_equal({ bool: { should: [{ term: { public: true } }, { term: { repo_id: @repo.id } }] } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "includes IP allow list-protected private organization repositories when accessed by a user-to-server GitHub Apps integration" do
    installation = make_integration_installation(target: @org, permissions: { "contents" => :read })
    grant = installation.integration.grant(@user)
    @user.oauth_access = grant
    filter = Search::Filters::RepositoryFilter.new current_user: @user, qualifiers: @quals

    assert_equal({ bool: { should: [{ term: { public: true } }, { term: { repo_id: @repo.id } }] } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end
end

class RepositoryFilterExternalCAPEnforcementTest < GitHub::TestCase
  skip_unless :idp_cap_available?

  include AuthenticationHelpers::OIDC

  fixtures do
    @owner = create :emu, :owner, provider_type: :oidc
    @business = @owner.enterprise_managed_business
    @repo = create(:private_repository, owner: @owner)

    @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
    @business.reload
    assert_predicate @business, :idp_based_ip_allowlist_configuration?
  end

  setup do
    @tenant_provider = ::OIDC::TenantProvider.new(@business)
    GitHub.flipper[:idp_cap_for_filters].enable
    GitHub.flipper[:disable_oidc_cap_cache].disable
    GitHub.flipper[:idp_cap_for_web].enable(@business)
    GitHub.flipper[:idp_cap_web_configurable_allowed].enable(@business)
    @business.enable_idp_ip_allowlist_for_web(actor: @owner)
    @quals = Search::ParsedQuery.qualifiers
  end

  test "excludes EMU-owned repositories when external CAP fails" do
    act_as(@owner)
    filter = VCR.use_cassette("oidc/azure-cap-failure", erb: { arg1: @tenant_provider.tenant_id }, record: :once) do
      Search::Filters::RepositoryFilter.new current_user: @owner, qualifiers: @quals
    end

    assert_equal({ term: { public: true } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  test "includes EMU-owned repositories when external CAP succeeds" do
    filter = VCR.use_cassette("oidc/azure-cap-success", erb: { arg1: @tenant_provider.tenant_id }, record: :once) do
      Search::Filters::RepositoryFilter.new current_user: @owner, qualifiers: @quals
    end

    assert_equal({ bool: { should: [{ term: { public: true } }, { term: { repo_id: @repo.id } }] } }, filter.must)
    assert_nil filter.must_not
    assert_nil filter.should
    assert filter.valid?
    assert filter.global?
  end

  context "#accessible_business_ids" do
    test "returns business id when external cap fails" do
      filter = VCR.use_cassette("oidc/azure-cap-failure", erb: { arg1: @tenant_provider.tenant_id }, record: :once) do
        Search::Filters::RepositoryFilter.new current_user: @owner, qualifiers: @quals
      end

      assert_equal [@business.id], filter.accessible_business_ids
    end

    test "returns business id when external cap succeeds" do
      filter = VCR.use_cassette("oidc/azure-cap-success", erb: { arg1: @tenant_provider.tenant_id }, record: :once) do
        Search::Filters::RepositoryFilter.new current_user: @owner, qualifiers: @quals
      end

      assert_equal [@business.id], filter.accessible_business_ids
    end
  end
end

if GitHub.single_tenant_enterprise?
  class RepositoryFilterEnterpriseModeTest < GitHub::TestCase
    setup do
      @admin = create :staff_admin_user
      @employee = create :user
      @org_1 = create :organization, admin: @admin, login: "first-org"
      @org_2 = create :organization, admin: @admin, login: "second-org"
      @org_3 = create :organization, admin: @admin, login: "third-org"

      @org_1.add_member(@employee)

      # Both @admin and @employee can access
      @org_1_repo = create :repository, owner: @org_1, name: "first-org-repo"
      @org_1_repo.update!(updated_at: 1.day.ago, pushed_at: 1.day.ago)
      # Only @admin can access
      @org_2_repo = create :private_repository, owner: @org_2, name: "second-org-private-repo"
      @org_2_repo.update!(updated_at: 2.days.ago, pushed_at: 2.days.ago)
      # Both @admin and @employee can access
      @org_2_collab_repo = create :repository, owner: @org_2, name: "second-org-collab-repo"
      @org_2_collab_repo.add_member(@employee, action: :read)
      @org_2_collab_repo.update!(updated_at: 3.days.ago, pushed_at: 3.days.ago)

      # Both @admin and @employee can access
      @org_3_repo = create :repository, owner: @org_3, name: "third-org-repo"
      @org_3_repo.update!(updated_at: 4.days.ago, pushed_at: 4.days.ago)

      # Only @employee can access
      @user_private_repo = create :private_repository, owner: @employee, name: "user-private-repo"
      @user_private_repo.update!(updated_at: 5.days.ago, pushed_at: 5.days.ago)

      # Only @admin can access
      @admin_private_repo = create :private_repository, owner: @admin, name: "admin-private-repo"
      @admin_private_repo.update!(updated_at: 5.days.ago, pushed_at: 5.days.ago)
      @quals = Search::ParsedQuery.qualifiers
    end

    def assert_relaxed_searchable_repositories(viewer:, repos:)
      GitHub.stubs(:enterprise_repo_search_filter_enabled?).returns(true)
      assert_searchable_repositories(viewer:, repos:)
      GitHub.unstub(:enterprise_repo_filter_enabled?)
    end

    def assert_searchable_repositories(viewer:, repos:)
      filter = Search::Filters::RepositoryFilter.new(current_user: viewer, qualifiers: @quals)
      expected = repos.map { |r| "#{r.id}:#{r.name}" }
      actual = filter.accessible_repository_ids.map { |id| "#{id}:#{Repositories::Public.get_active_or_deleted!(id).name}" }
      assert_equal expected, actual
    end

    context "when search has no qualifiers" do
      test "returns all accessible repositories for admin" do
        assert_relaxed_searchable_repositories(
          viewer: @admin,
          repos: [
            @org_1_repo,
            @org_2_repo,
            @org_2_collab_repo,
            @org_3_repo,
            @admin_private_repo,
          ])
      end

      test "most recently updated repos are returned first" do
        @org_3_repo.update!(updated_at: 1.minute.ago, pushed_at: 10.minutes.ago)
        assert_relaxed_searchable_repositories(
          viewer: @admin,
          repos: [
            @org_3_repo,
            @org_1_repo,
            @org_2_repo,
            @org_2_collab_repo,
            @admin_private_repo,
        ])

        @admin_private_repo.update!(updated_at: 1.second.ago, pushed_at: 10.seconds.ago)
        assert_relaxed_searchable_repositories(
          viewer: @admin,
          repos: [
            @admin_private_repo,
            @org_3_repo,
            @org_1_repo,
            @org_2_repo,
            @org_2_collab_repo,
        ])
      end

      test "returns all accessible repositories for employee" do
        assert_relaxed_searchable_repositories(
          viewer: @employee,
          repos: [
            @org_1_repo,
            @org_2_collab_repo,
            @org_3_repo,
            @user_private_repo,
          ])
      end
    end

    context "when search includes an org qualifier" do
      test "the search only includes repos for the relevant org for @admin" do
        @quals[:org].must ["third-org"]
        assert_relaxed_searchable_repositories(viewer: @admin, repos: [@org_3_repo])
      end

      test "the search contains the repo even though @employee is not an org member" do
        @quals[:org].must ["third-org"]
        assert_relaxed_searchable_repositories(viewer: @employee, repos: [@org_3_repo])
      end

      test "@employee can only see collaborated repos if they are not a member and all other repos are private" do
        @quals[:org].must ["second-org"]
        assert_relaxed_searchable_repositories(viewer: @employee, repos: [@org_2_collab_repo])
      end

      test "the search includes repos if the employee is in the org" do
        @quals[:org].must ["first-org"]
        assert_relaxed_searchable_repositories(viewer: @employee, repos: [
          @org_1_repo,
        ])
      end

      context "when the search has a repo qualifier" do
        test "the default search only includes qualified user private repo for the employee" do
          @quals[:repo].must ["user-private-repo"]
          assert_searchable_repositories(viewer: @employee, repos: [@user_private_repo])
        end

        test "the relaxed search only includes qualified user private repo for the employee" do
          @quals[:repo].must ["user-private-repo"]
          assert_relaxed_searchable_repositories(viewer: @employee, repos: [@user_private_repo])
        end
      end
    end
  end
end
