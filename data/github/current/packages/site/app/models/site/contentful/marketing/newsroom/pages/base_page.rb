# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Newsroom::Pages::BasePage < Site::Contentful::Page
  include Site::Contentful::Swp::Page
  extend T::Helpers

  abstract!

  sig { params(slug: String).void }
  def initialize(slug:)
    @slug = T.let(strip_path(slug), String)
  end

  sig { override.returns(String) }
  def cache_key
    "site.contentful.marketing.newsroom.pages.#{page_type}.#{@slug}/v2"
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    contentful_raw_json_response = Site::Contentful::Marketing::Newsroom::ContentTypes::ContainerPage.get_raw_json_for(@slug)

    return {} if contentful_raw_json_response.try(:[], "items").blank?

    page_settings = settings(contentful_raw_json_response)
    page_seo = seo(contentful_raw_json_response)

    {
      title: contentful_raw_json_response.dig("items", 0, "fields", "title"),
      contentful_raw_json_response: contentful_raw_json_response,
      feature_flag: page_settings[:feature_flag],
      use_dark_mode: page_settings[:use_dark_mode],
      global_navbar_style: page_settings[:global_navbar_style],
      revenue_play: page_settings[:revenue_play],
      seo: page_seo
    }
  end

  sig { returns(T.nilable(String)) }
  def feature_flag
    page_settings = settings(view_data)
    T.cast(page_settings.fetch(:feature_flag, nil), T.nilable(String))
  end

  sig { returns(T.nilable(String)) }
  def title
    view_data.fetch(:title)
  end

  # Since we are retrieving raw json, and not the tree structure from Contentful, this only validates top-level structure of the template.
  # This means references will not be checked. e.g. We'll check that hero is an object, but not that the linked asset exists.
  sig { override.params(data: JsonLikeType).void }
  def validate!(data)
    page = data[:contentful_raw_json_response].dig("items", 0, "fields")

    template = (data[:contentful_raw_json_response].dig("includes", "Entry") || []).find do |entry|
      entry.dig("sys", "contentType", "sys", "id") == page_template[:title]
    end

    JSON::Validator.validate!(Site::Contentful::Swp::Schemas::Page.build, page)
    JSON::Validator.validate!(page_template, template["fields"] || {})
  end

  protected

  sig { abstract.returns(T.untyped) }
  def page_template; end

  sig { abstract.returns(String) }
  def page_type; end
end
