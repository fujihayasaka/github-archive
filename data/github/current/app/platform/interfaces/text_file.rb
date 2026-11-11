# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module TextFile
      include Platform::Interfaces::Base
      docs_category :meta
      include GitHub::UTF8
      description "Entities that return contents of a text tree entry."

      required_capabilities [:mobile_only_schema_mask, :access_pull_request_diff_graphql_api]

      field :file_lines, [Objects::FileLine, null: true], description: "The lines for this file.", null: true

      def file_lines
        @object.async_file_lines
      end

      field :content_raw, String, description: "The raw content of the markdown.", null: true

      def content_raw
        @object.async_data.then do |data|
          next unless data

          utf8(data)
        end
      end
    end
  end
end
