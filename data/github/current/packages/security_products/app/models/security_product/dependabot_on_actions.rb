# typed: true
# frozen_string_literal: true

module SecurityProduct
  class DependabotOnActions < Service
    ACTIONS_RUNNER_ENABLED_KEY = "repository_dependency_updates.actions_runner.enabled".freeze
    ACTIONS_RUNNER_DISABLED_KEY = "repository_dependency_updates.actions_runner.disabled".freeze

    def enabled?
      log_timing do
        repository.config.enabled?(ACTIONS_RUNNER_ENABLED_KEY)
      end
    end

    def can_enable?(actor:, options:)
      log_timing do
        return Result.new(false, :feature_not_available) unless feature_enabled?
        return Result.new(false, :feature_not_available) if repository.actions_disabled?

        Result.new(true)
      end
    end

    def on_enable(actor:, options:)
      log_timing do
        return Result.new(ToggledServiceCollection.create(to_sym, options)) if repository.deleted?

        repository.config.enable(ACTIONS_RUNNER_ENABLED_KEY, actor)
        GlobalInstrumenter.instrument(ACTIONS_RUNNER_ENABLED_KEY, instrumentation_payload)
        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    def on_disable(actor:, options:)
      log_timing do
        dependent_results = disable_dependents(:dependabot_self_hosted, actor: actor, options: options)
        return dependent_results if dependent_results.error?

        return dependent_results if !enabled?

        repository.config.delete(ACTIONS_RUNNER_ENABLED_KEY, actor)

        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    def to_sym
      :dependabot_on_actions
    end

    def self.name
      "Dependabot on Actions"
    end

    def feature_enabled?
      Dependabot.dependabot_on_actions_available_for?(repository)
    end

    def instrumentation_payload
      {
        repository: repository,
        owner: repository.owner
      }
    end

  end
end
