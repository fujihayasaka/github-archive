# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Resources::Pages::Whitepapers::BasePage < Site::Contentful::Page
  extend T::Helpers
  include Site::Contentful::Swp::Page
  include Site::Contentful::Helpers::LocalizationHelper

  abstract!

  sig { params(slug: String, locale: T.nilable(Symbol)).void }
  def initialize(slug:, locale: :en)
    @slug = T.let(strip_path(slug), String)
    @locale = T.let(contentful_locale(locale || :en), String)
  end

  sig { override.returns(String) }
  def cache_key
    "site.swp.resources.pages.whitepapers.#{page_type}.#{@slug}.#{@locale}/v3"
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    contentful_raw_json_response = Site::Contentful::Marketing::Resources::ContentTypes::ContainerPage.get_raw_json_for(slug: @slug, locale: @locale)

    # Localize GitHub links if the localization experiment is enabled
    if FeatureFlag.vexi.enabled?(:marketing_localization_experiment, default: false)
      contentful_raw_json_response = localize_github_links(contentful_raw_json_response, @locale)
    end

    return {} if contentful_raw_json_response.try(:[], "items").blank?

    page_settings = settings(contentful_raw_json_response)
    page_seo = seo(contentful_raw_json_response)

    {
      title: contentful_raw_json_response.dig("items", 0, "fields", "title"),
      contentful_raw_json_response: contentful_raw_json_response,
      feature_flag: page_settings[:feature_flag],
      use_dark_mode: true,
      global_navbar_style: page_settings[:global_navbar_style],
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

  protected

  sig { abstract.returns(String) }
  def page_type; end
end
