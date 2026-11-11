# typed: true
# frozen_string_literal: true

module Search
  class DotcomTopicResultView < TopicResultView
    attr_reader :short_description, :name, :repository_count, :logo_url

    # Create a new DotcomTopicResultView from a `page` document hash returned from
    # the Dotcom API
    #
    # dotcom_hash - Document Hash returned by Dotcom API
    def initialize(dotcom_hash)
      @name = dotcom_hash["name"]
      @display_name = dotcom_hash["display_name"]
      @short_description = dotcom_hash["short_description"]
      @description = dotcom_hash["description"]
      @created_by = dotcom_hash["created_by"]
      @released = dotcom_hash["released"]
      @featured = dotcom_hash["featured"]
      @curated = dotcom_hash["curated"]
      @aliases = extract_name(dotcom_hash["aliases"])
      @related = extract_name(dotcom_hash["related"])
      @repository_count = dotcom_hash["repository_count"]
      @logo_url   = dotcom_hash["logo_url"]
      @created_at = Time.parse(dotcom_hash["created_at"])
      @updated_at = Time.parse(dotcom_hash["updated_at"])
      @highlights = Search::DotcomHighlights.highlights(dotcom_hash["text_matches"])
    end

    def url
      "#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_host_name}/topics/#{name}"
    end

    def extract_name(topic_relations)
      topic_relations.map do |relation|
        relation["topic_relation"]["name"] if relation && relation["topic_relation"]
      end
    end
  end
end
