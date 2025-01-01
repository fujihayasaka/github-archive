# typed: true
# frozen_string_literal: true

require_relative "custom_rule_helpers"

module ERBLint
  module Linters
    class DoNotEndWithNewline < Linter
      class ConfigSchema < LinterConfig
        property :include_files, accepts: array_of?(String), default: -> { [] }
      end
      self.config_schema = ConfigSchema

      include LinterRegistry
      include ERBLint::Linters::CustomRuleHelpers
      include ERBLint::Linters::ComponentHelpers

      MESSAGE = "This file must not end with a newline"

      def run(processed_source)
        path = processed_source.filename
        return unless path_matches?(path, @config.include_files)

        if processed_source.file_content.end_with?("\n")
          generate_node_offense(self.class, processed_source, processed_source.parser.ast)
        end
      end


      def path_matches?(path, globs)
        globs.any? { |glob| File.fnmatch("#{Dir.pwd}/#{glob}", path) }
      end
    end
  end
end
