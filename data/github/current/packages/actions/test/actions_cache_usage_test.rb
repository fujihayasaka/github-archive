# typed: true
# frozen_string_literal: true

require "test_helper"

class ActionsCacheUsageTest < GitHub::TestCase
  fixtures do
    @user = create :user
    @org1 = create :organization
    @org2 = create :organization
    @org3 = create :organization
    @size_desc = "size-desc"
    @size_asc = "size-asc"
    @repo = nil
    @unallowed_user = create :user

    @repo1_in_org1 = create(:repository, owner: @org1, name: "server")
    @cache_size1 = 2020202
    @cache_count1 = 2
    ActionsCacheUsageHelper.save_repo_cache_usage(@repo1_in_org1.id, @cache_size1, @cache_count1, @org1.id, 1.day.ago)

    @repo2_in_org1 = create(:repository, owner: @org1, name: "hello-world")
    @cache_size2 = 1212121
    @cache_count2 = 3
    ActionsCacheUsageHelper.save_repo_cache_usage(@repo2_in_org1.id, @cache_size2, @cache_count2, @org1.id, 2.days.ago)

    @repo1_in_org2 = create(:repository, owner: @org2, name: "server")
    @cache_size3 = 3030303
    @cache_count3 = 2
    ActionsCacheUsageHelper.save_repo_cache_usage(@repo1_in_org2.id, @cache_size3, @cache_count3, @org2.id, 1.day.ago)

    @repo2_in_org2 = create(:repository, owner: @org2, name: "hello-world")
    @cache_size4 = 1313131
    @cache_count4 = 3
    ActionsCacheUsageHelper.save_repo_cache_usage(@repo2_in_org2.id, @cache_size4, @cache_count4, @org2.id, 2.days.ago)

    @repo1_in_org3 = create(:repository, owner: @org3, name: "hello-world")


    @expected_caches_size = @cache_size1 + @cache_size2 + @cache_size3 + @cache_size4
    @expected_caches_count = @cache_count1 + @cache_count2 + @cache_count3 + @cache_count4

    @expected_caches_size_for_org1 = @cache_size1 + @cache_size2
    @expected_caches_count_for_org1 = @cache_count1 + @cache_count2
  end

  context "tests for ActionsCacheUsage class" do
    test "test method get_cache_usage_for_orgs with slices of size 1" do
      data = ActionsCacheUsage.get_cache_usage_for_orgs(org_ids: [@org1.id, @org2.id], slice: 1)
      assert_equal @expected_caches_size, data[:total_active_caches_size]
      assert_equal @expected_caches_count, data[:total_active_caches_count]
    end

    test "test method get_org_cache_usage_order_by_size_with_repo_details" do
      data = ActionsCacheUsage.get_org_cache_usage_order_by_size_with_repo_details(@org1.id, 1, 25, @size_desc)
      assert_equal 2, data.length
    end

    test "test method get_org_cache_usage_order_by_size_with_repo_details with pagination" do
      data = ActionsCacheUsage.get_org_cache_usage_order_by_size_with_repo_details(@org1.id, 1, 1, @size_desc)
      # as per_page is set to 1
      assert_equal 1, data.length
    end

    test "test method get_org_cache_usage_order_by_size_with_repo_details with no active caches" do
      data = ActionsCacheUsage.get_org_cache_usage_order_by_size_with_repo_details(@org3.id, 1, 25, @size_desc)
      assert_equal 0, data.length
    end

    test "test method get_org_cache_usage_order_by_size_with_repo_details with sorting desc" do
      data = ActionsCacheUsage.get_org_cache_usage_order_by_size_with_repo_details(@org1.id, 1, 25, @size_desc)
      assert_equal 2020202, data[0].active_caches_size
    end

    test "test method get_org_cache_usage_order_by_size_with_repo_details with sorting asc" do
      data = ActionsCacheUsage.get_org_cache_usage_order_by_size_with_repo_details(@org1.id, 1, 25, @size_asc)
      assert_equal 1212121, data[0].active_caches_size
    end

    test "test method get_org_cache_usage_order_by_size_with_repo_details with filters for no match" do
      data = ActionsCacheUsage.get_org_cache_usage_order_by_size_with_repo_details(@org1.id, 1, 25, @size_desc, "cache")
      assert_empty data
    end

    test "test method get_org_cache_usage_order_by_size_with_repo_details with full repo name in filters" do
      data = ActionsCacheUsage.get_org_cache_usage_order_by_size_with_repo_details(@org1.id, 1, 25, @size_desc, "server")
      assert_equal @repo1_in_org1.id, data[0].repository_id
    end

    test "test method get_org_cache_usage_order_by_size_with_repo_details with partial repo name in filters" do
      data = ActionsCacheUsage.get_org_cache_usage_order_by_size_with_repo_details(@org1.id, 1, 25, @size_desc, "world")
      assert_equal @repo2_in_org1.id, data[0].repository_id
    end

    test "test method get_org_cache_usage" do
      data = ActionsCacheUsage.get_org_cache_usage(@org1.id)
      assert_equal @expected_caches_size_for_org1, data.total_active_caches_size
      assert_equal @expected_caches_count_for_org1, data.total_active_caches_count
    end

    test "test method get_org_cache_usage with no active caches" do
      data = ActionsCacheUsage.get_org_cache_usage(@org3.id)
      assert_equal 0, data.total_active_caches_size
      assert_equal 0, data.total_active_caches_count
    end
  end
end
