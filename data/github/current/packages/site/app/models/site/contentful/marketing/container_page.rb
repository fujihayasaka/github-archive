# typed: strict
# frozen_string_literal: true

require "contentful"

# Model representation of the [SWP] Page content model
class Site::Contentful::Marketing::ContainerPage < Site::Contentful::Page
  include GitHub::Memoizer
  include Site::Contentful::Marketing::Client
  include Site::Contentful::Swp::Page::Options
  include Site::Contentful::Swp::Page::Traversal
  include Site::Contentful::Helpers::AsyncRevalidation

  NUMBER_OF_LINKED_ENTRIES = 10

  sig { returns(String) }
  def content_type
    "containerPage"
  end

  sig { override.returns(String) }
  attr_reader :url

  sig do
    params(
      path: String,
      locale: String,
      url: String,
      preview: T::Boolean,
    ).void
  end
  def initialize(path:, locale:, url:, preview: false)
    @path = path
    @locale = locale
    @url = url
    @preview = preview
  end

  sig { returns(String) }
  def title
    get_field("title") || ""
  end

  sig { returns(T::Boolean) }
  def missing?
    view_data.blank? || items.empty?
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  memoize def template
    get_field("template") || {}
  end

  # This assumes that the underlying template has a "form" field. While this has been the convention, it's not
  # currently enforced by the content model. This is something to be aware of when using this method.
  sig { returns(T::Boolean) }
  def has_form?
    template.dig("fields", "form").present?
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def serialize
    { path: @path, locale: @locale, url: @url }
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    return {} if raw_data.nil? || raw_data&.fetch("items", []).empty?
    raw_data
  end

  sig { override.returns(T::Boolean) }
  def preview?
    @preview
  end

  sig { override.returns(T::Boolean) }
  def skip_cache?
    preview?
  end

  sig { override.returns(Site::Contentful::Page::CacheKey) }
  def cache_key
    Site::Contentful::Page::CacheKey.new(
      base: "swp.container_page",
      locale: @locale,
      path: @path,
      version: 1,
      preview: preview?,
    )
  end

  private

  sig { returns(T.untyped) }
  memoize def raw_data
    params = {
      content_type:,
      "fields.path": @path,
      include:,
      locale: @locale,
    }

    self.class.contentful_raw_request(params, preview: preview?)
  end

  sig { overridable.returns(Integer) }
  def include
    10
  end
end
