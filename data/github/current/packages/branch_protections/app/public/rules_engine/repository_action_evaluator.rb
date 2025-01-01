# typed: strict
# frozen_string_literal: true

module RulesEngine
  module RepositoryActionEvaluator
    extend T::Sig

    sig { params(repository: Repository, actor: User, dry_run: T::Boolean).returns(T.nilable(String)) }
    def self.name_of_ruleset_source_blocking_delete(repository, actor, dry_run: false)
      if repository.member_privilege_rulesets_enabled?
        event = RuleEngine::Events::RepositoryOperationEvent.new(repository, actor, { delete: nil }, dry_run:)
        result = RuleEngine::GenericEvaluator.evaluate_rules(event).first
        if result.present?
          if result.action_permitted?
            nil
          else
            RepositoryRuleset.where(id: result.rule_runs.first.rule_provider_id).first.source.name
          end
        else
          nil
        end
      else
        nil
      end
    end

    sig { params(repository: Repository, actor: User, dry_run: T::Boolean).returns(T::Boolean) }
    def self.can_delete_repository?(repository, actor, dry_run: false)
      name_of_ruleset_source_blocking_delete(repository, actor, dry_run:).nil?
    end

    sig { params(repository: Repository, actor: User, dry_run: T::Boolean).returns(T.nilable(String)) }
    def self.name_of_ruleset_source_blocking_transfer(repository, actor, dry_run: false)
      if repository.member_privilege_rulesets_enabled?
        event = RuleEngine::Events::RepositoryOperationEvent.new(repository, actor, { transfer: nil }, dry_run:)
        result = RuleEngine::GenericEvaluator.evaluate_rules(event).first
        if result.present?
          if result.action_permitted?
            nil
          else
            RepositoryRuleset.where(id: result.rule_runs.first.rule_provider_id).first.source.name
          end
        else
          nil
        end
      else
        nil
      end
    end

    sig { params(repository: Repository, actor: User, dry_run: T::Boolean).returns(T::Boolean) }
    def self.can_transfer_repository?(repository, actor, dry_run: false)
      name_of_ruleset_source_blocking_transfer(repository, actor, dry_run:).nil?
    end

    sig { params(repository: Repository, actor: User, dry_run: T::Boolean).returns(T::Boolean) }
    def self.can_create_repository?(repository, actor, dry_run)
      if repository.member_privilege_rulesets_enabled?
        event = RuleEngine::Events::RepositoryOperationEvent.new(repository, actor, { create: nil }, dry_run:)
        result = RuleEngine::GenericEvaluator.evaluate_rules(event).first
        !!result&.action_permitted?
      else
        true
      end
    end

    sig { params(repository: Repository, actor: User, dry_run: T::Boolean).returns(T::Boolean) }
    def self.can_rename_repository?(repository, actor, dry_run)
      if repository.member_privilege_rulesets_enabled?
        event = RuleEngine::Events::RepositoryOperationEvent.new(repository, actor, { rename: nil }, dry_run:)
        result = RuleEngine::GenericEvaluator.evaluate_rules(event).first

        return true if !!result&.action_permitted?

        failed_runs = result&.rule_runs&.filter { |run| !run.allowed? } || []

        if failed_runs.size > 0
          has_more = failed_runs.size > 1
          repository.errors.add :name, "does not match \"#{failed_runs.first&.rule_config&.parameters['pattern']}\""
        end

        false
      else
        true
      end
    end

    sig { params(organization: Organization, rule_types: T.nilable(T::Array[String])).returns(T::Boolean) }
    def self.organization_is_protected?(organization, rule_types = nil)
      if organization.member_privilege_rulesets_enabled?
        enabled_rulesets = RepositoryRuleset.load_for(source: organization, include_parents: true, targets: ["member_privilege"]).select { |ruleset| ruleset.enabled? }

        return enabled_rulesets.any? if rule_types.nil?

        GitHub::PrefillAssociations.prefill_associations(enabled_rulesets, [:rule_configurations])

        enabled_rulesets.any? { |ruleset| ruleset.enabled? && ruleset.rule_configurations.any? { |config| rule_types.include?(config.rule_type) } }
      else
        false
      end
    end
  end
end
