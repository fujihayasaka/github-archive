# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Resources::Pages::CategoryPage < Site::Contentful::Page
  attr_reader :contentful_response
  include Site::Contentful::SWP::Page
  include Site::Contentful::Marketing::Resources::AvailableTopics

  def initialize(topic:, page:, url:)
    @topic = topic
    @slug = "/resources/articles/#{topic}"
    @url = url
    @page = page.blank? ? 1 : page.to_i
    @total_pages = nil
    @limit = 12
    @contentful_response = view_data
  end

  def cache_key
    "site.contentful.marketing.resources.pages.category.#{@slug}/v2"
  end

  def fetch_data_from_contentful
    @contentful_response = Site::Contentful::Marketing::Resources::ContentTypes::ContainerPage.get_raw_json_full_search_path_for(@slug)
    if @contentful_response["includes"].nil?
      return @contentful_response
    end

    new_entry = []

    # Remove unused entries and fields for smaller caching size
    (@contentful_response.dig("includes", "Entry") || []).each do |entry|
      case entry["sys"]["contentType"]["sys"]["id"]
      when "templateResourcesArticle"
        entry["fields"].slice!("title", "excerpt", "heroBackgroundImage")
        new_entry.push(entry)
      when "pageSettings", "backgroundImage", "pageSeo"
        new_entry.push(entry)
      end
    end

    @contentful_response["includes"]["Entry"] = new_entry
    @contentful_response
  end

  def filter_hidden_pages(&flag_filter)
    ids_to_remove = []

    (@contentful_response.dig("includes", "Entry") || []).each do |entry|
      if entry["sys"]["contentType"]["sys"]["id"] == "pageSettings" && entry["fields"].key?("featureFlag")
        feature_flag = entry["fields"]["featureFlag"]
        if flag_filter.call(feature_flag)
          ids_to_remove.push(entry["sys"]["id"])
        end
      end
    end

    @contentful_response.dig("items").reject! do |item|
      settings = item.dig("fields", "settings")
      settings && ids_to_remove.include?(settings.dig("sys", "id"))
    end
  end

  def apply_pagination
    # set total based on pre-filtered articles so total pages has a correct count
    @total_pages = (@contentful_response["items"].size / @limit.to_f).ceil

    # Paginate
    start_index = (@page - 1) * @limit
    @contentful_response["items"] = @contentful_response["items"][start_index, @limit] || []
  end

  def topic_name
    AVAILABLE_TOPICS[@topic] || ALL_TOPICS
  end

  def page_number
    @page
  end

  def total_pages
    @total_pages
  end

  def page_data
    if @page.present? && @page.to_i > 1
      title = "#{topic_name} - Page #{@page}"
      url = "#{T.must(@url)}&page=#{@page}"
      description = "Gallery of articles for the topic #{topic_name} - Page #{@page}"
    else
      title = topic_name
      url = T.must(@url)
      description = "Gallery of articles for the topic #{topic_name}"
    end
    {
      title: title,
      description: description,
      richweb: {
        title: title,
        url: url,
        description: description
      }
    }
  end

  def skip_cache?
    false
  end
end
