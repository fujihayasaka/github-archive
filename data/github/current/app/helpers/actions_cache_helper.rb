# typed: true
# frozen_string_literal: true

module ActionsCacheHelper
  CACHE_USAGE_WARNING_THRESHOLD = 75

  def cache_sort_menu_options
    [
      ["Recently used", "accessed-desc"],
      ["Least recently used", "accessed-asc"],
      %w[Newest created-desc],
      %w[Oldest created-asc],
      ["Largest size", "size-desc"],
      ["Smallest size", "size-asc"],
    ]
  end

  def org_cache_usage_sort_options
    [
      ["Largest size", "size-desc"],
      ["Smallest size", "size-asc"]
    ]
  end

  def show_cache_usage_warning?(cache_usage)
    ((cache_usage.active_caches_size * 100) / (convert_gb_into_bytes(cache_usage.repository.actions_cache_size_limit))) >= CACHE_USAGE_WARNING_THRESHOLD
  end

  def show_cache_usage_warning_with_limit?(cache_usage, storage_limit_gb)
    return false if storage_limit_gb.nil? || storage_limit_gb.zero?
    ((cache_usage.active_caches_size * 100) / (convert_gb_into_bytes(storage_limit_gb))) >= CACHE_USAGE_WARNING_THRESHOLD
  end

  def show_ghes_cache_size_policy?
    GitHub.enterprise?
  end

  def self.get_effective_storage_limits_for_repositories(organization_id, repository_ids, enterprise_id: nil)
    return {} if repository_ids.empty?

    response = ActionsResults::Twirp.cache_client.get_effective_storage_limit_for_repositories(
      organization_id: organization_id,
      repository_ids: repository_ids,
      enterprise_id: enterprise_id
    )

    if response.call_succeeded?
      # Build a map of repository_id => effective_storage_limit_gib
      # Only repositories with policies will be in the response
      repositories = response.value&.repositories || []
      repositories.each_with_object({}) do |limit_data, hash|
        hash[limit_data.repository_id] = limit_data.effective_storage_limit_gib
      end
    else
      {}
    end
  end

  private

  def convert_gb_into_bytes(size)
    size * 1024 * 1024 * 1024
  end
end
