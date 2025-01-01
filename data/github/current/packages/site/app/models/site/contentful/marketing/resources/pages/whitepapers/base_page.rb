# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Resources::Pages::Whitepapers::BasePage < Site::Contentful::Page
  extend T::Helpers
  abstract!

  include Site::Contentful::SWP::Page

  def initialize(slug:)
    @slug = strip_path(slug)
  end

  def cache_key
    "site.swp.resources.pages.whitepapers.#{page_type}.#{@slug}"
  end

  def fetch_data_from_contentful
    contentful_raw_json_response = Site::Contentful::Marketing::Resources::ContentTypes::ContainerPage.get_raw_json_full_search_path_for(@slug)

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
    view_data.fetch(:title)
  end

  def skip_cache?
    false
  end

  private

  sig { abstract.returns(String) }
  def page_type; end

end
