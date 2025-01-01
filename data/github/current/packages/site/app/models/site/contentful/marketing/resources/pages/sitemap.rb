# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Resources::Pages::Sitemap < Site::Contentful::Page
  attr_reader :contentful_response
  extend T::Sig
  include Site::Contentful::SWP::Page
  include Site::Contentful::Marketing::Resources::AvailableTopics

  def initialize
    @contentful_response = view_data
  end

  sig { returns(String) }
  def cache_key
    "site.contentful.marketing.sitemap/v2"
  end

  sig { returns(T::Array[T::Hash[Symbol, T::nilable(String)]]) }
  def fetch_data_from_contentful
    response = Site::Contentful::Marketing::Resources::ContentTypes::ContainerPage.get_raw_json_full_search_path_for("/resources/articles")
    @contentful_response = get_url_feature_flag_mappings(response)
  end

  # Internal: Returns a list of feature flags and their associated paths
  #
  # response - The response from the Contentful API
  #
  # Returns an array of hashes with the path and feature flag
  #
  # Example
  #
  #   get_url_feature_flag_mappings(response)
  #   => [{path: "https://www.github.com/resources/articles/ai/foo-bar", feature_flag: "conteful_lp_foo_bar"}]
  sig { params(response: T.untyped).returns(T::Array[T::Hash[Symbol, T::nilable(String)]]) }
  def get_url_feature_flag_mappings(response)
    feature_flag_id_pair_list = map_feature_flag_with_id(response)
    map_feature_flag_with_paths(response, feature_flag_id_pair_list)
  end

  # Internal: Returns a map of contentful ids and their associated feature flags. Maps through the "includes" in the response, which contains the reference "settings" for the container pages. Then checks if the settings contain a feature flag and adds it to the list.
  #
  # response - The response from the Contentful API
  #
  # Returns a mamp with the Contentful id and their feature flags
  #
  # Example
  #
  #   map_feature_flag_with_id(response)
  #   => { "123" => "contentful_lp_foo_bar", "456" => nil }
  sig { params(response: T.untyped).returns(T::Hash[String, T::nilable(String)]) }
  def map_feature_flag_with_id(response)
    feature_flag_id_hash = {}
    # Iterates through the "includes" -> "Entry" in the response to find the page settings. It sets the page setting id as the key and the feature flag as the value, which could be nil since feature flags are optional in contentful
    response.dig("includes", "Entry").each do |entry|
      if entry["sys"]["contentType"]["sys"]["id"] == "pageSettings"
        feature_flag = entry["fields"].key?("featureFlag") ? entry["fields"]["featureFlag"] : nil
        feature_flag_id_hash[entry["sys"]["id"]] = feature_flag
      end
    end

    feature_flag_id_hash
  end

  # Internal: Returns a list of paths and their associated feature flags. Maps through the "items" in the response, which are the container pages. Then maps through the feature_flag_id_pairs to find the associated feature flag for the path.
  #
  # response - The response from the Contentful API
  # feature_flag_id_pairs - The map of Contentful ids and their feature flags
  #
  # Returns an array of hashes with the path and feature flag
  #
  # Example
  #
  #   - `map_feature_flag_with_paths(response, feature_flag_id_pairs)
  #   => [{path: "https://www.github.com/resources/articles/ai/foo-bar", feature_flag: "conteful_lp_foo_bar"}]`
  sig { params(response: T.untyped, feature_flag_id_pairs: T::Hash[String, T::nilable(String)]).returns(T::Array[T::Hash[Symbol, T::nilable(String)]]) }
  def map_feature_flag_with_paths(response, feature_flag_id_pairs)
    feature_flag_path_pairs = []
    response["items"].each do |entry|
      next unless entry["sys"]["contentType"]["sys"]["id"] == "containerPage"

      settings = entry.dig("fields", "settings")
      path = entry["fields"]["path"]

      # Checks if the containerPage id matches the page settings' reference id. If it does, it adds the path and feature flag to the list.
      if settings && feature_flag_id_pairs.key?(settings["sys"]["id"])
        feature_flag_path_pairs.push({ path: "https://www.github.com#{path}", feature_flag: feature_flag_id_pairs[settings["sys"]["id"]] })
      elsif !settings
        # This conditional is here because settings is optional in containerPage on [SWP] Page content model. We set the feature flag to nil if the settings are not present.
        feature_flag_path_pairs.push({ path: "https://www.github.com#{path}", feature_flag: nil })
      end
    end
    feature_flag_path_pairs
  end

  # Internal: Filters out hidden URLs based on the feature flag
  #
  # call_block - The block that determines if the URL should be hidden
  #
  # Returns an array of hashes with the path and feature flag
  #
  # Example
  #
  #   filter_hidden_urls{ |ff| hidden?(ff) }
  sig do
    params(
      call_block: T.proc.params(ff: T.nilable(String)).returns(T::Boolean)
    ).returns(T::Array[T::Hash[Symbol, T.nilable(String)]])
  end
  def filter_hidden_urls(&call_block)
    @contentful_response.reject do |item|
      call_block.call(item[:feature_flag])
    end
  end
end
