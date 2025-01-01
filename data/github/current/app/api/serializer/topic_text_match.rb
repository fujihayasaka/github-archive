# typed: true
# frozen_string_literal: true

module Api::Serializer
  class TopicTextMatch
    include TextMatch

    def self.supported_field_names
      %w(name name.ngram display_name short_description description aliases).freeze
    end

    def object_type
      "Topic"
    end

    def object_url_suffix
      "/search/repositories?q=topic:#{topic.name}"
    end

    def property
      case field_name
      when "name", "name.ngram" then "name"
      else
        field_name
      end
    end

    private

    def topic
      search_result["_model"]
    end
  end
end
