# typed: true
# frozen_string_literal: true

require "test_helper"

class WriteThroughCacheTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @org = create :organization
    @private_repo_collaborator = create :user, login: "private-collaborator"
    @private_repo = create(:private_repository, :minimal, owner: @org)
    @public_repo_collaborator = create :user, login: "public-collaborator"
    @public_repo = create(:public_repository, :minimal, owner: @org)
    @member = create :user
    @business = create :business, organizations: [@org]

    @private_repo.add_member(@private_repo_collaborator)
    @public_repo.add_member(@public_repo_collaborator)
    @org.add_member @member
  end

  setup do
    enable_cache_storage
    reset_cache
    GitHub.flipper[:business_write_through_cache].enable(@business)
  end

  teardown do
    disable_cache_storage
  end

  context "#get_and_update" do
    test "returns the results of the given method without updating cache when feature flag is disabled" do
      GitHub.flipper[:business_write_through_cache].disable(@business)
      Business::PassThroughCache.any_instance.expects(:set).never

      assert_equal @business.all_member_ids, @business.write_through_cache.get_and_update(:all_member_ids)
    end

    test "updates the cache and returns values if cache is empty" do
      expected_values = @business.all_member_ids
      Business::PassThroughCache.any_instance.expects(:set).with("all_member_ids", expected_values, :int)

      assert_equal expected_values, @business.write_through_cache.get_and_update(:all_member_ids)
    end

    test "returns nil for nil responses" do
      Business::any_instance.expects(:all_member_ids).returns(nil)

      assert_nil @business.write_through_cache.get_and_update(:all_member_ids)
    end

    test "returns an empty array for empty responses" do
      Business::any_instance.expects(:all_member_ids).returns([])

      assert_equal [], @business.write_through_cache.get_and_update(:all_member_ids)
    end

    test "supports pluck argument for business methods" do
      expected_values = @business.filtered_outside_collaborators.pluck(:id)

      assert_equal expected_values, @business.write_through_cache
        .get_and_update(:filtered_outside_collaborators, {}, pluck: :id)
    end

    test "passes correct arguments to business method" do
      expected_public_values = @business.filtered_outside_collaborators(visibility: [:public]).pluck(:id)
      expected_private_values = @business.filtered_outside_collaborators(visibility: [:private]).pluck(:id)

      assert_equal expected_public_values, @business.write_through_cache
        .get_and_update(:filtered_outside_collaborators, { visibility: [:public] }, pluck: :id)
      assert_equal expected_private_values, @business.write_through_cache
        .get_and_update(:filtered_outside_collaborators, { visibility: [:private] }, pluck: :id)
    end

    test "enqueues a background job to update values when method is accessed" do
      # This will only update via background job when the cache is already populated. Populating the cache here so
      # the background job will be enqueued.
      @business.write_through_cache.update(:all_member_ids, type: :int)

      assert_enqueued_with(job: BusinessUpdateWriteThroughCacheJob) do
        @business.write_through_cache.get_and_update(:all_member_ids)
      end
    end

    test "enqueued background job contains appropriate arguments" do
      # This will only update via background job when the cache is already populated. Populating the cache here so
      # the background job will be enqueued.
      @business.write_through_cache.update(:filtered_outside_collaborators, { visibility: [:public] }, type: :int,
        pluck: :id)

      # First argument in the job is the job lock key
      assert_enqueued_with(job: BusinessUpdateWriteThroughCacheJob, args:
        [
          "filtered_outside_collaborators:visibility-[:public]:id",
          @business,
          :filtered_outside_collaborators,
          { visibility: [:public] },
          :int,
          :id,
        ]) do
        @business.write_through_cache.get_and_update(:filtered_outside_collaborators, { visibility: [:public] },
          pluck: :id)
      end
    end

    test "responds quickly even if given method is slow" do
      # Set an intial value so it uses the cache
      @business.write_through_cache.update(:all_member_ids, type: :int)

      # Getting expected member IDs now, because they will be stubbed out with a sleep delay.
      expected_member_ids = @business.all_member_ids

      # Simulate a long running method
      @business.stubs(:all_member_ids).returns { sleep 5; [4, 5, 6] }

      # Time the operation to show this is done in the background
      start_time = Time.now
      updated_values = @business.write_through_cache.get_and_update(:all_member_ids)
      end_time = Time.now

      assert end_time - start_time < 1

      # Check that the values are using the cached values
      assert_equal updated_values, expected_member_ids
    end

    test "returns updated results after an additional call" do
      # Populate the cache
      @business.write_through_cache.update(:all_member_ids, type: :int)

      # Change the value of all_member_ids
      @org.add_member(create :user)

      # Call the method again to update the cache
      perform_enqueued_jobs(only: [BusinessUpdateWriteThroughCacheJob]) do
        stale_results = @business.write_through_cache.get_and_update(:all_member_ids)
      end

      # Verify the results are now updated
      assert_equal @business.all_member_ids, @business.write_through_cache.get_and_update(:all_member_ids)
    end

    unless GitHub.single_business_environment?
      test "returns the cached results from the given business only" do
        business2 = create :business
        org2 = create :organization, business: business2
        org2.add_member(create :user)
        GitHub.flipper[:business_write_through_cache].enable(business2)

        # Calling methods twice to ensure cache is populated
        2.times do
          perform_enqueued_jobs(only: [BusinessUpdateWriteThroughCacheJob]) do
            assert_equal @business.all_member_ids, @business.write_through_cache.get_and_update(:all_member_ids)
            assert_equal business2.all_member_ids, business2.write_through_cache.get_and_update(:all_member_ids)
          end
        end
      end
    end
  end

  context "#update" do
    test "does not call the given business method when feature flag is disabled" do
      GitHub.flipper[:business_write_through_cache].disable(@business)

      Business::any_instance.expects(:all_member_ids).never
      Business::PassThroughCache.any_instance.expects(:set).never

      @business.write_through_cache.update(:all_member_ids, type: :int)
    end

    test "updates the cache with the results of a given method" do
      expected_values = @business.all_member_ids
      Business::PassThroughCache.any_instance.expects(:set).with("all_member_ids", expected_values, :int)

      @business.write_through_cache.update(:all_member_ids, type: :int)
    end

    test "does not store nil values in the cache" do
      Business::any_instance.expects(:all_member_ids).returns(nil)
      Business::PassThroughCache.any_instance.expects(:set).never

      @business.write_through_cache.update(:all_member_ids, type: :int)
    end

    test "can store empty results in the cache" do
      Business::any_instance.expects(:all_member_ids).returns([])
      Business::PassThroughCache.any_instance.expects(:set).with("all_member_ids", [], :int)

      @business.write_through_cache.update(:all_member_ids, type: :int)
    end

    test "cache stores results from different arguments in different keys" do
      expected_public_values = @business.filtered_outside_collaborators(visibility: [:public]).pluck(:id)
      expected_private_values = @business.filtered_outside_collaborators(visibility: [:private]).pluck(:id)
      Business::PassThroughCache.any_instance.expects(:set)
        .with("filtered_outside_collaborators:visibility-[:public]:id", expected_public_values, :int)
      Business::PassThroughCache.any_instance.expects(:set)
        .with("filtered_outside_collaborators:visibility-[:private]:id", expected_private_values, :int)

      @business.write_through_cache.update(:filtered_outside_collaborators, { visibility: [:public] }, type: :int,
        pluck: :id)
      @business.write_through_cache.update(:filtered_outside_collaborators, { visibility: [:private] }, type: :int,
        pluck: :id)
    end

    test "cache stores results with different plucks in different keys" do
      expected_id_values = @business.filtered_outside_collaborators.pluck(:id)
      expected_login_values = @business.filtered_outside_collaborators.pluck(:display_login)
      Business::PassThroughCache.any_instance.expects(:set)
        .with("filtered_outside_collaborators:id", expected_id_values, :int)
      Business::PassThroughCache.any_instance.expects(:set)
        .with("filtered_outside_collaborators:display_login", expected_login_values, :string)

      @business.write_through_cache.update(:filtered_outside_collaborators, {}, type: :int, pluck: :id)
      @business.write_through_cache.update(:filtered_outside_collaborators, {}, type: :string, pluck: :display_login)
    end
  end

  context "metrics" do
    test "records cache hits" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      # Set an intial value so it uses the cache
      @business.write_through_cache.update(:all_member_ids, type: :int)
      @business.write_through_cache.get_and_update(:all_member_ids)

      assert_equal 1, GitHub.dogstats.increments("business.write_through_cache.count",
        tags: ["method:all_member_ids", "cache:hit"]).count
    end

    test "records cache misses" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @business.write_through_cache.get_and_update(:all_member_ids)

      assert_equal 1, GitHub.dogstats.increments("business.write_through_cache.count",
        tags: ["method:all_member_ids", "cache:miss"]).count
    end
  end
end
