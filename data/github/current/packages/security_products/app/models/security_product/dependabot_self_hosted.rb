# typed: strict
# frozen_string_literal: true

module SecurityProduct
  class DependabotSelfHosted < Service
    SELF_HOSTED_ENABLED_KEY = T.let("repository_dependency_updates.self_hosted.enabled".freeze, String)
    SELF_HOSTED_DISABLED_KEY = T.let("repository_dependency_updates.self_hosted.disabled".freeze, String)

    sig { override.returns(T::Boolean) }
    def enabled?
      log_timing do
        return false if repository.actions_disabled?
        return false if repository.public?

        repository.config.enabled?(SELF_HOSTED_ENABLED_KEY)
      end
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_enable?(actor:, options:)
      log_timing do
        return Result.new(false, :feature_not_available) if repository.public? || !feature_enabled?
        return Result.new(false, :actions_disabled) if repository.actions_disabled?
        Result.new(true)
      end
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_enable(actor:, options:)
      log_timing do
        # If the repository is public, we treat this as a noop rather than an error.
        return Result.new(ToggledServiceCollection.empty) if repository.public?
        return Result.new(ToggledServiceCollection.create(to_sym, options)) if repository.deleted?

        repository.config.enable(SELF_HOSTED_ENABLED_KEY, actor)
        GlobalInstrumenter.instrument(SELF_HOSTED_ENABLED_KEY, instrumentation_payload)
        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_disable(actor:, options:)
      log_timing do
        repository.config.delete(SELF_HOSTED_ENABLED_KEY, actor)

        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    sig { override.returns(Symbol) }
    def to_sym
      :dependabot_self_hosted
    end

    sig { override.returns(String) }
    def self.name
      "Dependabot Self Hosted Runners"
    end

    sig { override.params(symbol: T.nilable(SecurityProduct::Result::Error)).returns(String) }
    def self.error_to_message(symbol)
      case symbol
      when :actions_disabled
        "Dependabot Self Hosted Runners cannot be enabled because GitHub Actions is disabled for this repository."
      else
        super
      end
    end

    sig { returns(T::Boolean) }
    def feature_enabled?
      true
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def instrumentation_payload
      {
        repository: repository,
        owner: repository.owner
      }
    end

    # Public: Return runner configuration for Dependabot to consume.
    # Uses Configurable module's automatic inheritance: Repository → Organization → Default
    #
    # Returns:
    #   nil if settings are unavailable or not enabled.
    #   Otherwise, a Hash with the following keys:
    #     :runner_labels - Array<String>: The labels to use for the runner.
    #     :runner_group  - String or nil: The runner group name.
    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def dependabot_runner_settings
      return nil unless Dependabot.dependabot_runner_settings_available_for?(repository)
      return nil unless enabled?

      return nil unless repository.respond_to?(:dependabot_runner_settings)

      repository.dependabot_runner_settings
    end
  end
end
