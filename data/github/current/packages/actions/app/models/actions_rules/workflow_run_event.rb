# typed: strict
# frozen_string_literal: true

module ActionsRules
  class WorkflowRunEvent < RuleEngine::RuleEvent
    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(String) }
    attr_reader :event_name

    sig do
      params(
        repository: Repository,
        actor: User,
        event_name: String,
        integration: T.nilable(IntegrationInstallation),
      ).void
    end
    def initialize(repository, actor, event_name, integration: nil)
      super(actor)

      @repository = repository
      @event_name = event_name
      @event_action = T.let(
        EventActionWorkflowRun.new(
          repository: repository,
          triggering_actor: actor,
          triggering_integration: integration,
          event_name: event_name,
        ),
        EventActionWorkflowRun,
      )
    end

    sig { override.returns(T.nilable(FeatureFlag::IFeatureTarget)) }
    def feature_flag_source
      repository
    end

    sig { override.returns(T::Array[EventActionWorkflowRun]) }
    def event_actions
      [@event_action]
    end

    sig { override.params(rule_suites: T::Array[RuleEngine::RuleSuite]).returns(T::Array[RuleEngine::RuleSuite]) }
    def finalize_rule_suites(rule_suites)
      rule_suites
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def evaluation_log_data
      super.merge({
        "gh.repo.id" => repository.id,
        "gh.actions.event_name" => event_name,
      })
    end
  end
end
