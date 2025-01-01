# typed: true
# frozen_string_literal: true

module Api::Serializer
  class RepositoryTextMatch
    include TextMatch

    def self.supported_field_names
      %w(name name.ngram description).freeze
    end

    def object_type
      "Repository"
    end

    def object_url_suffix
      "/repositories/#{repository_id}"
    end

    def property
      case field_name
      when "name", "name.ngram" then "name"
      when "description"        then "description"
      end
    end

    private

    def repository_id
      search_result["_id"]
    end
  end
end
