# typed: strict
# frozen_string_literal: true

module SecurityProduct
  class DependabotOnActions < Service
    ACTIONS_RUNNER_ENABLED_KEY = T.let("repository_dependency_updates.actions_runner.enabled".freeze, String)
    ACTIONS_RUNNER_DISABLED_KEY = T.let("repository_dependency_updates.actions_runner.disabled".freeze, String)

    sig { override.returns(T::Boolean) }
    def enabled?
      log_timing do
        return false if repository.actions_disabled?

        repository.config.enabled?(ACTIONS_RUNNER_ENABLED_KEY)
      end
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_enable?(actor:, options:)
      log_timing do
        return Result.new(false, :actions_disabled) if repository.actions_disabled?

        Result.new(true)
      end
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_enable(actor:, options:)
      log_timing do
        return Result.new(ToggledServiceCollection.create(to_sym, options)) if repository.deleted?

        repository.config.enable(ACTIONS_RUNNER_ENABLED_KEY, actor)
        GlobalInstrumenter.instrument(ACTIONS_RUNNER_ENABLED_KEY, instrumentation_payload)
        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_disable(actor:, options:)
      log_timing do
        dependent_results = disable_dependents(:dependabot_self_hosted, actor: actor, options: options)
        return dependent_results if dependent_results.error?

        return dependent_results if !enabled?

        repository.config.delete(ACTIONS_RUNNER_ENABLED_KEY, actor)

        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    sig { override.returns(Symbol) }
    def to_sym
      :dependabot_on_actions
    end

    sig { override.returns(String) }
    def self.name
      "Dependabot on Actions"
    end

    sig { override.params(symbol: T.nilable(SecurityProduct::Result::Error)).returns(String) }
    def self.error_to_message(symbol)
      case symbol
      when :actions_disabled
        "Dependabot on Actions cannot be enabled because GitHub Actions is disabled for this repository."
      else
        super
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def instrumentation_payload
      {
        repository: repository,
        owner: repository.owner
      }
    end

  end
end
