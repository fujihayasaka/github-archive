# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Resources::Pages::Articles::ShowPage < Site::Contentful::Page
  include Site::Contentful::Swp::Page

  sig { returns(JsonLikeType) }
  attr_reader :contentful_response

  sig { params(slug: String, url: T.nilable(String)).void }
  def initialize(slug:, url:)
    @slug = T.let(strip_path("/resources/articles/#{slug}"), String)
    @url = url
    @contentful_response = T.let(view_data, JsonLikeType)
  end

  sig { override.returns(String) }
  def cache_key
    "site.swp.resources.#{@slug}/v2"
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    @contentful_response = Site::Contentful::Marketing::Resources::ContentTypes::ContainerPage.get_raw_json_for(@slug)

    return {} if @contentful_response.try(:[], "items").blank?

    @contentful_response
  end

  sig { returns(T.nilable(String)) }
  def feature_flag
    page_settings = settings(@contentful_response)

    T.cast(page_settings.fetch(:feature_flag, nil), T.nilable(String))
  end

  sig { returns(T.nilable(String)) }
  def title
    @contentful_response.dig("items", 0, "fields", "title")
  end

  sig { returns(JsonLikeType) }
  def page_data
    page_seo = seo(@contentful_response)
    page_settings = settings(@contentful_response)

    {
      description: page_seo.fetch(:description, nil),
      revenue_play: page_settings[:revenue_play],
      richweb: {
        description: page_seo.fetch(:description, nil),
        image: page_seo.fetch(:social_media_image, nil),
        title: @contentful_response.dig("items", 0, "fields", "title"),
        url: T.must(@url)
      }
    }
  end

  sig { override.params(data: JsonLikeType).void }
  def validate!(data)
    page = data.dig("items", 0, "fields")

    template = (data.dig("includes", "Entry") || []).find do |entry|
      entry.dig("sys", "contentType", "sys", "id") == "templateResourcesArticle"
    end

    JSON::Validator.validate!(Site::Contentful::Swp::Schemas::Page.build, page)
    JSON::Validator.validate!(Site::Contentful::Marketing::Resources::Pages::Articles::Schemas::ShowPage.build, template["fields"] || {})
  end
end
