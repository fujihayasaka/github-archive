# typed: true
# frozen_string_literal: true

class Site::Contentful::Page
  include Site::Contentful::Helpers::CacheHelper
  include GitHub::Memoizer

  memoize def view_data
    return fetch_data_from_contentful if skip_cache?

    return page_cached_data if page_cached_data.present?

    revalidate
  end

  def revalidate
    fetch_data_from_contentful.tap { |data| save_page_data_in_cache(data) }
  end

  # Override this method from subclasses to get the data to store in the cache.
  def fetch_data_from_contentful
    raise NotImplementedError, "Must be implemented by subclass"
  end

  # Override this method from subclasses to get the cache key.
  def cache_key
    raise NotImplementedError, "Must be implemented by subclass"
  end

  # Default implementation. Override this method from subclasses to skip the cache.
  def skip_cache?
    false
  end
end
