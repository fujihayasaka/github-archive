# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Events
    class RepositoryOperationEvent < RuleEvent

      RepositoryModel = T.type_alias { T.any(Repositories::IRepository, RepositoryAttributes) }

      sig { returns(RepositoryModel) }
      attr_reader :repository_model

      class RepositoryAttributes < T::Struct
        include Conditions::Targetable

        const :id, T.nilable(Integer)
        const :global_relay_id, T.nilable(String)
        const :name, String
        const :custom_properties_effective_values_proc, T.proc.returns(T.nilable(T::Hash[String, T.untyped]))
        const :system_properties_effective_values_proc, T.proc.returns(T.nilable(T::Hash[String, T.untyped]))
        const :owner, T.nilable(User)

        sig { returns(T::Hash[String, T.untyped]) }
        def custom_properties_effective_values
          custom_properties_effective_values_proc.call || {}
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def system_properties_effective_values
          system_properties_effective_values_proc.call || {}
        end

        sig { override.returns(T::Hash[RuleEngine::Conditions::Targetable::Attribute, T.untyped]) }
        def targetable_attributes
          {
            Attribute::RepositoryGlobalId => global_relay_id,
            Attribute::RepositoryName => name,
            Attribute::RepositoryCustomProperties => custom_properties_effective_values_proc,
            Attribute::RepositorySystemProperties => system_properties_effective_values_proc
          }
        end

        sig { override.returns(Promise[T.nilable(RuleEngine::Conditions::Targetable)]) }
        def async_targetable_parent
          parent = if (organization = owner).is_a?(Organization)
            Conditions::Targets::Organization.new(organization:)
          elsif (user = owner).present?
            Conditions::Targets::User.new(user:)
          end
          T.cast(Promise.resolve(parent), Promise[T.nilable(RuleEngine::Conditions::Targetable)])
        end
      end

      sig do
        params(
          repository_model: RepositoryModel,
          actor: Types::Actor,
          operations: T::Hash[Symbol, T.untyped],
          persist_results: T::Boolean,
        ).void
      end
      def initialize(repository_model, actor, operations, persist_results: false)
        super(actor)

        @repository_model = repository_model
        @operations = T.let(operations.map { |k, v| EventActionRepositoryOperation.new(repository_model:, operation: k, operation_value: v) }, T::Array[EventActionRepositoryOperation])
        @persist_results = persist_results
      end

      sig { override.returns(T.nilable(FeatureFlag::IFeatureTarget)) }
      def feature_flag_source
        repository_model.owner
      end

      sig { override.returns(T::Array[EventActionRepositoryOperation]) }
      def event_actions
        @operations
      end

      sig { override.params(rule_suites: T::Array[RuleSuite]).returns(T::Array[RuleSuite]) }
      def finalize_rule_suites(rule_suites)
        rule_suites
      end

      sig { override.params(rule_suites: T::Array[RuleSuite]).void }
      def record_results(rule_suites)
        return unless @persist_results

        ActiveRecord::Base.connected_to(role: :writing) do
          rule_suites.filter(&:should_persist?).each do |rule_suite|
            next unless rule_suite.repository&.repo_policy_bypass_enabled?
            rule_suite.log_evaluation
            rule_suite.save!
          end
        end

        GitHub.context.push(repository_operation_event_rule_suites: rule_suites.map(&:id))
      end

      sig { override.returns(T::Hash[String, T.untyped]) }
      def evaluation_log_data
        super.merge({
          "gh.repo.id" => repository_model.id
        })
      end
    end
  end
end
