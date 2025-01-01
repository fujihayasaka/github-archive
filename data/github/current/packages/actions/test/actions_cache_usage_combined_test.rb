# typed: strict
# frozen_string_literal: true

require "test_helper"

class ActionsCacheUsageCombinedTest < GitHub::TestCase
  test "test ActionsCacheUsageCombined with artifact and results cache usage" do
    artifact_cache_usage_created_at = 30.days.ago
    results_cache_usage_created_at = 5.days.ago
    artifact_cache_usage_updated_at = 20.days.ago
    results_cache_usage_updated_at = 1.day.ago
    delta = 0.01

    artifact_cache_usage = ActionsCacheUsage.new(id: 1, repository_id: 1, owner_id: 1, active_caches_size: 1, active_caches_count: 1, is_results_usage: false, created_at: artifact_cache_usage_created_at, updated_at: artifact_cache_usage_updated_at)
    results_cache_usage = ActionsCacheUsage.new(id: 1, repository_id: 1, owner_id: 1, active_caches_size: 1, active_caches_count: 1, is_results_usage: true, created_at: results_cache_usage_created_at, updated_at: results_cache_usage_updated_at)
    cache_usage_combined = ActionsCacheUsageCombined.new([artifact_cache_usage, results_cache_usage])

    refute_nil cache_usage_combined
    assert_equal 1, cache_usage_combined.repository_id
    assert_equal 1, cache_usage_combined.owner_id
    assert_equal 2, cache_usage_combined.active_caches_size
    assert_in_delta cache_usage_combined.created_at.to_f, artifact_cache_usage.created_at.to_f, delta
    assert_in_delta cache_usage_combined.updated_at.to_f, results_cache_usage.updated_at.to_f, delta
    assert_equal 2, cache_usage_combined.active_caches_count
    assert_equal true, cache_usage_combined.has_results?
  end

  test "test ActionsCacheUsageCombined with empty array" do
    cache_usage_combined = ActionsCacheUsageCombined.new([])

    assert_nil cache_usage_combined.repository_id
    assert_nil cache_usage_combined.owner_id
    assert_nil cache_usage_combined.active_caches_size
    assert_nil cache_usage_combined.active_caches_count
    assert_nil cache_usage_combined.created_at
    assert_nil cache_usage_combined.updated_at
    assert_nil cache_usage_combined.has_results?
  end

  test "test ActionsCacheUsageCombined with multiple repository ids" do
    artifact_cache_usage = ActionsCacheUsage.new(id: 1, repository_id: 1, owner_id: 1)
    results_cache_usage = ActionsCacheUsage.new(id: 123, repository_id: 2, owner_id: 1)

    assert_raises_with_message(ArgumentError, "All cache usages should have the same repository_id") do
      ActionsCacheUsageCombined.new([artifact_cache_usage, results_cache_usage])
    end
  end

  test "test ActionsCacheUsageCombined with multiple owner ids" do
    artifact_cache_usage = ActionsCacheUsage.new(id: 1, repository_id: 1, owner_id: 1)
    results_cache_usage = ActionsCacheUsage.new(id: 123, repository_id: 1, owner_id: 1000000000)

    assert_raises_with_message(ArgumentError, "All cache usages should have the same owner_id") do
      ActionsCacheUsageCombined.new([artifact_cache_usage, results_cache_usage])
    end
  end
end
