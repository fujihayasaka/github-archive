# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Resources::Pages::Articles::ShowPage < Site::Contentful::Page
  attr_reader :contentful_response
  include Site::Contentful::SWP::Page

  def initialize(slug:, url:)
    @slug = strip_path("/resources/articles/#{slug}")
    @url = url
    @contentful_response = view_data
  end

  def cache_key
    "site.swp.resources.#{@slug}"
  end

  def fetch_data_from_contentful
    @contentful_response = Site::Contentful::Marketing::Resources::ContentTypes::ContainerPage.get_raw_json_for(@slug)

    return if @contentful_response["items"].empty?

    @contentful_response
  end

  def feature_flag
    page_settings = settings(@contentful_response)

    page_settings.fetch(:feature_flag, nil)
  end

  def title
    @contentful_response.dig("items", 0, "fields", "title")
  end

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
end
