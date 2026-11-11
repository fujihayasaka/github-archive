# typed: strict
# frozen_string_literal: true

require "net/http"
require "json"

class Site::Contentful::Marketing::Resources::Taxonomies::BaseTaxonomy
  extend T::Helpers
  include GitHub::Memoizer
  include Site::Contentful::Helpers::CacheHelper

  abstract!

  BASE_URL = "https://cdn.contentful.com"

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def items
    cached_data = page_cached_data
    return cached_data[:items] || [] if cached_data.present?

    revalidate
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def revalidate
    fetched_items = fetch_items
    save_page_data_in_cache({ items: fetched_items }) if fetched_items.present?
    fetched_items
  end

  sig { abstract.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def fetch_items; end

  protected

  sig { params(uri: URI::Generic).returns(T.nilable(T::Hash[String, T.untyped])) }
  def fetch_from_api(uri)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{GitHub.contentful_marketing_delivery_token}"
    request["Content-Type"] = "application/json"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    if response.code == "200"
      JSON.parse(response.body)
    else
      GitHub.dogstats.increment("site.contentful.taxonomies.api_failures", tags: ["status:#{response.code}"])
      GitHub.logger.error(
        "Failed to fetch from Contentful",
        "gh.contentful.status_code": response.code,
        "gh.contentful.response_body": response.body,
        "gh.contentful.uri": uri.to_s
      )
      raise "Failed to fetch from Contentful: #{response.code}" if Rails.env.development?
      nil
    end
  end

  sig { returns(String) }
  def space_id
    GitHub.contentful_marketing_space_id
  end

  sig { returns(String) }
  def environment
    GitHub.contentful_marketing_environment
  end

  sig { params(item: T::Hash[String, T.untyped], field_name: String).returns(T.nilable(String)) }
  def extract_localized_field(item, field_name)
    field_value = item.dig(field_name)
    return nil if field_value.blank?

    # Contentful returns localized fields as nested objects
    # e.g., { "en-US": "value" }
    if field_value.is_a?(Hash)
      field_value.values.first
    else
      field_value
    end
  end
end
