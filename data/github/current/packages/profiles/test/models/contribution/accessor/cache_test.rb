# typed: false
# frozen_string_literal: true

require "test_helper"

class ContributionAccessorCacheTest < GitHub::TestCase
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
