# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryOwnerDependenciesLoaderTest < GitHub::TestCase
  fixtures do
    @staff = create(:user, :staff)

    @sponsorable_owner1 = create(:user, :sponsorable)
    @sponsorable_dependency1 = create(:repository_sponsorable, :owner, sponsorable: @sponsorable_owner1).repository

    @sponsorable_owner2 = create(:user, :sponsorable)
    @sponsorable_dependency2 = create(:repository_sponsorable, :owner, sponsorable: @sponsorable_owner2).repository

    @private_sponsorable_dependency = create(:private_repository, owner: @sponsorable_owner1)
    create(:repository_sponsorable, :owner, sponsorable: @sponsorable_owner1,
      repository: @private_sponsorable_dependency)

    @non_sponsorable_dependency = create(:repository)

    @private_non_sponsorable_dependency = create(:private_repository)

    if GitHub.spamminess_check_enabled?
      @spammer = create(:spammy_user)
      @spammy_dependency = create(:repository, owner: @spammer)
    end
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    @loader = Repository::OwnerDependenciesLoader.new(owner_id: 1, public_only: false)
  end

  context "#total_dependencies" do
    test "returns count of visible dependencies that match given scope" do
      dependency_ids = [@sponsorable_dependency2, @sponsorable_dependency1, @non_sponsorable_dependency,
        @private_non_sponsorable_dependency].map(&:id)
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: dependency_ids } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      assert_equal 2, @loader.total_dependencies(scope: Repository.with_sponsorable_owner)
      assert_equal 2, @loader.total_dependencies(scope: Repository.public_scope.with_sponsorable_owner)
      assert_equal 3, @loader.total_dependencies(scope: Repository.public_scope)
      assert_equal 3, @loader.total_dependencies,
        "should still get a count excluding private dependency for anonymous viewer"

      viewer = create(:user)
      @private_non_sponsorable_dependency.add_member(viewer)

      loader = Repository::OwnerDependenciesLoader.new(owner_id: 1, public_only: false, viewer: viewer)
      assert_equal 4, loader.total_dependencies, "viewer with access to private dependency should have it counted"
    end
  end

  context "#dependencies" do
    test "memoizes repeated calls with the same parameters" do
      owner_id = @sponsorable_owner1.id
      viewer = @sponsorable_owner1
      sort_by = Repository::OwnerDependenciesLoader::DG_API_SORT_OPTIONS.first
      dependencies = [@sponsorable_dependency2, @non_sponsorable_dependency]
      preloads = [:owner_sponsors_listing_stafftools_metadata]

      fake_result = stub(ok?: true, value!: { dependencies: dependencies.map(&:id) })
      Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with({
        owner_id: owner_id, sort_by: sort_by, package_managers: [], public_only: false, direct_only: false,
        repository_ids: [],
      }).returns(Promise.resolve(fake_result))

      loader = Repository::OwnerDependenciesLoader.new(owner_id: owner_id, sort_by: sort_by, package_managers: [],
        public_only: false, direct_only: false, viewer: viewer)

      result = assert_query_count_per_table({ repositories: 2, sponsors_listing_stafftools_metadata: 1 }) do
        loader.dependencies(preloads: preloads)
      end
      assert_same_elements dependencies, result.dependencies

      # Ensure the relations we specified were prefilled on each returned dependency when result not memoized:
      assert_query_count(0) do
        result.dependencies.each(&:owner_sponsors_listing_stafftools_metadata)
      end

      memoized_result = assert_query_count_per_table({ repositories: 0, sponsors_listing_stafftools_metadata: 0 }) do
        loader.dependencies(preloads: preloads)
      end
      assert_same_elements dependencies, memoized_result.dependencies

      # Ensure the relations we specified were prefilled on each returned dependency from memoized value:
      assert_query_count(0) do
        memoized_result.dependencies.each(&:owner_sponsors_listing_stafftools_metadata)
      end
    end
  end

  context "#async_dependencies" do
    test "preserves dependency graph API sorting across multiple batches" do
      arbitrary_repo_id_order = [@non_sponsorable_dependency.id, @sponsorable_dependency1.id,
        @sponsorable_dependency2.id]
      refute_equal arbitrary_repo_id_order, Repository.where(id: arbitrary_repo_id_order).pluck(:id),
        "need an order of repo IDs to come back from the dependency graph API in an order different from how a " \
        "Repository query would return them"

      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: arbitrary_repo_id_order } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = Repository::OwnerDependenciesLoader.new(
        owner_id: 1,
        sort_by: Repository::OwnerDependenciesLoader::DG_API_SORT_OPTIONS.first,
        package_managers: [],
        public_only: false,
        direct_only: false,
      )

      Repository::OwnerDependenciesLoader.stub_const(:BATCH_SIZE, 1) do
        result = loader.async_dependencies.sync

        assert_equal arbitrary_repo_id_order, result.dependencies.map(&:id),
          "expected to get back all the results at once, in the same order as the dependency graph API returned them"
        refute_predicate result, :already_sorted?
      end
    end

    test "filters by given scope" do
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: {
          dependencies: [@sponsorable_dependency2.id, @sponsorable_dependency1.id, @non_sponsorable_dependency.id],
        } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)
      scope = Repository.where(id: @sponsorable_dependency1.id)

      result = @loader.async_dependencies(scope: scope).sync

      assert_equal [@sponsorable_dependency1], result.dependencies
      assert_predicate result, :already_sorted?
    end

    test "returns only public dependencies when viewer is anonymous" do
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: {
          dependencies: [@sponsorable_dependency1.id, @private_sponsorable_dependency.id],
        } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      result = @loader.async_dependencies.sync

      assert_includes result.dependencies, @sponsorable_dependency1
      refute_includes result.dependencies, @private_sponsorable_dependency
      assert_predicate result, :already_sorted?
    end

    test "returns public and visible private dependencies for specified viewer" do
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: {
          dependencies: [@sponsorable_dependency1.id, @private_sponsorable_dependency.id],
        } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = Repository::OwnerDependenciesLoader.new(owner_id: 1, public_only: false,
        viewer: @private_sponsorable_dependency.owner)
      result = loader.async_dependencies.sync

      assert_same_elements [@sponsorable_dependency1, @private_sponsorable_dependency], result.dependencies
      assert_predicate result, :already_sorted?
    end

    test "omits private dependencies the viewer cannot access" do
      rando = create(:user)
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: {
          dependencies: [@sponsorable_dependency1.id, @private_sponsorable_dependency.id],
        } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = Repository::OwnerDependenciesLoader.new(owner_id: 1, public_only: false, viewer: rando)
      result = loader.async_dependencies.sync

      assert_includes result.dependencies, @sponsorable_dependency1
      refute_includes result.dependencies, @private_sponsorable_dependency
      assert_predicate result, :already_sorted?
    end

    test "filters out spammy dependencies for viewer who can't see them" do
      innocent_user = create(:user)
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: {
          dependencies: [@non_sponsorable_dependency.id, @spammy_dependency.id],
        } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = Repository::OwnerDependenciesLoader.new(owner_id: 1, public_only: false, viewer: innocent_user)
      result = loader.async_dependencies.sync

      assert_includes result.dependencies, @non_sponsorable_dependency
      refute_includes result.dependencies, @spammy_dependency
      assert_predicate result, :already_sorted?
    end if GitHub.spamminess_check_enabled?

    test "includes spammy dependencies for staff viewer" do
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: {
          dependencies: [@non_sponsorable_dependency.id, @spammy_dependency.id],
        } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)
      scope = Repository.order(:id)

      loader = Repository::OwnerDependenciesLoader.new(owner_id: 1, public_only: false, viewer: @staff)
      result = loader.async_dependencies(scope: scope).sync

      assert_equal [@non_sponsorable_dependency, @spammy_dependency], result.dependencies
      assert_predicate result, :already_sorted?
    end if GitHub.spamminess_check_enabled?

    test "excludes disabled dependencies" do
      disabled_dependency = create(:repository)
      disabled_dependency.access.disable("size", @staff)
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [disabled_dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      result = @loader.async_dependencies.sync

      assert_empty result.dependencies
      assert_predicate result, :already_sorted?
    end
  end

  test "loads repository owner dependencies with given parameters" do
    fake_result = stub(ok?: true, value!: { dependencies: [] })
    Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with({
      owner_id: 1,
      sort_by: nil,
      package_managers: [],
      public_only: false,
      direct_only: false,
      repository_ids: [],
    }).returns(Promise.resolve(fake_result))

    @loader.async_dependency_ids
  end
end
