# typed: strict
# frozen_string_literal: true

module RulesEngine
  module RepositoryActionEvaluator

    sig { params(repository_model: RuleEngine::Events::RepositoryOperationEvent::RepositoryModel, actor: User, visibility: String).returns({ errors: T::Array[String] }) }
    def self.validate_creation(repository_model, actor, visibility)
      event = RuleEngine::Events::RepositoryOperationEvent.new(repository_model, actor, {
        create: nil,
        change_visibility: visibility,
      })

      result = RuleEngine::GenericEvaluator.evaluate_rules(event)

      errors = result.filter_map do |rule_suite|
        next if rule_suite.action_permitted?

        rule_suite.failure_messages(prefix: nil, exclude_violations: true, include_bypassed: false)
      end.flatten

      { errors: }
    end

    sig { params(repository: Repository, actor: User, operation: T::Hash[Symbol, T.untyped], persist_results: T::Boolean).returns(T.nilable(RuleEngine::RuleSuite)) }
    def self.evaluate_operation(repository, actor, operation, persist_results: false)
      if repository.member_privilege_rulesets_enabled?
        event = RuleEngine::Events::RepositoryOperationEvent.new(repository, actor, operation, persist_results:)
        RuleEngine::GenericEvaluator.evaluate_rules(event).first
      else
        nil
      end
    end

    sig { params(repository: Repository, actor: User, operation: T::Hash[Symbol, T.untyped], persist_results: T::Boolean).returns(T.nilable(String)) }
    def self.name_of_ruleset_source_blocking_operation(repository, actor, operation, persist_results: false)
      return nil unless repository.member_privilege_rulesets_enabled?
      result = evaluate_operation(repository, actor, operation, persist_results:)
      if result.present? && !result.action_permitted?
        T.must(RepositoryRuleset.where(id: result.rule_runs.first!.rule_provider_id).first).source.name
      else
        nil
      end
    end

    sig { params(repository: Repository, actor: User, persist_results: T::Boolean).returns(T.nilable(String)) }
    def self.name_of_ruleset_source_blocking_delete(repository, actor, persist_results: false)
      name_of_ruleset_source_blocking_operation(repository, actor, { delete: nil }, persist_results:)
    end

    sig { params(repository: Repository, actor: User, persist_results: T::Boolean).returns(T::Boolean) }
    def self.can_delete_repository?(repository, actor, persist_results: false)
      name_of_ruleset_source_blocking_delete(repository, actor, persist_results:).nil?
    end

    sig { params(repository: Repository, actor: User, persist_results: T::Boolean).returns(T.nilable(String)) }
    def self.name_of_ruleset_source_blocking_transfer(repository, actor, persist_results: false)
      name_of_ruleset_source_blocking_operation(repository, actor, { transfer: nil }, persist_results:)
    end

    sig { params(repository: Repository, actor: User, persist_results: T::Boolean).returns(T::Boolean) }
    def self.can_transfer_repository?(repository, actor, persist_results: false)
      name_of_ruleset_source_blocking_transfer(repository, actor, persist_results:).nil?
    end

    sig { params(repository: Repository, actor: User, persist_results: T::Boolean).returns(T.nilable(RuleEngine::RuleSuite)) }
    def self.check_repo_create(repository, actor, persist_results: false)
      if repository.member_privilege_rulesets_enabled?
        event = RuleEngine::Events::RepositoryOperationEvent.new(repository, actor, { create: nil }, persist_results:)
        RuleEngine::GenericEvaluator.evaluate_rules(event).first
      else
        nil
      end
    end

    sig { params(repository: Repository, actor: User, persist_results: T::Boolean).returns(T::Boolean) }
    def self.can_create_repository?(repository, actor, persist_results: false)
      result = check_repo_create(repository, actor, persist_results:)
      result ? result.action_permitted? : true
    end

    sig { params(repository: Repository, actor: User, new_visibility: Symbol, persist_results: T::Boolean).returns(T.nilable(String)) }
    def self.name_of_ruleset_source_blocking_visibility(repository, actor, new_visibility, persist_results: false)
      name_of_ruleset_source_blocking_operation(repository, actor, { change_visibility: new_visibility }, persist_results:)
    end

    sig { params(repository: Repository, actor: User, persist_results: T::Boolean).returns(T::Boolean) }
    def self.can_create_repository_visibility?(repository, actor, persist_results)
      if repository.member_privilege_rulesets_enabled?
        event = RuleEngine::Events::RepositoryOperationEvent.new(repository, actor, { change_visibility: repository.visibility }, persist_results:)
        result = RuleEngine::GenericEvaluator.evaluate_rules(event).first
        !!result&.action_permitted?
      else
        true
      end
    end

    sig { params(repository: Repository, actor: User, persist_results: T::Boolean).returns(T::Boolean) }
    def self.can_rename_repository?(repository, actor, persist_results)
      if repository.member_privilege_rulesets_enabled?
        event = RuleEngine::Events::RepositoryOperationEvent.new(repository, actor, { rename: nil }, persist_results:)
        result = RuleEngine::GenericEvaluator.evaluate_rules(event).first

        return true if !!result&.action_permitted?

        failed_runs = result&.rule_runs&.filter { |run| !run.allowed? } || []

        if failed_runs.size > 0
          has_more = failed_runs.size > 1
          parameters = failed_runs.first&.rule_config&.parameters
          negate, pattern = if parameters.present?
            [parameters["negate"], parameters["pattern"]]
          end
          repository.errors.add :name, "must #{negate ? "not " : ""}match \"#{pattern}\" per organization policy"
        end

        false
      else
        true
      end
    end

    sig { params(organization: Organization, rule_types: T.nilable(T::Array[String])).returns(T::Boolean) }
    def self.organization_is_protected?(organization, rule_types = nil)
      if organization.member_privilege_rulesets_enabled?
        enabled_rulesets = RepositoryRuleset.load_for(source: organization, include_parents: true, targets: ["repository"]).select { |ruleset| ruleset.enabled? }

        return enabled_rulesets.any? if rule_types.nil?

        GitHub::PrefillAssociations.prefill_associations(enabled_rulesets, [:rule_configurations])

        enabled_rulesets.any? { |ruleset| ruleset.enabled? && ruleset.rule_configurations.any? { |config| rule_types.include?(config.rule_type) } }
      else
        false
      end
    end
  end
end
