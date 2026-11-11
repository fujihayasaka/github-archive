# typed: strict
# frozen_string_literal: true

require "yaml"

module TriageAgent
  module Frontmatter
    # Generic utilities for extracting and working with YAML frontmatter
    # in markdown documents. Shared so that multiple parsers can reuse
    # the same low-level extraction logic.
    module Parser
      # Wildcard value that means "all" when used in allowed/blocked lists
      # or in the top-level allowed-actions array.
      WILDCARD = T.let("*", String)

      # Extracts the YAML frontmatter hash from a markdown document that
      # starts with `---`. Returns nil if no frontmatter is found.
      sig { params(content: T.nilable(String)).returns(T.nilable(T::Hash[String, T.untyped])) }
      def self.extract_frontmatter(content)
        return nil if content.blank?

        # Frontmatter must start at the very beginning of the file with ---
        # and end with --- on its own line. We use \A and \z-family anchors
        # to avoid regex anchor bypass issues with ^ and $.
        match = content.match(/\A---\s*\n(.+?)\n---\s*(\n|\z)/m)
        return nil unless match

        # YAML 1.1 (used by Psych) treats bare `on`, `off`, `yes`, `no`
        # as booleans. Quote only unindented (column-0) keys so we don't
        # accidentally rewrite values inside nested mappings or block scalars.
        #
        # NOTE: `^` is intentional here — we need to match the start of
        # each line in the multi-line YAML string, not the start of the
        # entire string (`\A` would only match the first line).
        yaml_str = T.must(match[1])
          .gsub(/^(on|off|yes|no)(\s*:)/i) { "\"#{$1}\"#{$2}" }

        parsed = YAML.safe_load(yaml_str)
        return nil unless parsed.is_a?(Hash)

        parsed
      end

      # Coerces a value to an array of strings, or nil if the value is
      # not an array-like collection. Handles YAML arrays and single strings.
      sig { params(value: T.untyped).returns(T.nilable(T::Array[String])) }
      def self.coerce_string_array(value)
        case value
        when Array
          value.map(&:to_s)
        when String
          [value]
        else
          nil
        end
      end

      # Extracts the markdown body from a document, stripping any YAML
      # frontmatter. Returns the original content if no frontmatter is
      # found, or nil for blank input.
      sig { params(content: T.nilable(String)).returns(T.nilable(String)) }
      def self.extract_body(content)
        return nil if content.blank?

        content.sub(/\A---\s*\n.*?\n---\s*(\n|\z)/m, "")
      end

      # Returns true when the value is an array containing only the
      # wildcard string "*".
      sig { params(value: T.untyped).returns(T::Boolean) }
      def self.wildcard_list?(value)
        value.is_a?(Array) && value.size == 1 && value.first.to_s == WILDCARD
      end
    end
  end
end
