# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::LandingPages::Pages::ShowPage < Site::Contentful::Page
  include Site::Contentful::Swp::Page
  include Site::Contentful::Helpers::LocalizationHelper

  sig { params(slug: String, locale: T.nilable(Symbol)).void }
  def initialize(slug:, locale: :en)
    @slug = T.let(strip_path(slug), String)
    @locale = T.let(contentful_locale(locale || :en), String)
  end

  sig { override.returns(String) }
  def cache_key
    "site.swp.landing_pages.#{@slug}.#{@locale}/v3"
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    contentful_raw_json_response = Site::Contentful::Marketing::LandingPages::ContentTypes::ContainerPage.get_raw_json_for(@slug, @locale)

    # Localize GitHub links if the localization experiment is enabled
    if GitHub.flipper[:marketing_localization_experiment].enabled?
      contentful_raw_json_response = localize_github_links(contentful_raw_json_response, @locale)
    end

    return {} if contentful_raw_json_response.try(:[], "items").blank?

    page_settings = settings(contentful_raw_json_response)
    page_seo = seo(contentful_raw_json_response)
    template_name = extract_template_name_from_contentful(contentful_raw_json_response)

    {
      title: contentful_raw_json_response.dig("items", 0, "fields", "title"),
      contentful_raw_json_response: contentful_raw_json_response,
      template_name: template_name,
      feature_flag: page_settings[:feature_flag],
      use_dark_mode: page_settings[:use_dark_mode],
      global_navbar_style: page_settings[:global_navbar_style],
      revenue_play: page_settings[:revenue_play],
      seo: page_seo
    }
  end

  sig { override.params(data: JsonLikeType).void }
  def validate!(data)
    page = data[:contentful_raw_json_response].dig("items", 0, "fields")

    JSON::Validator.validate!(Site::Contentful::Swp::Schemas::Page.build, page)
    validate_template!(data[:contentful_raw_json_response])
  end

  private

  sig { params(contentful_raw_json_response: T::Hash[T.untyped, T.untyped]).void }
  def validate_template!(contentful_raw_json_response)
    template_name = extract_template_name_from_contentful(contentful_raw_json_response)

    if template_name == "templateContactSalesForm"
      template = (contentful_raw_json_response.dig("includes", "Entry") || []).find do |entry|
        entry.dig("sys", "contentType", "sys", "id") == "templateContactSalesForm"
      end

      JSON::Validator.validate!(Site::Contentful::Marketing::LandingPages::Schemas::ContactSalesTemplate.build, template["fields"])
    end
  end

  sig { params(contentful_raw_json_response: T::Hash[T.untyped, T.untyped]).returns(String) }
  def extract_template_name_from_contentful(contentful_raw_json_response)
    page = contentful_raw_json_response["items"][0]
    return "" if page.nil?

    template_entry_id = page.dig("fields", "template", "sys", "id")

    template = (contentful_raw_json_response.dig("includes", "Entry") || []).find do |entry|
      entry.dig("sys", "id") == template_entry_id
    end

    return "" if template.nil?
    template.dig("sys", "contentType", "sys", "id")
  end
end
