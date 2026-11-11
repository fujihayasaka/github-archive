# typed: true
# frozen_string_literal: true

module Api::Serializer
  class CommitMessageTextMatch
    include TextMatch

    def self.supported_field_names
      %w(message).freeze
    end

    def object_type
      "CommitMessage"
    end

    def object_url_suffix
      "/repos/#{search_result["_model"].owner.login_for_api}/#{search_result["_model"].name}/commits/#{search_result["_source"]["hash"]}"
    end

    def property
      field_name
    end
  end
end
