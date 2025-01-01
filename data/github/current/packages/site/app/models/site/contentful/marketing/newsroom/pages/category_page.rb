# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Newsroom::Pages::CategoryPage < Site::Contentful::Marketing::Newsroom::Pages::BasePage
  sig { params(page: T.untyped).void }
  def initialize(page: nil)
    @page = T.let(page.blank? ? 1 : page.to_i, Integer)
    @limit = T.let(15, Integer)
    @slug = T.let("/newsroom/press-releases", String)
    @container_page = T.let(nil, T.untyped)
    @total_pages = T.let(nil, T.nilable(Integer))
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    # Contains the container_page for Category page plus container_page for all press releases
    contentful_raw_json_response = Site::Contentful::Marketing::Newsroom::ContentTypes::ContainerPage.get_raw_json_full_search_path_for(@slug)

    return {} if contentful_raw_json_response.try(:[], "items").blank?

    # Extract the container page so we can apply filters and pagination to press releases
    @container_page = contentful_raw_json_response["items"].find do |item|
      item.dig("fields", "path") == @slug
    end

    return {} if @container_page.nil?

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
  def apply_pagination!
    view_data[:contentful_raw_json_response]["items"].delete_if { |item| container_page && item["sys"]["id"] == container_page["sys"]["id"] }
    sort_by_published_date!

    @total_pages = (view_data[:contentful_raw_json_response]["items"].size / @limit.to_f).ceil

    # Paginate
    start_index = (@page - 1) * @limit
    view_data[:contentful_raw_json_response]["items"] = view_data.dig(:contentful_raw_json_response, "items")[start_index, @limit] || []
    view_data[:contentful_raw_json_response]["items"].unshift(container_page)
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
      use_dark_mode: maybe_page_settings.try(:dig, "fields", "colorMode") == "dark",
      global_navbar_style: (maybe_global_navbar_style.blank? || maybe_global_navbar_style == "default") ? nil : maybe_global_navbar_style
    }
  end

  sig { params(contentful_raw_json_response: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, T.nilable(T.any(TrueClass, FalseClass, String))]) }
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

  sig { returns(Integer) }
  def page_number
    @page
  end

  sig { returns(Integer) }
  def total_pages
    raise TypeError, "@total_pages is nil, expected an Integer" if @total_pages.nil?

    @total_pages
  end

  protected

  sig { override.returns(T.untyped) }
  def page_template
    Site::Contentful::Marketing::Newsroom::Schemas::CategoryPage.build
  end

  sig { override.returns(String) }
  def page_type
    "category"
  end

  private

  sig { returns(T.untyped) }
  def container_page
    return @container_page if @container_page.present?

    # Set @container_page if it hasn't been defined yet (this happens when cache is enabled)
    @container_page = view_data.dig(:contentful_raw_json_response, "items").find do |item|
      item["fields"]["path"] == "/newsroom/press-releases"
    end
  end

  sig { void }
  def sort_by_published_date!
    published_date_by_entry_id = {}

    (view_data.dig(:contentful_raw_json_response, "includes", "Entry") || []).each do |entry|
      if entry["sys"]["contentType"]["sys"]["id"] == "templateResourcesArticle"
        published_date_by_entry_id[entry["sys"]["id"]] = entry.dig("fields", "publishedDate")
      end
    end

    (view_data.dig(:contentful_raw_json_response, "items") || []).sort_by! do |item|
      published_date_by_entry_id[item.dig("fields", "template", "sys", "id")]
    end.reverse!
  end
end
