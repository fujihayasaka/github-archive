# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Solutions::Pages::BasePage < Site::Contentful::Page
  attr_reader :contentful_response
  include Site::Contentful::SWP::Page

  def initialize(slug:)
    @slug = slug
  end

  def cache_key
    "site.contentful.marketing.solutions.pages.#{page_type}.#{@slug}/v2"
  end

  def fetch_data_from_contentful
    contentful_raw_json_response = Site::Contentful::Marketing::Solutions::ContentTypes::ContainerPage.get_raw_json_for(@slug)
    return nil if contentful_raw_json_response["items"].empty?

    page_settings = settings(contentful_raw_json_response)
    page_seo = seo(contentful_raw_json_response)

    {
      title: contentful_raw_json_response.dig("items", 0, "fields", "title"),
      contentful_raw_json_response: contentful_raw_json_response,
      feature_flag: page_settings[:feature_flag],
      use_dark_mode: page_settings[:use_dark_mode],
      global_navbar_style: page_settings[:global_navbar_style],
      seo: page_seo
    }
  end

  def feature_flag
    page_settings = settings(view_data)
    page_settings.fetch(:feature_flag, nil)
  end

  def title
    view_data.dig("items", 0, "fields", "title")
  end

  def skip_cache?
    false
  end

  private

  def page_type
    raise NotImplementedError, "You must implement the page_type method"
  end
end
