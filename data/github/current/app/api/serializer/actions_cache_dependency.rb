# typed: true
# frozen_string_literal: true

module Api::Serializer::ActionsCacheDependency
  def cache_usage_hash(data, options = {})
    cache_usage = data[:cache_usage]
    {
      full_name:                      data[:repository].name_with_owner_for_api(use: options[:serialize_login]),
      active_caches_size_in_bytes:    cache_usage&.active_caches_size.to_i,
      active_caches_count:            cache_usage&.active_caches_count.to_i
    }
  end

  def cache_usage_policy_hash(data, options = {})
    cache_usage_limit = data[:repo_cache_size_limit_in_gb]
    {
      repo_cache_size_limit_in_gb:         cache_usage_limit
    }
  end

  def cache_hash(data, options = {})
    {
      id: data.id,
      ref: data.scope,
      key: data.key,
      version: data.version,
      last_accessed_at: data.lastAccessed,
      created_at: data.created,
      size_in_bytes: data.size
    }
  end

  def caches_hash(data, options = {})
    actions_caches_result = data[:actions_caches]
    {
      total_count:  actions_caches_result[:total_count],
      actions_caches: actions_caches_result[:actions_caches].map { |cache| cache_hash(cache, options) }
    }
  end

  def cache_storage_limit_hash(data, options = {})
    {
      max_cache_size_gb:     data[:max_cache_size_gb].to_i,
    }
  end

  def cache_retention_limit_hash(data, options = {})
    {
      max_cache_retention_days:     data[:retain_for].to_i,
    }
  end
end
