# typed: strict
# frozen_string_literal: true

module RepositoryRulesets
  module HashParser
    extend T::Helpers
    include Kernel

    # These bypass actor types do not require an actor_id
    BYPASS_ACTOR_TYPES_WITHOUT_ACTOR_ID = T.let(%w[EnterpriseOwner DeployKey].freeze, T::Array[String])

    sig do
      params(
        domain: RuleEngine::DomainAccessorBase[RuleEngine::Types::RuleSource],
        source: RuleEngine::Types::RuleSource,
        hash: T::Hash[T.untyped, T.untyped],
        validate_bypass_actors: T.nilable(T::Boolean),
      ).returns(RuleEngine::RulesetBase)
    end
    def self.to_ruleset(domain, source, hash, validate_bypass_actors: false)
      validate_target(domain, source, hash)

      ruleset = domain.ruleset_class.new(source:, name: hash["name"])

      ruleset.target = hash["target"] if hash["target"].present?
      ruleset.enforcement = RuleEngine::RulesetBase::ENFORCEMENT_DISPLAY_VALUES.key(hash["enforcement"].to_sym) if hash["enforcement"].present?

      attach_conditions(ruleset, source, hash["conditions"]) if hash["conditions"]
      attach_rules(ruleset, source, hash["rules"]) if hash["rules"]
      attach_bypass_actors(ruleset, source, hash["bypass_actors"]) if hash["bypass_actors"]

      if validate_bypass_actors
        ruleset.bypass_actors.each do |bypass_actor|
          raise RepositoryRulesetBypassActor::ValidationError.new(bypass_actor.errors) unless bypass_actor.valid?
        end
      end

      # call and reassign conditions, rules, and bypass_actors before the ruleset id is set
      # Note: ActiveRecord magic will try to attach a foreign key to these objects if it sees the ruleset has an id
      # at time of call (lazy loaded). Which will also make the sql look at the current ruleset
      # (not just the newly created ruleset) for these objects.
      # Resulting in current information being mixed in with historical information
      if ruleset.is_a?(RepositoryRuleset)
        ruleset.conditions = ruleset.conditions.to_a
        ruleset.rule_configurations = ruleset.rule_configurations.to_a
        ruleset.bypass_actors = ruleset.bypass_actors.to_a
      end

      ruleset
    end

    # Only works for `RepositoryRuleset` currently
    # TODO: Support API for other types of rulesets
    sig { params(ruleset: RepositoryRuleset, hash: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
    def self.patch_repository_ruleset!(ruleset, hash)
      validate_target(Repositories.domain.rulesets, ruleset.source, hash)

      ruleset.name = hash["name"] if hash["name"].present?
      ruleset.target = hash["target"] if hash["target"].present?
      ruleset.enforcement = RuleEngine::RulesetBase::ENFORCEMENT_DISPLAY_VALUES.key(hash["enforcement"].to_sym) if hash["enforcement"].present?

      # TODO: consider removing this retry, since it may not be safe
      # See https://thehub.github.com/epd/engineering/products-and-services/dotcom/deadlocked-transactions/
      RepositoryRuleset.retry_on_deadlock do
        RepositoryRuleset.transaction do
          if ruleset.source.member_privilege_rulesets_enabled? && ruleset.target == "repository"
            if ruleset.source.is_a?(Repository)
              # repository policies are only supported on non-repo sources
              raise RuleEngine::IRuleset::InvalidTarget.new(ruleset.target)
            end
            if ruleset.enforcement == "evaluate"
              raise RuleEngine::IRuleset::Error.new("Repository policies cannot be set to evaluate")
            end
          end
          conditions_changed = hash["conditions"] &&
            ruleset.upsert_conditions(hash["conditions"].keys.map { |key| translate_condition(key, hash["conditions"][key]) })

          bypass_actors_changed = if hash["bypass_actors"]
            bypass_actors = RepositoryRulesetBypassActor.translate_bypass_actors(ruleset, hash["bypass_actors"])
            ruleset.upsert_bypass_actors(T.unsafe(bypass_actors))
          else
            false
          end

          rules_changed = hash["rules"] &&
            ruleset.upsert_rules(hash["rules"].map { |rule_hash| translate_rule(rule_hash, ruleset) }, apply_default_parameters: true)

          changed = ruleset.changed? || conditions_changed || bypass_actors_changed || rules_changed

          next false unless changed

          ruleset.save!
          true
        end
      end
    end

    sig { params(domain: RuleEngine::DomainAccessorBase[RuleEngine::Types::RuleSource], source: RuleEngine::Types::RuleSource, hash: T::Hash[T.untyped, T.untyped]).void }
    def self.validate_target(domain, source, hash)
      return unless hash["target"]
      # TODO: Consider using AR validations
      return if hash["target"] == "repository" && source.member_privilege_rulesets_enabled? && !source.is_a?(Repository)
      return if hash["target"] != "repository" && domain.ruleset_class.targets.keys.include?(hash["target"])

      raise RuleEngine::IRuleset::InvalidTarget.new(hash["target"])
    end

    sig { params(ruleset: RuleEngine::RulesetBase, source: RuleEngine::Types::RuleSource, hash: T::Hash[T.untyped, T.untyped]).void }
    def self.attach_conditions(ruleset, source, hash)
      hash.each do |key, condition_hash|
        ruleset.conditions.build(translate_condition(key, condition_hash))
      end
    end

    sig { params(ruleset: RuleEngine::RulesetBase, source: RuleEngine::Types::RuleSource, hash: T::Array[T::Hash[T.untyped, T.untyped]]).void }
    def self.attach_rules(ruleset, source, hash)
      hash.each do |rule_hash|
        ruleset.rule_configurations.build(translate_rule(rule_hash, ruleset))
      end
    end

    sig { params(ruleset: RuleEngine::RulesetBase, source: RuleEngine::Types::RuleSource, hash: T::Array[T::Hash[T.untyped, T.untyped]]).void }
    def self.attach_bypass_actors(ruleset, source, hash)
      return unless ruleset.is_a?(RepositoryRuleset)

      bypass_actors = RepositoryRulesetBypassActor.translate_bypass_actors(ruleset, hash)

      bypass_actors.each do |bypass_actor|
        # call from_hash to create the concrete subclass, not the abstract base class
        ruleset.bypass_actors << RepositoryRulesetBypassActor.from_hash(bypass_actor)
      end
    end

    sig { params(target: T.untyped, condition_hash: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
    private_class_method def self.translate_condition(target, condition_hash)
      attrs = {
        target:,
        parameters: translate_condition_parameters(target, condition_hash.except("type"))
      }
      attrs[:condition_type] = condition_hash["type"] if condition_hash["type"].present?
      attrs
    end

    sig { params(target: String, parameters: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
    private_class_method def self.translate_condition_parameters(target, parameters)
      # Convert DB IDs to global IDs
      if target == "repository_id"
        parameters["repository_ids"] = Repository.where(id: parameters["repository_ids"]).map(&:global_relay_id)
      end
      if target == "organization_id"
        parameters["organization_ids"] = Organization.where(id: parameters["organization_ids"]).map(&:global_relay_id)
      end

      parameters
    end

    sig { params(hash: T::Hash[T.untyped, T.untyped], ruleset: RuleEngine::RulesetBase).returns(T::Hash[T.untyped, T.untyped]) }
    private_class_method def self.translate_rule(hash, ruleset)
      hash["rule_type"] = hash.delete("type") if hash["type"].present?
      if hash["parameters"].present?
        # If a rule type is a node_id and we instead have the object mapping (db_id and type), we need to convert it
        impl = ruleset.domain.registry.rule_impl_for_rule_type(hash["rule_type"])
        hash["parameters"] = translate_node_id_fields(hash["parameters"], impl.parameter_schema.fields) if impl.present?
      end

      hash.deep_symbolize_keys
    end

    sig { params(hash: T::Hash[T.untyped, T.untyped], fields: T::Array[RuleEngine::ParameterSchema::Base]).returns(T::Hash[T.untyped, T.untyped]) }
    private_class_method def self.translate_node_id_fields(hash, fields)
      # Get all node id fields that need to be translated
      nodes_hash = get_all_node_id_fields(hash, fields)
      # If there are no node fields, we can just return the original hash
      if !nodes_hash.present?
        return hash
      end
      id_to_node_id_hash = {}
      nodes_hash.each do |type, ids|
        # The OpenAPI schema should be protecting us here, so if an invalid type gets in, raise an error
        klass = case type
        when "User" then User
        when "Team" then Team
        when "IntegrationInstallation" then IntegrationInstallation
        when "RepositoryRole" then RepositoryRole
        else
          raise RuleEngine::IRuleset::Error.new("Invalid reviewer type #{type}")
        end
        klass.where(id: ids).each do |record|
          id_to_node_id_hash[type] ||= {}
          id_to_node_id_hash[type][record.id] = record.global_relay_id
        end
      end
      # Now that we've collected all the node id fields and mapped the db ids to global ids, we can convert them
      convert_node_ids(hash, fields, id_to_node_id_hash)
    end

    sig { params(hash: T::Hash[T.untyped, T.untyped], fields: T::Array[RuleEngine::ParameterSchema::Base], nodes_hash: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
    private_class_method def self.get_all_node_id_fields(hash, fields, nodes_hash = {})
      fields.each do |field|
        if field.is_a?(RuleEngine::ParameterSchema::NodeIdField)
          value = hash[field.node_id_object.name]
          next unless value.present?
          type = value["type"]
          id = value["id"]
          if type && id
            nodes_hash[type] ||= []
            nodes_hash[type] << id
          end
        else
          value = hash[field.name]
          if field.is_a?(RuleEngine::ParameterSchema::Array) && field.content_type == :object && value.is_a?(::Array)
            value.filter { |item| item.is_a?(Hash) }.map do |item|
              nodes_hash = get_all_node_id_fields(item, field.content_object.fields, nodes_hash)
            end
          elsif field.is_a?(RuleEngine::ParameterSchema::Array) && field.content_type == :node_id && field.node_id_object && value.is_a?(::Array)
            value.each do |item|
              next unless item.is_a?(Hash)
              item_type = item["type"]
              item_id = item["id"]
              next unless item_type && item_id
              nodes_hash[item_type] ||= []
              nodes_hash[item_type] << item_id
            end
          elsif field.is_a?(RuleEngine::ParameterSchema::Object) && value.is_a?(Hash)
            nodes_hash = get_all_node_id_fields(value, field.fields, nodes_hash)
          end
        end
      end

      nodes_hash
    end

    sig { params(hash: T::Hash[T.untyped, T.untyped], fields: T::Array[RuleEngine::ParameterSchema::Base], nodes_hash: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
    private_class_method def self.convert_node_ids(hash, fields, nodes_hash = {})
      fields.each do |field|
        if field.is_a?(RuleEngine::ParameterSchema::NodeIdField)
          value = hash.delete(field.node_id_object.name)
          next unless value.present?
          node_id = nodes_hash.dig(value["type"], value["id"])
          # If not found, just use the original id so we can provide a useful error message
          # convert to string because NodeID is expected to be a string
          hash[field.name] = node_id || value["id"]&.to_s
        else
          value = hash[field.name]
          if field.is_a?(RuleEngine::ParameterSchema::Array) && field.content_type == :object && value.is_a?(::Array)
            hash[field.name] = value.filter { |item| item.is_a?(Hash) }.map do |item|
              convert_node_ids(item, field.content_object.fields, nodes_hash)
            end
          elsif field.is_a?(RuleEngine::ParameterSchema::Array) && field.content_type == :node_id && field.node_id_object && value.is_a?(::Array)
            hash[field.name] = value.map do |item|
              if item.is_a?(Hash)
                nodes_hash.dig(item["type"], item["id"]) || item["id"]&.to_s
              else
                item
              end
            end
          elsif field.is_a?(RuleEngine::ParameterSchema::Object) && value.is_a?(Hash)
            hash[field.name] = convert_node_ids(value, field.fields, nodes_hash)
          end
        end
      end
      hash
    end
  end
end
