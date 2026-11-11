# typed: strict
# frozen_string_literal: true

module TriageAgent
  module Frontmatter
    # Parses YAML frontmatter from the triage agent's `.md` config file
    # and builds a TriageAgent::TriggerConfig. Extracts the `on:` block
    # which specifies which events trigger the triage agent.
    #
    # Schema (`on` is required, both triggers must be present):
    #
    #   ---
    #   on:                       # Required field
    #     issue-create: true      # Required — true or { filter: "<query>" }
    #     issue-comment: true     # Required — true or false
    #   ---
    #
    # Constraints:
    #
    #   - `on` is required — both `issue-create` and `issue-comment` must be present.
    #   - `issue-create` can be a hash (with optional `filter` key) or `true`.
    #   - `issue-comment` must be `true` or `false`.
    #   - `filter` uses GitHub advanced search query syntax.
    #   - Missing/invalid config results in a no-triggers TriggerConfig.
    #
    # Behaviour:
    #
    #   ┌──────────────────────────────────┬──────────────────────────────────────────┐
    #   │ Config state                     │ Result                                   │
    #   ├──────────────────────────────────┼──────────────────────────────────────────┤
    #   │ on missing                       │ Invalid config / no triggers             │
    #   │ issue-create missing             │ Invalid config / no triggers             │
    #   │ issue-comment missing            │ Invalid config / no triggers             │
    #   │ issue-comment: false             │ Retriage disabled                        │
    #   │ issue-comment: true              │ Triggers on @copilot mentions            │
    #   │ Both triggers, comment: true     │ Both enabled                             │
    #   │ filter on issue-create           │ Only triages matching issues              │
    #   └──────────────────────────────────┴──────────────────────────────────────────┘
    class TriggerParser

      # Raised when the frontmatter config is missing, incomplete, or invalid.
      class ConfigError < StandardError; end

      # Top-level key for triggers.
      ON_KEY = T.let("on", String)

      # Trigger keys nested under `on`.
      ISSUE_CREATE_KEY = T.let("issue-create", String)
      ISSUE_COMMENT_KEY = T.let("issue-comment", String)

      # Sub-key within issue-create.
      FILTER_KEY = T.let("filter", String)

      # Parses the raw .md content and returns a TriggerConfig.
      #
      # Fail-closed semantics: triggers are only enabled when explicitly
      # listed under `on`. Missing content, missing frontmatter, or an
      # absent/empty `on` block all result in a no-triggers TriggerConfig.
      sig { params(raw_content: T.nilable(String)).returns(TriageAgent::TriggerConfig) }
      def self.parse(raw_content)
        frontmatter = Parser.extract_frontmatter(raw_content)

        if frontmatter.nil? || frontmatter.empty?
          raise ConfigError, "no valid frontmatter found"
        end

        raise ConfigError, "'#{ON_KEY}' key is missing" unless frontmatter.key?(ON_KEY)

        on_config = frontmatter[ON_KEY]

        raise ConfigError, "'#{ON_KEY}' must be a hash, got #{on_config.class}" unless on_config.is_a?(Hash)

        issue_create_enabled, issue_create_filter = parse_issue_create(on_config)
        issue_comment_enabled = parse_issue_comment(on_config)

        TriggerConfig.new(
          issue_create_enabled: issue_create_enabled,
          issue_create_filter: issue_create_filter,
          issue_comment_enabled: issue_comment_enabled
        )
      rescue ConfigError, Psych::Exception => e
        GitHub.logger.warn("triage_agent.trigger_config_error", {
          "code.namespace" => "TriageAgent::Frontmatter::TriggerParser",
          "error" => e.message,
        })
        no_triggers
      end

      # Returns a TriggerConfig with no triggers enabled.
      sig { returns(TriageAgent::TriggerConfig) }
      def self.no_triggers
        TriggerConfig.new
      end

      # Parses the `issue-create` trigger from the `on` config hash.
      # Returns [enabled, filter] tuple.
      sig do
        params(on_config: T::Hash[String, T.untyped])
          .returns([T::Boolean, T.nilable(String)])
      end
      def self.parse_issue_create(on_config)
        raise ConfigError, "'#{ISSUE_CREATE_KEY}' is required" unless on_config.key?(ISSUE_CREATE_KEY)

        value = on_config[ISSUE_CREATE_KEY]

        case value
        when true
          [true, nil]
        when Hash
          filter = value[FILTER_KEY]

          if filter.present? && !filter.is_a?(String)
            raise ConfigError, "'#{ISSUE_CREATE_KEY}.#{FILTER_KEY}' must be a string, got #{filter.class}"
          end

          [true, filter.presence]
        else
          raise ConfigError, "'#{ISSUE_CREATE_KEY}' must be true or a hash, got #{value.inspect}"
        end
      end

      # Parses the `issue-comment` trigger from the `on` config hash.
      sig { params(on_config: T::Hash[String, T.untyped]).returns(T::Boolean) }
      def self.parse_issue_comment(on_config)
        raise ConfigError, "'#{ISSUE_COMMENT_KEY}' is required" unless on_config.key?(ISSUE_COMMENT_KEY)

        value = on_config[ISSUE_COMMENT_KEY]

        case value
        when true
          true
        when false
          false
        else
          raise ConfigError, "'#{ISSUE_COMMENT_KEY}' must be true or false, got #{value.inspect}"
        end
      end

      private_class_method :no_triggers, :parse_issue_create, :parse_issue_comment
    end
  end
end
