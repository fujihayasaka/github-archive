# typed: false
# frozen_string_literal: true

require "test_helper"

class ContributionAccessorCacheTest < GitHub::TestCase
  include HydroTestHelpers

  context ".user_namespace" do
    test "returns different values for different users when namespace is generated simultaneously" do
      Timecop.freeze do
        user1, user2 = create_pair(:user)

        user1_namespace = Contribution::Accessor::Cache.user_namespace user1
        user2_namespace = Contribution::Accessor::Cache.user_namespace user2

        refute_equal user1_namespace, user2_namespace
      end
    end
  end

  context ".clear_cache_for_user" do
    if GitHub.single_tenant_enterprise?
      test "clears the cache" do
        user = create(:user)

        cache_key = Contribution::Accessor::Cache.send(:user_namespace_key, user.id)
        Profiles::Kv.store.expects(:del).with(cache_key)
        Contribution::Accessor::Cache.clear_cache_for_user(user)
        assert_hydro_messages(count: 0, schema: "github.users.v1.ContributionHistoryModified")
      end
    else
      test "generates a hydro event" do
        user = create(:user)

        Profiles::Kv.store.expects(:del).never
        Contribution::Accessor::Cache.clear_cache_for_user(user)

        message = { user: Hydro::EntitySerializer.user(user) }
        assert_hydro_published(message, schema: "github.users.v1.ContributionHistoryModified")
      end
    end
  end

  context ".bulk_clear_cache_for_users" do
    if GitHub.single_tenant_enterprise?
      test "clears the cache for all users" do
        users = create_list(:user, 2)

        cache_keys = users.map { |user| Contribution::Accessor::Cache.send(:user_namespace_key, user.id) }
        Profiles::Kv.store.expects(:mdel).with(cache_keys)

        Contribution::Accessor::Cache.bulk_clear_cache_for_users(users)
      end
    else
      test "generates hydro events for all users" do
        users = create_list(:user, 2)

        Profiles::Kv.store.expects(:mdel).never

        Contribution::Accessor::Cache.bulk_clear_cache_for_users(users)

        users.each do |user|
          message = { user: Hydro::EntitySerializer.user(user) }
          assert_hydro_published(message, schema: "github.users.v1.ContributionHistoryModified")
        end
      end
    end
  end

  context ".bulk_reset_user_namespace" do
    test "passes expiration to the KV store" do
      Timecop.freeze do
        expiration = 1.day.from_now

        user_ids = [1, 2, 3]
        expected_updates = user_ids.each_with_object({}) do |user_id, hash|
          key = Contribution::Accessor::Cache.send(:user_namespace_key, user_id)
          value = Contribution::Accessor::Cache.send(:user_namespace_value, user_id)
          hash[key] = value
        end

        Profiles::Kv.store.expects(:mset).with(expected_updates, expires: expiration).once
        Contribution::Accessor::Cache.bulk_reset_user_namespace(user_ids, expires: expiration)
      end
    end

    test "default to nil expiration" do
      Timecop.freeze do
        user_ids = [1, 2, 3]
        expected_updates = user_ids.each_with_object({}) do |user_id, hash|
          key = Contribution::Accessor::Cache.send(:user_namespace_key, user_id)
          value = Contribution::Accessor::Cache.send(:user_namespace_value, user_id)
          hash[key] = value
        end

        Profiles::Kv.store.expects(:mset).with(expected_updates, expires: nil).once
        Contribution::Accessor::Cache.bulk_reset_user_namespace(user_ids)
      end
    end
  end

  context "cache key generation" do
    # Ensure we don't make unexpected changes to our cache key
    test "generates a key unique on the cache version, user namespace, and constructor arguments" do
      user = create(:user)
      viewer = create(:user)
      date_range = Date.yesterday..Date.tomorrow
      start_date = date_range.begin
      end_date = date_range.end
      organization_id = 123

      klass = Contribution::Accessor::Cache
      cache = klass.new(
        user: user,
        viewer: viewer,
        date_range: date_range,
        contribution_classes: [Contribution::CreatedRepository, Contribution::CreatedIssue],
        organization_id: organization_id,
        skip_restricted: skip_restricted = false,
        excluded_organization_ids: [3, 2, 1],
        lightweight: lightweight = false,
      )

      expected_key_seed =
        "#{klass::CACHE_VERSION}:#{klass.user_namespace(user)}:" \
        "Contribution::CreatedIssue,Contribution::CreatedRepository:" \
        "#{start_date}:#{end_date}:#{viewer.id}:#{organization_id}:#{skip_restricted}:" \
        "1,2,3:#{lightweight}"

      assert_equal "accessor-cache:#{Digest::SHA256.hexdigest(expected_key_seed)}", cache.send(:key)
    end
  end

  context "#log_cache_stat" do
    test "logs cache miss if data is nil" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      user = create(:user)

      cache = Contribution::Accessor::Cache.new(
        user: user,
        viewer: nil,
        date_range: Date.yesterday..Date.tomorrow,
        contribution_classes: [],
        organization_id: 123,
        skip_restricted: skip_restricted = false,
        excluded_organization_ids: [3, 2, 1],
        lightweight: false,
      )
      cache.get

      assert_equal 1, GitHub.dogstats.increments("cache.miss").length
    end

    test "logs cache hit if data is not nil" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      user = create(:user)

      cache = Contribution::Accessor::Cache.new(
        user: user,
        viewer: nil,
        date_range: Date.yesterday..Date.tomorrow,
        contribution_classes: [],
        organization_id: 123,
        skip_restricted: skip_restricted = false,
        excluded_organization_ids: [3, 2, 1],
        lightweight: false,
      )
      GitHub.cache.stubs(:get).with(cache.send(:key)).returns(true)
      cache.get

      assert_equal 1, GitHub.dogstats.increments("cache.hit").length
    end

    test "sets logged_in tag to true if viewer exists" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      user = create(:user)
      viewer = create(:user)

      cache = Contribution::Accessor::Cache.new(
        user: user,
        viewer: viewer,
        date_range: Date.yesterday..Date.tomorrow,
        contribution_classes: [],
        organization_id: 123,
        skip_restricted: skip_restricted = false,
        excluded_organization_ids: [3, 2, 1],
        lightweight: false,
      )
      cache.get

      assert_equal 1, GitHub.dogstats.increments("cache.miss", keys: ["logged_in:true"]).length
    end

    test "sets logged_in tag to false if viewer does not exist" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      user = create(:user)

      cache = Contribution::Accessor::Cache.new(
        user: user,
        viewer: nil,
        date_range: Date.yesterday..Date.tomorrow,
        contribution_classes: [],
        organization_id: 123,
        skip_restricted: skip_restricted = false,
        excluded_organization_ids: [3, 2, 1],
        lightweight: false,
      )
      cache.get

      assert_equal 1, GitHub.dogstats.increments("cache.miss", keys: ["logged_in:false"]).length
    end

    test "sets is_year_long tag to true if date range is longer than a year" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      user = create(:user)
      date_range = 1.year.ago.to_date..Date.today
      organization_id = 123

      cache = Contribution::Accessor::Cache.new(
        user: user,
        viewer: nil,
        date_range: date_range,
        contribution_classes: [],
        organization_id: organization_id,
        skip_restricted: skip_restricted = false,
        excluded_organization_ids: [3, 2, 1],
        lightweight: false,
      )
      cache.get

      assert_equal 1, GitHub.dogstats.increments("cache.miss", keys: ["is_year_long:true"]).length
    end

    test "sets includes_today tag to true if date range includes today" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      user = create(:user)

      cache = Contribution::Accessor::Cache.new(
        user: user,
        viewer: nil,
        date_range: 1.month.ago.to_date..1.month.since.to_date,
        contribution_classes: [],
        organization_id: 123,
        skip_restricted: skip_restricted = false,
        excluded_organization_ids: [3, 2, 1],
        lightweight: false,
      )
      cache.get

      assert_equal 1, GitHub.dogstats.increments("cache.miss", keys: ["includes_today:true"]).length
    end
  end
end
