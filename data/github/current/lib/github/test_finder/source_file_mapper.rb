# typed: true
# frozen_string_literal: true

module GitHub
  module TestFinder
    class SourceFileMapper
      attr_reader :mappings
      def initialize
        @mappings = build_mappings
      end

      def test_path_for(path)
        mappings.each do |pattern, test_path_template|
          path.match(pattern) do |m|
            return test_path_template % m.captures
          end
        end

        nil
      end

      private

      def build_mappings
        config_path = Rails.root.join("test/source_to_test.yml")
        data = YAML.load(File.read(config_path))

        data.to_h do |string_pattern, test_path_template|
          pattern = Regexp.new(string_pattern[1..-2])
          [pattern, test_path_template]
        end
      end
    end
  end
end
