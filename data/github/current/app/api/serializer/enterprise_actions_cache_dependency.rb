# typed: true
# frozen_string_literal: true

module Api::Serializer::EnterpriseActionsCacheDependency
  def enterprise_cache_usage_hash(data, options = {})
    {
      total_active_caches_count:          data[:total_active_caches_count].to_i,
      total_active_caches_size_in_bytes:  data[:total_active_caches_size].to_i
    }
  end

  def enterprise_cache_usage_policy_hash(data, options = {})
    {
      repo_cache_size_limit_in_gb:     data[:repo_cache_size_limit_in_gb].to_i,
      max_repo_cache_size_limit_in_gb:       data[:max_repo_cache_size_limit_in_gb].to_i
    }
  end
end
