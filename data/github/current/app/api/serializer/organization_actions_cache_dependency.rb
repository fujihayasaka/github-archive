# typed: true
# frozen_string_literal: true

module Api::Serializer::OrganizationActionsCacheDependency
  def org_cache_usage_by_repo_hash(data, options = {})
    cache_usage = data[:cache_usage]
    caches_usage_hash_data = cache_usage.map do |repo_cache_usage|
      {
        full_name:                       repo_cache_usage.repository.name_with_owner_for_api(use: options[:serialize_login]),
        active_caches_size_in_bytes:     repo_cache_usage.active_caches_size,
        active_caches_count:             repo_cache_usage.active_caches_count
      }
    end
    {
      total_count:                data[:total_count],
      repository_cache_usages:    caches_usage_hash_data
    }
  end

  def org_cache_usage_hash(data, options = {})
    {
      total_active_caches_size_in_bytes:  data[:total_active_caches_size].to_i,
      total_active_caches_count:          data[:total_active_caches_count].to_i
    }
  end
end
