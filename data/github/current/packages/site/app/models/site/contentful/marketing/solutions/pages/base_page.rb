# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Solutions::Pages::BasePage < Site::Contentful::Page
  include Site::Contentful::Swp::Page

  abstract!

  sig { params(slug: String).void }
  def initialize(slug:)
    @slug = T.let(strip_path(slug), String)
  end

  sig { override.returns(String) }
  def cache_key
    "site.contentful.marketing.solutions.pages.#{page_type}.#{@slug}/v3"
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    contentful_raw_json_response = Site::Contentful::Marketing::Solutions::ContentTypes::ContainerPage.get_raw_json_for(@slug)

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

  sig { returns(T.nilable(T::Boolean)) }
  def flex_template?
    (view_data[:contentful_raw_json_response].dig("includes", "Entry") || []).any? do |entry|
      entry.dig("sys", "contentType", "sys", "id") == "templateFlex"
    end
  end

  sig { returns(T.nilable(String)) }
  def feature_flag
    page_settings = settings(view_data)

    T.cast(page_settings.fetch(:feature_flag, nil), T.nilable(String))
  end

  sig { returns(T.nilable(String)) }
  def title
    view_data.dig("items", 0, "fields", "title")
  end

  protected

  sig { abstract.returns(String) }
  def page_type; end
end
