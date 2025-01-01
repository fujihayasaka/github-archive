# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Resources::Pages::Whitepapers::IndexPage < Site::Contentful::Marketing::Resources::Pages::Whitepapers::BasePage
  def initialize
    @slug = "/resources/whitepapers"
    @container_page = nil
  end

  def fetch_data_from_contentful
    # Contains the container_page for Index page plus container_page for all whitepapers
    contentful_raw_json_response = Site::Contentful::Marketing::Resources::ContentTypes::ContainerPage.get_raw_json_full_search_path_for(@slug)

    return nil if contentful_raw_json_response["items"].empty?

    # Extract the container page so we can apply filters to whitepapers
    @container_page = contentful_raw_json_response["items"].find do |item|
      item.dig("fields", "path") == @slug
    end

    return nil if @container_page.nil?

    page_settings = settings(contentful_raw_json_response)
    page_seo = seo(contentful_raw_json_response)

    title = @container_page.dig("fields", "title")

    {
      title: title,
      contentful_raw_json_response: contentful_raw_json_response,
      feature_flag: page_settings[:feature_flag],
      use_dark_mode: page_settings[:use_dark_mode],
      global_navbar_style: page_settings[:global_navbar_style],
      seo: page_seo
    }
  end

  def skip_cache?
    false
  end

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

  def filter_hidden_pages(&flag_filter)
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

  def sort_by_published_date
    view_data[:contentful_raw_json_response]["items"].delete_if { |item| container_page && item["sys"]["id"] == container_page["sys"]["id"] }
    published_date_by_entry_id = {}


    (view_data.dig(:contentful_raw_json_response, "includes", "Entry") || []).each do |entry|
      if entry["sys"]["contentType"]["sys"]["id"] == "templateWhitepaper"
        published_date_by_entry_id[entry["sys"]["id"]] = entry.dig("fields", "publishedDate")
      end
    end

    (view_data.dig(:contentful_raw_json_response, "items") || []).sort_by! do |item|
      published_date_by_entry_id[item.dig("fields", "template", "sys", "id")]
    end.reverse!
    view_data[:contentful_raw_json_response]["items"].unshift(container_page)
  end

  private

  def page_type
    "index"
  end

  def container_page
    return @container_page if @container_page.present?

    # Set @container_page if it hasn't been defined yet (this happens when cache is enabled)
    @container_page = view_data.dig(:contentful_raw_json_response, "items").find do |item|
      item["fields"]["path"] == "/resources/whitepapers"
    end
  end
end
