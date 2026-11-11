# typed: strict
# frozen_string_literal: true

# Scaffolded from Site::Contentful::Marketing::LandingPages::Pages::ShowPage
# The long-term goal is to unify the page models but, currently, we need to utilize different Contentful Spaces.
class Site::Contentful::FlexSuite::Pages::ShowPage < Site::Contentful::Page
  include Site::Contentful::Swp::Page
  include Site::Contentful::Helpers::LocalizationHelper

  sig { params(slug: String, locale: T.nilable(Symbol), preview: T::Boolean).void }
  def initialize(slug:, locale: :en, preview: false)
    @slug = T.let(strip_path(slug), String)
    @locale = T.let(contentful_locale(locale || :en), String)
    @preview = T.let(preview, T::Boolean)
  end

  sig { override.returns(Site::Contentful::Page::CacheKey) }
  def cache_key
    Site::Contentful::Page::CacheKey.new(
      base: "site.swp.flex_suite",
      path: @slug,
      locale: @locale,
      version: 1,
      preview: @preview,
    )
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    contentful_raw_json_response = Site::Contentful::FlexSuite::ContentTypes::ContainerPage.get_raw_json_for(slug: @slug, locale: @locale, preview: @preview)

    return {} if contentful_raw_json_response.try(:[], "items").blank?

    contentful_raw_json_response = localize_github_links(contentful_raw_json_response, @locale)

    contentful_raw_json_response = strip_nt_experiences_from_variants(contentful_raw_json_response)

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
      seo: page_seo,
      has_nt_experiences: has_nt_experiences?(contentful_raw_json_response)
    }
  end

  sig { override.params(new_data: JsonLikeType).void }
  def validate!(new_data)
    page = new_data[:contentful_raw_json_response].dig("items", 0, "fields")

    JSON::Validator.validate!(Site::Contentful::Swp::Schemas::Page.build, page)
    validate_template!(new_data[:contentful_raw_json_response])
  end

  sig { override.returns(T::Boolean) }
  def skip_cache?
    @preview
  end

  private

  sig { params(contentful_raw_json_response: T::Hash[T.untyped, T.untyped]).void }
  def validate_template!(contentful_raw_json_response)
    template_name = extract_template_name_from_contentful(contentful_raw_json_response)
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

  sig { params(contentful_raw_json_response: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
  def has_nt_experiences?(contentful_raw_json_response)
    entries = contentful_raw_json_response.dig("includes", "Entry")

    return false unless entries.is_a?(Array)

    entries.any? do |entry|
      fields = entry["fields"]
      next false unless fields.is_a?(Hash)

      fields["nt_experiences"].present?
    end
  end

  sig { params(contentful_raw_json_response: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
  def strip_nt_experiences_from_variants(contentful_raw_json_response)
    entries = contentful_raw_json_response.dig("includes", "Entry")
    return contentful_raw_json_response unless entries.is_a?(Array)

    variant_ids = entries
      .select { |e| e.dig("sys", "contentType", "sys", "id") == "nt_experience" }
      .flat_map { |e| e.dig("fields", "nt_variants") || [] }
      .map { |v| v.dig("sys", "id") }
      .compact
      .to_set

    entries.each do |entry|
      if variant_ids.include?(entry.dig("sys", "id"))
        entry["fields"]&.delete("nt_experiences")
      end
    end

    contentful_raw_json_response
  end
end
