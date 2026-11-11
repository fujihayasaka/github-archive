# typed: strict
# frozen_string_literal: true

module TriageAgent
  module Frontmatter
    # Parses YAML frontmatter from the triage agent's `.md` config file
    # and builds a TriageAgent::Allowlist. When config moves to a DB,
    # this parser can be retired and replaced with a DB-backed builder.
    #
    # Schema (`allowed-actions` is required):
    #
    #   ---
    #   allowed-actions:            # Required field
    #     <action-type>:            # add-labels, add-type, add-fields
    #       allowed: [values...]    # Permitted values (use ["*"] to allow all)
    #       blocked: [values...]    # Blocked values (use ["*"] to block all)
    #   ---
    #
    # Or use the wildcard to allow everything:
    #
    #   ---
    #   allowed-actions: ["*"]      # All actions allowed with all values
    #   ---
    #
    # Example:
    #
    #   ---
    #   allowed-actions:
    #     add-labels:
    #       allowed: [good first issue, duplicate, wontfix]
    #       blocked: [duplicate]
    #     add-type:
    #       blocked: [Epic, Initiative]
    #     add-fields:
    #       allowed: ["*"]
    #       blocked: [Priority, Effort]
    #   ---
    #
    # Constraints:
    #
    #   - `allowed-actions` is required — config is invalid without it.
    #   - `allowed-actions: ["*"]` — all actions allowed, no restrictions.
    #   - Action types must be explicitly listed — unlisted actions disabled.
    #   - `allowed` and `blocked` can be used independently:
    #     - allowed only → only those values permitted.
    #     - blocked only → all values except blocked ones permitted.
    #     - Both → allowed values minus blocked values.
    #   - Wildcard `["*"]` applies to both lists:
    #     - `allowed: ["*"]` → permit all values (unless in blocked).
    #     - `blocked: ["*"]` → block all values.
    #   - `blocked: []` → no values blocked (all permitted).
    #   - `blocked` takes precedence — values in both lists are excluded.
    #
    # Behaviour:
    #
    #   ┌────────────────────────────┬──────────────────────────────────────────┐
    #   │ Config state               │ Result                                   │
    #   ├────────────────────────────┼──────────────────────────────────────────┤
    #   │ allowed-actions missing    │ Invalid config / no actions              │
    #   │ allowed-actions: ["*"]     │ All actions allowed with all values      │
    #   │ Action type not listed     │ That action is disabled                  │
    #   │ allowed only               │ Only listed values permitted             │
    #   │ blocked only               │ All values except blocked ones permitted │
    #   │ allowed + blocked          │ Allowed values minus blocked values      │
    #   │ allowed: ["*"]             │ All values permitted (unless in blocked) │
    #   │ blocked: ["*"]             │ All values blocked                       │
    #   │ blocked: []                │ No values blocked, all values permitted  │
    #   └────────────────────────────┴──────────────────────────────────────────┘
    class AllowlistParser
      # Raised when the frontmatter config is missing, incomplete, or invalid.
      class ConfigError < StandardError; end

      # Top-level key that wraps all action filters.
      ALLOWED_ACTIONS_KEY = T.let("allowed-actions", String)

      # Parses the raw .md content and returns an Allowlist.
      #
      # Fail-closed semantics: actions are only permitted when explicitly
      # listed under `allowed-actions`. Missing content, missing frontmatter,
      # or an absent/empty `allowed-actions` block all result in a deny-all
      # Allowlist. Individual action keys that are absent from `allowed-actions`
      # are also blocked.
      sig { params(raw_content: T.nilable(String)).returns(TriageAgent::Allowlist) }
      def self.parse(raw_content)
        frontmatter = Parser.extract_frontmatter(raw_content)

        if frontmatter.nil? || frontmatter.empty?
          raise ConfigError, "no valid frontmatter found"
        end

        raise ConfigError, "'#{ALLOWED_ACTIONS_KEY}' key is missing" unless frontmatter.key?(ALLOWED_ACTIONS_KEY)

        actions = frontmatter[ALLOWED_ACTIONS_KEY]

        case actions
        when Hash
          return deny_all if actions.empty?

          AllowlistBuilder.new(actions).build
        when Array
          return Allowlist.new if Parser.wildcard_list?(actions)
          return deny_all if actions.empty?

          raise ConfigError, "'#{ALLOWED_ACTIONS_KEY}' array must be [\"*\"] or [], got #{actions.inspect}"
        when nil
          deny_all
        else
          raise ConfigError, "'#{ALLOWED_ACTIONS_KEY}' must be a hash, empty array, or [\"*\"], got #{actions.class}"
        end
      rescue ConfigError, Psych::Exception => e
        GitHub.logger.warn("triage_agent.config_error", {
          "code.namespace" => "TriageAgent::Frontmatter::AllowlistParser",
          "error" => e.message,
        })
        deny_all
      end

      # Returns a deny-all Allowlist that blocks every action dimension.
      sig { returns(TriageAgent::Allowlist) }
      def self.deny_all
        Allowlist.new(comment_enabled: false, allowed_labels: [], allowed_types: [], allowed_fields: [])
      end

      private_class_method :deny_all
    end
  end
end
