# typed: true
# frozen_string_literal: true

require "test_helper"

class ActionsCacheUsageHelperTest < GitHub::TestCase
  fixtures do
    @org = create :organization
    @org_for_transfer = create :organization

    @repo = create(:repository, owner: @org, name: "server")
  end

  context "check ActionsCacheUsageHelper works correctly" do
    test "add new actions cache usage" do
      owner_id = @org.id
      active_caches_size = 1111
      active_caches_count = 1

      ActionsCacheUsageHelper.save_repo_cache_usage(@repo, active_caches_size, active_caches_count, owner_id, DateTime.now, true)
      ac_usage = ActionsCacheUsageHelper.get_all_actions_cache

      assert_equal 1, ac_usage.length
      assert_equal @repo.id, ac_usage.last.repository_id
      assert_equal owner_id, ac_usage.last.owner_id
      assert_equal 1111, ac_usage.last.active_caches_size
      assert_equal 1, ac_usage.last.active_caches_count
      assert_equal true, ac_usage.last.is_results_usage
    end

    test "update existing actions cache usage" do
      owner_id = @org.id
      active_caches_size = 1111
      active_caches_count = 1

      ActionsCacheUsageHelper.save_repo_cache_usage(@repo, active_caches_size, active_caches_count, owner_id, DateTime.now, true)

      active_caches_size = 9999
      active_caches_count = 2

      ActionsCacheUsageHelper.save_repo_cache_usage(@repo, active_caches_size, active_caches_count, owner_id, DateTime.now, true)
      ac_usage = ActionsCacheUsageHelper.get_all_actions_cache

      assert_equal 1, ac_usage.length
      assert_equal 9999, ac_usage.last.active_caches_size
      assert_equal 2, ac_usage.last.active_caches_count
      assert_equal true, ac_usage.last.is_results_usage
      assert_equal @repo.id, ac_usage.last.repository_id
      assert_equal owner_id, ac_usage.last.owner_id
    end

    test "test method transfer_cache_owner" do
      owner_id = @org.id
      active_caches_size = 101012
      active_caches_count = 3

      ActionsCacheUsageHelper.save_repo_cache_usage(@repo, active_caches_size, active_caches_count, owner_id, DateTime.now, false)
      ActionsCacheUsageHelper.save_repo_cache_usage(@repo, active_caches_size, active_caches_count, owner_id, DateTime.now, true)

      @repo.transfer_ownership_to(@org_for_transfer, actor: @org)
      ActionsCacheUsageHelper.transfer_cache_owner(@repo, @org_for_transfer)

      data1 = ActionsCacheUsage.get_org_cache_usage(@org_for_transfer.id)
      if @repo&.feature_enabled?(:use_merged_cache_usage)
        assert_equal active_caches_size * 2, data1[:total_active_caches_size]
        assert_equal active_caches_count * 2, data1[:total_active_caches_count]
      else
        assert_equal active_caches_size, data1[:total_active_caches_size]
        assert_equal active_caches_count, data1[:total_active_caches_count]
      end

      data2 = ActionsCacheUsage.get_org_cache_usage(@org.id)
      assert_equal 0, data2[:total_active_caches_size]
      assert_equal 0, data2[:total_active_caches_count]
    end
  end
end
