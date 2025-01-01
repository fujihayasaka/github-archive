# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage < Site::Contentful::Page
  include Site::Contentful::Swp::Page
  include Site::Contentful::Marketing::Resources::AvailableTopics

  sig { returns(JsonLikeType) }
  attr_reader :contentful_response

  sig { params(topic: String, page: T.nilable(String), url: T.nilable(String)).void }
  def initialize(topic:, page:, url:)
    @topic = topic
    @slug = T.let("/resources/articles/#{topic}", String)
    @url = url
    @page = T.let(page.blank? ? 1 : page.to_i, Integer)
    @total_pages = T.let(nil, T.nilable(Integer))
    @limit = T.let(12, Integer)
    @contentful_response = T.let(view_data, JsonLikeType)
  end

  sig { override.returns(String) }
  def cache_key
    "site.swp.resources.category.#{@slug}"
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    @contentful_response = Site::Contentful::Marketing::Resources::ContentTypes::ContainerPage.get_raw_json_full_search_path_for(slug: @slug)
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

  sig { params(flag_filter: T.proc.params(feature_flag: T.nilable(String)).returns(T::Boolean)).void }
  def filter_hidden_pages!(&flag_filter)
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

  sig { void }
  def apply_pagination!
    # set total based on pre-filtered articles so total pages has a correct count
    @total_pages = (@contentful_response["items"].size / @limit.to_f).ceil

    # Paginate
    start_index = (@page - 1) * @limit
    @contentful_response["items"] = @contentful_response["items"][start_index, @limit] || []
  end

  sig { returns(String) }
  def topic_name
    AVAILABLE_TOPICS[@topic] || ALL_TOPICS
  end

  sig { returns(Integer) }
  def page_number
    @page
  end

  sig { returns(T.nilable(Integer)) }
  def total_pages
    @total_pages
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
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
end
