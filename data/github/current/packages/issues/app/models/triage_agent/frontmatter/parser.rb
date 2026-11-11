# typed: strict
# frozen_string_literal: true

require "yaml"

module TriageAgent
  module Frontmatter
    # Base class for frontmatter parsers. Provides shared utilities for
    # extracting and working with YAML frontmatter in markdown documents.
    #
    # Subclasses must override `parse_frontmatter!` to parse their
    # section of the frontmatter hash, raising ConfigError on invalid
    # input.
    #
    # Provides a shared `validate_frontmatter` that calls the
    # subclass's `parse_frontmatter!` and collects any ConfigError
    # messages into an array of human-readable error strings.
    class Parser
      # Raised when the frontmatter config is missing, incomplete, or invalid.
      class ConfigError < StandardError; end

      # Wildcard value that means "all" when used in allowed/blocked lists
      # or in the top-level allowed-actions array.
      WILDCARD = T.let("*", String)

      # Validates config from a pre-extracted frontmatter hash.
      # Returns an array of error strings (empty when valid).
      sig { params(frontmatter: T::Hash[String, T.untyped]).returns(T::Array[String]) }
      def self.validate_frontmatter(frontmatter)
        parse_frontmatter!(frontmatter)
        []
      rescue ConfigError => e
        [e.message]
      end

      # Subclasses must override this method to parse their section
      # of the frontmatter. Should raise ConfigError on invalid input.
      sig { params(frontmatter: T::Hash[String, T.untyped]).returns(T.untyped) }
      def self.parse_frontmatter!(frontmatter)
        raise NotImplementedError, "#{name} must implement parse_frontmatter!"
      end

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

      # Extracts YAML frontmatter from raw markdown content and raises
      # ConfigError if no valid frontmatter is found.
      sig { params(raw_content: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
      def self.extract_frontmatter!(raw_content)
        frontmatter = extract_frontmatter(raw_content)
        raise ConfigError, "no valid frontmatter found" if frontmatter.nil? || frontmatter.empty?
        frontmatter
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

      # Logs a config warning with a structured event.
      sig { params(log_event: String, namespace: T.nilable(String), error: StandardError).void }
      def self.log_warning(log_event:, namespace:, error:)
        GitHub.logger.warn(log_event, {
          "code.namespace" => namespace,
          "error" => error.message,
        })
      end
    end
  end
end
