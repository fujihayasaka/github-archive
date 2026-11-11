# typed: strict
# frozen_string_literal: true

module TriageAgent
  module Frontmatter
    # Validates the triage agent config file frontmatter without applying
    # fail-closed defaults. Used to surface invalid config state in the UI
    # so users can diagnose misconfiguration before it silently disables
    # triggers or actions.
    #
    # Delegates to TriggerParser.validate_frontmatter and
    # AllowlistParser.validate_frontmatter, which reuse the same parsing
    # logic that the parsers themselves use at runtime.
    class ConfigValidator
      # Returns true when the raw config content has valid frontmatter
      # with correct `on:` and `allowed-actions:` sections.
      sig { params(raw_content: T.nilable(String)).returns(T::Boolean) }
      def self.valid?(raw_content)
        validate(raw_content).empty?
      end

      # Returns an array of human-readable error strings. An empty array
      # means the config is valid.
      sig { params(raw_content: T.nilable(String)).returns(T::Array[String]) }
      def self.validate(raw_content)
        frontmatter = Parser.extract_frontmatter!(raw_content)

        errors = T.let([], T::Array[String])
        errors.concat(TriggerParser.validate_frontmatter(frontmatter))
        errors.concat(AllowlistParser.validate_frontmatter(frontmatter))
        errors
      rescue Parser::ConfigError, Psych::Exception => e
        [e.message]
      end
    end
  end
end
