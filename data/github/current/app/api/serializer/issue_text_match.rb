# typed: true
# frozen_string_literal: true

module Api::Serializer
  class IssueTextMatch
    include TextMatch

    def self.supported_field_names
      %w(title body).freeze
    end

    def object_type
      "Issue"
    end

    def object_url_suffix
      "/repositories/#{issue.repository_id}/issues/#{issue.number}"
    end

    def property
      field_name
    end

    private

    def issue
      search_result["_model"]
    end
  end
end
