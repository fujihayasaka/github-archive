# typed: true
# frozen_string_literal: true

require "test_helper"

class ActionsCacheUsageTest < GitHub::TestCase
  fixtures do
    @user = create :user
    @org1 = create :organization
    @org2 = create :organization
    @org3 = create :organization
    @org4 = create :organization
    @size_desc = "size-desc"
    @size_asc = "size-asc"
    @repo = nil
    @unallowed_user = create :user

    @repo1_in_org1 = create(:repository, owner: @org1, name: "server")
    @cache_size1 = 2020202
    @cache_count1 = 2
    ActionsCacheUsageHelper.save_repo_cache_usage(@repo1_in_org1, @cache_size1, @cache_count1, @org1.id, 1.day.ago, false)
    ActionsCacheUsageHelper.save_repo_cache_usage(@repo1_in_org1, @cache_size1, @cache_count1, @org1.id, 1.day.ago, true)

    @repo3_in_org4 = create(:repository, owner: @org4, name: "mega-repo")
    ActionsCacheUsageHelper.save_repo_cache_usage(@repo3_in_org4, 100, 2, @org4.id, 1.day.ago, false)
    ActionsCacheUsageHelper.save_repo_cache_usage(@repo3_in_org4, 50, 9, @org4.id, 1.day.ago, true)

    @repo2_in_org1 = create(:repository, owner: @org1, name: "hello-world")
    @cache_size2 = 1212121
    @cache_count2 = 3
    ActionsCacheUsageHelper.save_repo_cache_usage(@repo2_in_org1, @cache_size2, @cache_count2, @org1.id, 2.days.ago, false)
    ActionsCacheUsageHelper.save_repo_cache_usage(@repo2_in_org1, @cache_size2, @cache_count2, @org1.id, 2.days.ago, true)

    @repo1_in_org2 = create(:repository, owner: @org2, name: "server")
    @cache_size3 = 3030303
    @cache_count3 = 2
    ActionsCacheUsageHelper.save_repo_cache_usage(@repo1_in_org2, @cache_size3, @cache_count3, @org2.id, 1.day.ago, false)

    @repo2_in_org2 = create(:repository, owner: @org2, name: "hello-world")
    @cache_size4 = 1313131
    @cache_count4 = 3
    ActionsCacheUsageHelper.save_repo_cache_usage(@repo2_in_org2, @cache_size4, @cache_count4, @org2.id, 2.days.ago, false)

    @repo1_in_org3 = create(:repository, owner: @org3, name: "hello-world")

    @expected_caches_size_for_org1 = @cache_size1 * 2 + @cache_size2 * 2
    @expected_caches_count_for_org1 = @cache_count1 * 2 + @cache_count2 * 2
  end

  context "tests for ActionsCacheUsage class" do

    test "test method get_repo_cache_usage results and artifact-cache cache usage" do
      data = ActionsCacheUsage.get_repo_cache_usage(@repo3_in_org4)
      if @repo3_in_org4&.feature_enabled?(:use_merged_cache_usage)
        assert_equal 150, data.active_caches_size
        assert_equal 11, data.active_caches_count
      else
        assert_equal 50, data.active_caches_size
        assert_equal 9, data.active_caches_count
      end
    end

    test "test method get_repo_cache_usage with results cache usage" do
      org = create :organization
      repo_in_org = create(:repository, owner: org, name: "mega-giga-repo")
      active_caches_size = 100
      active_caches_count = 10
      ActionsCacheUsageHelper.save_repo_cache_usage(repo_in_org, active_caches_size, active_caches_count, repo_in_org.id, 1.day.ago, true)
      data = ActionsCacheUsage.get_repo_cache_usage(repo_in_org)

      assert_equal active_caches_size, data.active_caches_size
      assert_equal active_caches_count, data.active_caches_count
    end

    test "test method get_repo_cache_usage with artifact-cache cache usage" do
      org = create :organization
      repo_in_org = create(:repository, owner: org, name: "tiny-repo")
      active_caches_size = 1000
      active_caches_count = 99
      ActionsCacheUsageHelper.save_repo_cache_usage(repo_in_org, active_caches_size, active_caches_count, repo_in_org.id, 1.day.ago, false)
      data = ActionsCacheUsage.get_repo_cache_usage(repo_in_org)

      assert_equal active_caches_size, data.active_caches_size
      assert_equal active_caches_count, data.active_caches_count
    end

    test "test method get_cache_usage_for_orgs with artifact-cache and results cache usage" do
      org_1 = create :organization
      repo_1_in_org_1 = create(:repository, owner: org_1, name: "org-1-repo-1")
      repo_1_in_org_1_active_caches_size = 500
      repo_1_in_org_1_active_caches_count = 99
      ActionsCacheUsageHelper.save_repo_cache_usage(repo_1_in_org_1, repo_1_in_org_1_active_caches_size, repo_1_in_org_1_active_caches_count, org_1.id, 1.day.ago, false)
      ActionsCacheUsageHelper.save_repo_cache_usage(repo_1_in_org_1, repo_1_in_org_1_active_caches_size, repo_1_in_org_1_active_caches_count, org_1.id, 1.day.ago, true)

      repo_2_in_org_1 = create(:repository, owner: org_1, name: "org-1-repo-2")
      repo_2_in_org_1_active_caches_size = 500
      repo_2_in_org_1_active_caches_count = 1
      ActionsCacheUsageHelper.save_repo_cache_usage(repo_2_in_org_1, repo_2_in_org_1_active_caches_size, repo_2_in_org_1_active_caches_count, org_1.id, 1.day.ago, false)
      ActionsCacheUsageHelper.save_repo_cache_usage(repo_2_in_org_1, repo_2_in_org_1_active_caches_size, repo_2_in_org_1_active_caches_count, org_1.id, 1.day.ago, true)

      org_2 = create :organization
      repo_1_in_org_2 = create(:repository, owner: org_2, name: "org-2-repo-1")
      repo_1_in_org_2_active_caches_size = 1000
      repo_1_in_org_2_active_caches_count = 99
      ActionsCacheUsageHelper.save_repo_cache_usage(repo_1_in_org_2, repo_1_in_org_2_active_caches_size, repo_1_in_org_2_active_caches_count, org_2.id, 1.day.ago, false)
      ActionsCacheUsageHelper.save_repo_cache_usage(repo_1_in_org_2, repo_1_in_org_2_active_caches_size, repo_1_in_org_2_active_caches_count, org_2.id, 1.day.ago, true)

      repo_2_in_org_2 = create(:repository, owner: org_2, name: "org-2-repo-2")
      repo_2_in_org_active_caches_size = 2
      repo_2_in_org_active_caches_count = 200
      ActionsCacheUsageHelper.save_repo_cache_usage(repo_2_in_org_2, repo_2_in_org_active_caches_size, repo_2_in_org_active_caches_count, org_2.id, 1.day.ago, false)
      ActionsCacheUsageHelper.save_repo_cache_usage(repo_2_in_org_2, repo_2_in_org_active_caches_size, repo_2_in_org_active_caches_count, org_2.id, 1.day.ago, true)

      data = ActionsCacheUsage.get_cache_usage_for_orgs(org_ids: [org_1.id, org_2.id], slice: 1)
      if repo_1_in_org_1&.feature_enabled?(:use_merged_cache_usage) && repo_2_in_org_1&.feature_enabled?(:use_merged_cache_usage) && repo_1_in_org_2&.feature_enabled?(:use_merged_cache_usage) && repo_2_in_org_2&.feature_enabled?(:use_merged_cache_usage)
        assert_equal repo_1_in_org_1_active_caches_size * 2 + repo_2_in_org_1_active_caches_size * 2 + repo_1_in_org_2_active_caches_size * 2 + repo_2_in_org_active_caches_size * 2, data[:total_active_caches_size]
        assert_equal repo_1_in_org_1_active_caches_count * 2 + repo_2_in_org_1_active_caches_count * 2 + repo_1_in_org_2_active_caches_count * 2 + repo_2_in_org_active_caches_count * 2, data[:total_active_caches_count]
      else
        assert_equal repo_1_in_org_1_active_caches_size + repo_2_in_org_1_active_caches_size + repo_1_in_org_2_active_caches_size + repo_2_in_org_active_caches_size, data[:total_active_caches_size]
        assert_equal repo_1_in_org_1_active_caches_count + repo_2_in_org_1_active_caches_count + repo_1_in_org_2_active_caches_count + repo_2_in_org_active_caches_count, data[:total_active_caches_count]
      end
    end

    test "test method get_cache_usage_for_orgs with slices of size 1" do
      data = ActionsCacheUsage.get_cache_usage_for_orgs(org_ids: [@org1, @org2], slice: 1)
      if @org1&.feature_enabled?(:use_merged_cache_usage) && @org2&.feature_enabled?(:use_merged_cache_usage)
        assert_equal @cache_size1 * 2 + @cache_size2 * 2 + @cache_size3 + @cache_size4, data[:total_active_caches_size]
        assert_equal @cache_count1 * 2 + @cache_count2 * 2 + @cache_count3 + @cache_count4, data[:total_active_caches_count]
      else
        assert_equal @cache_size1 + @cache_size2 + @cache_size3 + @cache_size4, data[:total_active_caches_size]
        assert_equal @cache_count1 + @cache_count2 + @cache_count3 + @cache_count4, data[:total_active_caches_count]
      end
    end

    test "test method get_org_cache_usage_order_by_size_with_repo_details" do
      data = ActionsCacheUsage.get_org_cache_usage_order_by_size_with_repo_details(@org1.id, 1, 25, @size_desc)
      if @org1&.feature_enabled?(:use_merged_cache_usage)
        assert_equal 4, data.length
      else
        assert_equal 2, data.length
      end
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
      if @org1&.feature_enabled?(:use_merged_cache_usage)
        assert_equal @expected_caches_size_for_org1, data.total_active_caches_size
        assert_equal @expected_caches_count_for_org1, data.total_active_caches_count
      else
        assert_equal @cache_size1 + @cache_size2, data.total_active_caches_size
        assert_equal @cache_count1 + @cache_count2, data.total_active_caches_count
      end
    end

    test "test method get_org_cache_usage with no active caches" do
      data = ActionsCacheUsage.get_org_cache_usage(@org3.id)
      assert_equal 0, data.total_active_caches_size
      assert_equal 0, data.total_active_caches_count
    end
  end
end
