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

  def show_ghes_cache_size_policy?
    GitHub.enterprise?
  end

  private

  def convert_gb_into_bytes(size)
    size * 1024 * 1024 * 1024
  end
end
