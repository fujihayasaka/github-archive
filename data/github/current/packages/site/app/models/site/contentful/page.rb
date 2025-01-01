# typed: strict
# frozen_string_literal: true

class Site::Contentful::Page
  extend T::Helpers

  include GitHub::Memoizer
  include Site::Contentful::Helpers::CacheHelper

  abstract!

  sig(:final) { returns(JsonLikeType) }
  memoize def view_data
    return fetch_data_from_contentful if skip_cache?

    cached_data = page_cached_data

    return cached_data if cached_data.present?

    revalidate
  end

  sig(:final) { returns(JsonLikeType) }
  def revalidate
    fetch_data_from_contentful.tap { |data| save_page_data_in_cache(data) if valid?(data) }
  end

  sig { abstract.returns(JsonLikeType) }
  def fetch_data_from_contentful; end

  sig { abstract.returns(String) }
  def cache_key; end

  # Override this method from subclasses to determine if the data should be cached.
  sig { overridable.params(new_data: JsonLikeType).void }
  def validate!(new_data); end

  # Default implementation. Override this method from subclasses to skip the cache.
  sig { overridable.returns(T::Boolean) }
  def skip_cache?
    false
  end

  private

  sig { params(data: JsonLikeType).returns(T::Boolean) }
  def valid?(data)
    return true if data.blank?

    validate!(data)

    true
  rescue StandardError => error # rubocop:disable Lint/RescueException
    GitHub.dogstats.increment("site.contentful.pages.data_validation_error")

    GitHub.logger.error(
      "Received invalid data from Contentful",
      "code.namespace": self.class.name,
      "gh.contentful.cache_key": cache_key,
      "gh.contentful.validation_error": error.message,
    )

    false
  end
end
