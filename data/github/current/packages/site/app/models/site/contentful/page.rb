# typed: strict
# frozen_string_literal: true

class Site::Contentful::Page
  extend T::Helpers

  include GitHub::Memoizer
  include Site::Contentful::Helpers::CacheHelper
  include Site::Contentful::Helpers::ObservabilityHelper

  abstract!

  sig(:final) { returns(JsonLikeType) }
  memoize def view_data
    GitHub.dogstats.distribution_time("site.contentful.pages.view_data_latency_ms", tags: metric_tags) do
      return fetch_and_report if skip_cache?

      cached_data = page_cached_data

      return cached_data if cached_data.present?

      revalidate
    end
  end

  sig(:final) { returns(JsonLikeType) }
  def revalidate
    new_data = fetch_and_report

    # Always cache when content is valid and is found. When content is not found but we have a previous
    # cache entry, overwrite it to prevent serving stale data for deleted pages.
    save_page_data_in_cache(new_data) if valid?(new_data) && (content_found?(new_data) || cached?)

    new_data
  end

  sig { abstract.returns(JsonLikeType) }
  def fetch_data_from_contentful; end

  # Whether the Contentful response contains actual content. Subclasses should override this
  # when fetch_data_from_contentful returns a non-blank structure for missing pages
  # (e.g., { customer_story: nil } or { items: [] }).
  sig { overridable.params(new_data: JsonLikeType).returns(T::Boolean) }
  def content_found?(new_data)
    new_data.present?
  end

  # Validates the shape or correctness of the Contentful response. Raise if data is invalid
  # to prevent caching malformed content.
  sig { overridable.params(new_data: JsonLikeType).void }
  def validate!(new_data); end

  # Default implementation. Override this method from subclasses to skip the cache.
  sig { overridable.returns(T::Boolean) }
  def skip_cache?
    false
  end

  private

  sig { returns(JsonLikeType) }
  def fetch_and_report
    new_data = GitHub.dogstats.distribution_time("site.contentful.pages.fetch_latency_ms", tags: metric_tags) do
      fetch_data_from_contentful
    end

    unless content_found?(new_data)
      GitHub.dogstats.increment("site.contentful.pages.empty_response", tags: metric_tags)

      GitHub.logger.info(
        "Received empty response from Contentful",
        **log_context,
      )
    end

    new_data
  end

  sig { params(data: JsonLikeType).returns(T::Boolean) }
  def valid?(data)
    return true if data.blank?

    validate!(data)

    true
  rescue StandardError => error
    GitHub.dogstats.increment("site.contentful.pages.data_validation_error", tags: metric_tags)

    GitHub.logger.error(
      "Received invalid data from Contentful",
      "gh.contentful.validation_error": error.message,
      **log_context,
    )

    false
  end
end
