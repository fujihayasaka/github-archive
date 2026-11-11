# typed: strict
# frozen_string_literal: true

module TriageAgent
  module Frontmatter
    # Builds a TriageAgent::Allowlist from a parsed `allowed-actions` hash.
    # Handles wildcard expansion and allowed/blocked resolution for each
    # action dimension. Used by AllowlistParser after frontmatter extraction.
    class AllowlistBuilder
      # Action keys nested under allowed-actions.
      ADD_COMMENT_KEY = T.let("add-comment", String)
      ADD_LABELS_KEY = T.let("add-labels", String)
      ADD_TYPE_KEY   = T.let("add-type", String)
      ADD_FIELDS_KEY = T.let("add-fields", String)

      # Sub-keys within each action hash.
      ALLOWED_KEY = T.let("allowed", String)
      BLOCKED_KEY = T.let("blocked", String)

      sig { params(actions: T::Hash[String, T.untyped]).void }
      def initialize(actions)
        @actions = T.let(actions, T::Hash[String, T.untyped])
      end

      # Resolves each action dimension and assembles the Allowlist.
      sig { returns(TriageAgent::Allowlist) }
      def build
        comment_enabled = resolve_comment

        allowed_labels, disallowed_labels = resolve_action(ADD_LABELS_KEY)
        allowed_types, disallowed_types   = resolve_action(ADD_TYPE_KEY)
        allowed_fields, disallowed_fields = resolve_action(ADD_FIELDS_KEY)

        Allowlist.new(
          comment_enabled: comment_enabled,
          allowed_labels: allowed_labels,
          disallowed_labels: disallowed_labels,
          allowed_types: allowed_types,
          disallowed_types: disallowed_types,
          allowed_fields: allowed_fields,
          disallowed_fields: disallowed_fields,
        )
      end

      private

      # Resolves the allowed/blocked pair for a single action dimension,
      # translating wildcards into the corresponding Allowlist semantics.
      # When the action key is absent from @actions, that action is
      # disabled (empty allowed list).
      sig do
        params(action_key: String)
          .returns([T.nilable(T::Array[String]), T.nilable(T::Array[String])])
      end
      def resolve_action(action_key)
        # Action not listed → validation error (all keys are mandatory)
        raise AllowlistParser::ConfigError, "'#{action_key}' is required" unless @actions.key?(action_key)

        config = @actions[action_key]

        raise AllowlistParser::ConfigError, "'#{action_key}' must be a hash with 'allowed' and/or 'blocked' keys, got #{config.class}" unless config.is_a?(Hash)

        raw_allowed = extract_list(config, ALLOWED_KEY)
        raw_blocked = extract_list(config, BLOCKED_KEY)

        if raw_allowed.nil? && raw_blocked.nil?
          raise AllowlistParser::ConfigError, "'#{action_key}' must contain 'allowed' and/or 'blocked' keys"
        end

        # blocked: ["*"] overrides everything → block all values
        return [[], nil] if Parser.wildcard_list?(raw_blocked)

        # allowed: ["*"] → unrestricted (nil in Allowlist terms)
        allowed = Parser.wildcard_list?(raw_allowed) ? nil : raw_allowed

        [allowed, raw_blocked]
      end

      # Resolves the add-comment boolean. Required key.
      sig { returns(T::Boolean) }
      def resolve_comment
        raise AllowlistParser::ConfigError, "'#{ADD_COMMENT_KEY}' is required" unless @actions.key?(ADD_COMMENT_KEY)

        value = @actions[ADD_COMMENT_KEY]

        case value
        when true then true
        when false then false
        else
          raise AllowlistParser::ConfigError, "'#{ADD_COMMENT_KEY}' must be true or false, got #{value.inspect}"
        end
      end

      # Extracts a string array from a nested action config hash.
      # Returns nil when the config is not a hash or the key is absent,
      # which leaves the corresponding Allowlist dimension unrestricted.
      sig { params(config: T.untyped, key: String).returns(T.nilable(T::Array[String])) }
      def extract_list(config, key)
        return nil unless config.is_a?(Hash)

        Parser.coerce_string_array(config[key])
      end
    end
  end
end
