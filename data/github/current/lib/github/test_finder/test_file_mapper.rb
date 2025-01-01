# typed: true
# frozen_string_literal: true

module GitHub
  module TestFinder
    class TestFileMapper
      attr_reader :mappings
      def initialize
        @mappings = build_mappings
      end

      def test_path_for(path)
        mappings.each do |pattern, source_path_template|
          path.match(pattern) do |m|
            return source_path_template % m.captures
          end
        end

        nil
      end

      private

      def build_mappings
        config_path = Rails.root.join("test/test_to_source.yml")
        data = YAML.load(File.read(config_path))

        data.to_h do |string_pattern, source_path_template|
          pattern = Regexp.new(string_pattern[1..-2])
          [pattern, source_path_template]
        end
      end
    end
  end
end
