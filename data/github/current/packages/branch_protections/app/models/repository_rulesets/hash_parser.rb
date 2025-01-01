# typed: strict
# frozen_string_literal: true

module RepositoryRulesets
  module HashParser
    extend T::Helpers
    extend T::Sig
    include Kernel

    class OrgRoleBypassActorError < StandardError
      extend T::Sig

      sig { params(msg: String, actor_id: T.nilable(Integer)).void }
      def initialize(msg, actor_id: nil)
        @actor_id = actor_id
        super(msg)
      end

      sig { returns(T.nilable(Integer)) }
      attr_reader :actor_id
    end

    sig { params(source: RuleEngine::Types::RuleSource, hash: T::Hash[T.untyped, T.untyped]).returns(RepositoryRuleset) }
    def self.to_repository_ruleset(source, hash)
      validate_target(source, hash)

      ruleset = RepositoryRuleset.new(source:, name: hash["name"])

      ruleset.target = hash["target"] if hash["target"].present?
      ruleset.enforcement = RepositoryRuleset::ENFORCEMENT_DISPLAY_VALUES.key(hash["enforcement"].to_sym) if hash["enforcement"].present?

      attach_conditions(ruleset, source, hash["conditions"]) if hash["conditions"]
      attach_rules(ruleset, source, hash["rules"]) if hash["rules"]
      attach_bypass_actors(ruleset, source, hash["bypass_actors"]) if hash["bypass_actors"]

      ruleset
    end

    sig { params(ruleset: RepositoryRuleset, hash: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
    def self.patch_repository_ruleset!(ruleset, hash)
      validate_target(ruleset.source, hash)

      ruleset.name = hash["name"] if hash["name"].present?
      ruleset.target = hash["target"] if hash["target"].present?
      ruleset.enforcement = RepositoryRuleset::ENFORCEMENT_DISPLAY_VALUES.key(hash["enforcement"].to_sym) if hash["enforcement"].present?

      RepositoryRuleset.transaction do
        if ruleset.source.member_privilege_rulesets_enabled? && ruleset.target == "member_privilege"
          if ruleset.source.is_a?(Repository)
            # member_privilege rulesets are only supported on non-repo sources
            raise RepositoryRuleset::InvalidTarget.new(ruleset.target)
          end
          if ruleset.enforcement == "evaluate"
            raise RepositoryRuleset::Error.new("Member privilege rulesets cannot be set to evaluate")
          end
        end
        conditions_changed = hash["conditions"] &&
          ruleset.upsert_conditions(hash["conditions"].keys.map { |key| translate_condition(key, hash["conditions"][key]) })

        bypass_actors_changed = if hash["bypass_actors"]
          bypass_actors = translate_bypass_actors(ruleset, ruleset.source, hash["bypass_actors"])
          ruleset.upsert_bypass_actors(T.unsafe(bypass_actors))
        else
          false
        end

        rules_changed = hash["rules"] &&
          ruleset.upsert_rules(hash["rules"].map { |rule_hash| translate_rule(rule_hash) }, apply_default_parameters: true)

        changed = ruleset.changed? || conditions_changed || bypass_actors_changed || rules_changed

        next false unless changed

        ruleset.save!
        true
      end
    end

    sig { params(source: RuleEngine::Types::RuleSource, hash: T::Hash[T.untyped, T.untyped]).void }
    def self.validate_target(source, hash)
      return unless hash["target"]
      # TODO: Remove once push rules are fully enabled, and consider using AR validations
      return if hash["target"] == "push" && source.push_rulesets_enabled?
      return if hash["target"] == "member_privilege" && source.member_privilege_rulesets_enabled? && !source.is_a?(Repository)
      return if hash["target"] != "push" && hash["target"] != "member_privilege" && RepositoryRuleset.targets.keys.include?(hash["target"])

      raise RepositoryRuleset::InvalidTarget.new(hash["target"])
    end

    sig { params(ruleset: RepositoryRuleset, source: RuleEngine::Types::RuleSource, hash: T::Hash[T.untyped, T.untyped]).void }
    def self.attach_conditions(ruleset, source, hash)
      hash.each do |key, condition_hash|
        ruleset.conditions.build(translate_condition(key, condition_hash))
      end
    end

    sig { params(ruleset: RepositoryRuleset, source: RuleEngine::Types::RuleSource, hash: T::Array[T::Hash[T.untyped, T.untyped]]).void }
    def self.attach_rules(ruleset, source, hash)
      hash.each do |rule_hash|
        ruleset.rule_configurations.build(translate_rule(rule_hash))
      end
    end

    sig { params(ruleset: RepositoryRuleset, source: RuleEngine::Types::RuleSource, hash: T::Array[T::Hash[T.untyped, T.untyped]]).void }
    def self.attach_bypass_actors(ruleset, source, hash)
      bypass_actors = translate_bypass_actors(ruleset, source, hash)

      bypass_actors.each do |bypass_actor|
        ruleset.bypass_actors.build(bypass_actor)
      end
    end

    sig { params(target: T.untyped, condition_hash: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
    private_class_method def self.translate_condition(target, condition_hash)
      {
        target:,
        condition_type: condition_hash["type"],
        parameters: translate_condition_parameters(target, condition_hash.except("type"))
      }
    end

    sig { params(target: String, parameters: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
    private_class_method def self.translate_condition_parameters(target, parameters)
      # Convert DB IDs to global IDs
      if target == "repository_id"
        parameters["repository_ids"] = Repository.where(id: parameters["repository_ids"]).map(&:global_relay_id)
      end

      # Update the repository property condition to use the new format with the source field
      if target == "repository_property" && GitHub.flipper[:ruleset_backfill_source].enabled?
        %w[include exclude].each do |condition|
          parameters[condition].each { |property| property["source"] ||= "custom" }
        end
      end

      parameters
    end

    sig { params(hash: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
    private_class_method def self.translate_rule(hash)
      hash["rule_type"] = hash.delete("type") if hash["type"].present?
      hash.deep_symbolize_keys
    end

    sig { params(ruleset: RepositoryRuleset, source: RuleEngine::Types::RuleSource, hash: T::Array[T::Hash[T.untyped, T.untyped]]).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    private_class_method def self.translate_bypass_actors(ruleset, source, hash)
      bypass_actors = T.let([], T::Array[T::Hash[T.untyped, T.untyped]])
      bypass_org_admin = T.let(false, T::Boolean)
      bypass_deploy_key = T.let(false, T::Boolean)
      valid_actor_types = RepositoryRulesetBypassActor::VALID_ACTORS + %w[OrganizationAdmin DeployKey]

      hash.each do |bypass_actor_hash|
        if valid_actor_types.exclude?(bypass_actor_hash["actor_type"])
          raise RepositoryRuleset::Error.new("#{bypass_actor_hash["actor_type"]} is not a valid actor type")
        end
        # actor_id is no longer required in the schema because deploy keys do not have an actor id
        # so check input to ensure id is not nil for other bypass actors
        if (valid_actor_types - ["DeployKey"]).include?(bypass_actor_hash["actor_type"]) && bypass_actor_hash["actor_id"].nil?
          raise RepositoryRuleset::Error.new("actor_id is required for #{bypass_actor_hash["actor_type"]}")
        end
        if bypass_actor_hash["bypass_mode"] != "always" && ruleset.target != "branch"
          raise RepositoryRuleset::Error.new("bypass mode must be 'ALWAYS' for #{ruleset.target} rulesets")
        end
        if bypass_actor_hash["actor_type"] == "OrganizationAdmin"
          next unless source.is_a?(Business) || source.owner.organization?

          actor_id = bypass_actor_hash["actor_id"]
          if RepositoryRuleset::ORG_ROLE_BYPASS_ACTOR_IDS.values.exclude?(actor_id)
            raise OrgRoleBypassActorError.new("#{actor_id} is not a supported actor_id", actor_id:)
          end

          bypass_org_admin = true

          if bypass_actor_hash["bypass_mode"] == "pull_request"
            ruleset.bypass_mode = :org_bypass_prs_only
          else
            ruleset.bypass_mode = :org_bypass_any
          end
        elsif bypass_actor_hash["actor_type"] == "DeployKey"
          if bypass_actor_hash["actor_id"] != RepositoryRulesetBypassActor::DeployKey.id
            raise RepositoryRuleset::Error.new("actor id is invalid for deploy key bypass actor. Must be null.")
          end
          if bypass_actor_hash["bypass_mode"] != "always"
            # Deploy key does not support any other bypass mode
            # We can't prohibit the input via the OpenAPI schema so raise an error instead
            raise RepositoryRuleset::Error.new("deploy key bypass mode must be 'ALWAYS'")
          end
          bypass_deploy_key = true
          ruleset.deploy_key_bypass = true
        else
          bypass_actor_hash["bypass_mode"] = db_actor_bypass_mode(bypass_actor_hash["bypass_mode"]) if bypass_actor_hash["bypass_mode"].present?
          bypass_actors << bypass_actor_hash.symbolize_keys
        end
      end

      if !bypass_org_admin
        ruleset.bypass_mode = :no_org_bypass
      end

      if !bypass_deploy_key
        ruleset.deploy_key_bypass = false
      end

      bypass_actors
    end

    sig { params(bypass_mode: T.nilable(String)).returns(Integer) }
    private_class_method def self.db_actor_bypass_mode(bypass_mode)
      if bypass_mode == "always" || bypass_mode.nil?
        # default value
        RepositoryRulesetBypassActor::BYPASS_MODES[:any]
      else
        RepositoryRulesetBypassActor::BYPASS_MODES[bypass_mode.to_sym]
      end
    end
  end
end
