# typed: true
# frozen_string_literal: true

module CommandPalette
  module Results
    class FileResult
      attr_reader :object, :base_file_path, :paths

      def initialize(object:, base_file_path:, paths:)
        @object = object
        @base_file_path = base_file_path
        @paths = paths
      end

      def as_json(*)
        {
          object: object.as_json(dangerously_allow_all_keys: true),
          base_file_path: base_file_path,
          paths: paths,
        }.reject { |_key, value| value.nil? }
      end
    end
  end
end
