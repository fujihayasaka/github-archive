# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Resources::Pages::Whitepapers::IndexPage < Site::Contentful::Marketing::Resources::Pages::Whitepapers::BasePage
  sig { params(page: T.nilable(String), content_type: T.nilable(String), topics: T.nilable(String), locale: T.nilable(Symbol)).void }
  def initialize(page: nil, content_type: nil, topics: nil, locale: nil)
    @page = T.let(page.blank? ? 1 : page.to_i, Integer)
    @limit = T.let(12, Integer)
    @slug = T.let("/resources/whitepapers", String)
    @container_page = T.let(nil, T.untyped)
    @content_types = T.let((content_type || "").split(",").map(&:strip), T::Array[String])
    @topics = T.let((topics || "").split(",").map(&:strip), T::Array[String])
    @total_pages = T.let(nil, T.nilable(Integer))
    @locale = T.let(contentful_locale(locale || :en), String)

    super(slug: @slug, locale: locale || :en)
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    # Contains the container_page for Index page plus container_page for all whitepapers
    contentful_raw_json_response = Site::Contentful::Marketing::Resources::ContentTypes::ContainerPage.get_raw_json_full_search_path_for(slug: @slug, locale: @locale)

    return {} if contentful_raw_json_response.try(:[], "items").blank?

    # Localize GitHub links if the localization experiment is enabled
    if FeatureFlag.vexi.enabled?(:marketing_localization_experiment, default: false)
      contentful_raw_json_response = localize_github_links(contentful_raw_json_response, @locale)
    end

    # Extract the container page so we can apply filters to whitepapers
    @container_page = contentful_raw_json_response["items"].find do |item|
      item.dig("fields", "path") == @slug
    end

    return {} if @container_page.nil?

    filtered_entries = []

    # Remove unused entries and fields for smaller caching size
    (contentful_raw_json_response.dig("includes", "Entry") || []).each do |entry|
      case entry.dig("sys", "contentType", "sys", "id")
      when "templateWhitepaper"
        entry["fields"].slice!("heading", "contentType", "featuredImage", "excerpt", "publishedDate", "topics")
        filtered_entries.push(entry)
      when "pageSettings", "pageSeo", "templateWhitepaperIndex"
        filtered_entries.push(entry)
      end
    end

    contentful_raw_json_response["includes"]["Entry"] = filtered_entries

    page_settings = settings(contentful_raw_json_response)
    page_seo = seo(contentful_raw_json_response)

    title = @container_page.dig("fields", "title")
    title += " - Page #{@page}" if @page.to_i > 1

    {
      title: title,
      contentful_raw_json_response: contentful_raw_json_response,
      feature_flag: page_settings[:feature_flag],
      use_dark_mode: page_settings[:use_dark_mode],
      global_navbar_style: page_settings[:global_navbar_style],
      seo: page_seo
    }
  end

  sig { params(contentful_raw_json_response: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, T.nilable(T.any(TrueClass, FalseClass, String))]) }
  def settings(contentful_raw_json_response)
    settings_id = container_page.dig("fields", "settings", "sys", "id")

    maybe_page_settings = (contentful_raw_json_response.dig("includes", "Entry") || []).find do |entry|
      entry.dig("sys", "id") == settings_id
    end

    maybe_global_navbar_style = maybe_page_settings.try(:dig, "fields", "globalNavbarStyle")

    {
      feature_flag: maybe_page_settings.try(:dig, "fields", "featureFlag"),
      use_dark_mode: true,
      global_navbar_style: (maybe_global_navbar_style.blank? || maybe_global_navbar_style == "default") ? nil : maybe_global_navbar_style
    }
  end

  sig { params(contentful_raw_json_response: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, T.nilable(String)]) }
  def seo(contentful_raw_json_response)
    seo_id = container_page.dig("fields", "seo", "sys", "id")

    maybe_page_seo = (contentful_raw_json_response.dig("includes", "Entry") || []).find do |entry|
      entry.dig("sys", "id") == seo_id
    end

    return {} if maybe_page_seo.nil?

    maybe_social_media_image = (contentful_raw_json_response.dig("includes", "Asset") || []).find do |asset|
      asset.dig("sys", "id") == maybe_page_seo.dig("fields", "socialMediaImage").try(:dig, "sys", "id")
    end

    maybe_social_media_image_url = maybe_social_media_image.try(:dig, "fields", "file", "url")

    description = maybe_page_seo.dig("fields", "description")
    description += " - Page #{@page}" if @page.present? && @page.to_i > 1

    {
      description: description,
      social_media_image: maybe_social_media_image_url.nil? ? nil : "https:#{maybe_social_media_image_url}"
    }
  end

  sig { params(flag_filter: T.proc.params(feature_flag: T.nilable(String)).returns(T::Boolean)).void }
  def filter_hidden_pages!(&flag_filter)
    ids_to_remove = []

    (view_data.dig(:contentful_raw_json_response, "includes", "Entry") || []).each do |entry|
      if entry["sys"]["contentType"]["sys"]["id"] == "pageSettings" && entry["fields"].key?("featureFlag")
        feature_flag = entry["fields"]["featureFlag"]
        if flag_filter.call(feature_flag)
          ids_to_remove.push(entry["sys"]["id"])
        end
      end
    end

    view_data.dig(:contentful_raw_json_response, "items").reject! do |item|
      settings = item.dig("fields", "settings")
      settings && ids_to_remove.include?(settings.dig("sys", "id"))
    end
  end

  sig { void }
  def apply_filters!
    return if @content_types.empty? && @topics.empty?

    ids_to_remove = []

    # Collect IDs to remove
    (view_data.dig(:contentful_raw_json_response, "includes", "Entry") || []).each do |entry|
      next unless entry.dig("sys", "contentType", "sys", "id") == "templateWhitepaper"

      entry_content_type = entry.dig("fields", "contentType").to_s.downcase
      # Convert topics to kebab for comparison
      entry_topics = entry.dig("fields", "topics").to_a.map { |topic| topic.downcase.gsub(/\s+|-/, "-") }


      unless (@content_types.empty? || @content_types.include?(entry_content_type)) &&
        (@topics.empty? || (@topics & entry_topics).any?)
        ids_to_remove.push(entry["sys"]["id"])
      end
    end

    # Remove items with matching settings IDs
    view_data.dig(:contentful_raw_json_response, "items").reject! do |item|
      template = item.dig("fields", "template")
      template && ids_to_remove.include?(template.dig("sys", "id"))
    end
  end

  sig { void }
  def apply_pagination!
    view_data[:contentful_raw_json_response]["items"].delete_if { |item| container_page && item["sys"]["id"] == container_page["sys"]["id"] }
    sort_by_published_date!

    @total_pages = (view_data[:contentful_raw_json_response]["items"].size / @limit.to_f).ceil

    # Paginate
    start_index = (@page - 1) * @limit
    view_data[:contentful_raw_json_response]["items"] = view_data.dig(:contentful_raw_json_response, "items")[start_index, @limit] || []
    view_data[:contentful_raw_json_response]["items"].unshift(container_page)
  end

  sig { returns(Integer) }
  def page_number
    @page
  end

  sig { returns(Integer) }
  def total_pages
    raise TypeError, "@total_pages is nil, expected an Integer" if @total_pages.nil?

    @total_pages
  end

  sig { returns(T::Array[String]) }
  def content_types
    @content_types
  end

  sig { returns(T::Array[String]) }
  def topics
    @topics
  end

  protected

  sig { override.returns(String) }
  def page_type
    "index"
  end

  private

  sig { returns(T.untyped) }
  def container_page
    return @container_page if @container_page.present?

    # Set @container_page if it hasn't been defined yet (this happens when cache is enabled)
    @container_page = view_data.dig(:contentful_raw_json_response, "items").find do |item|
      item["fields"]["path"] == "/resources/whitepapers"
    end
  end

  sig { void }
  def sort_by_published_date!
    published_date_by_entry_id = {}

    (view_data.dig(:contentful_raw_json_response, "includes", "Entry") || []).each do |entry|
      if entry["sys"]["contentType"]["sys"]["id"] == "templateWhitepaper"
        published_date_by_entry_id[entry["sys"]["id"]] = entry.dig("fields", "publishedDate")
      end
    end

    (view_data.dig(:contentful_raw_json_response, "items") || []).sort_by! do |item|
      published_date_by_entry_id[item.dig("fields", "template", "sys", "id")]
    end.reverse!
  end
end
