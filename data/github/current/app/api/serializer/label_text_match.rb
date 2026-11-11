# typed: true
# frozen_string_literal: true

module Api::Serializer
  class LabelTextMatch
    include TextMatch

    def self.supported_field_names
      %w(name description).freeze
    end

    def object_type
      "Label"
    end

    def object_url_suffix
      "/repos/#{label.repository.name_with_owner_for_api}/labels/#{label.to_escaped_param}"
    end

    def property
      field_name
    end

    private

    def label
      search_result["_model"]
    end
  end
end
