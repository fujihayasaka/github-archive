# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module TextFile
      include Platform::Interfaces::Base
      description "Entities that return contents of a text tree entry."


      required_capabilities [:mobile_only_schema_mask]

      field :file_lines, [Objects::FileLine, null: true], description: "The lines for this file.", null: true

      def file_lines
        @object.async_file_lines
      end

      field :content_raw, String, description: "The raw content of the markdown.", method: :async_data, null: true
    end
  end
end
