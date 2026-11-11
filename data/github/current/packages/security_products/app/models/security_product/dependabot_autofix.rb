# typed: true
# frozen_string_literal: true

module SecurityProduct
  class DependabotAutofix < Service
    AUTOFIX_ENABLED_KEY = "repository_dependency_updates.autofix.enabled".freeze
    AUTOFIX_DISABLED_KEY = "repository_dependency_updates.autofix.disabled".freeze

    def enabled?
      log_timing do
        return unless feature_enabled?
        return false if repository.actions_disabled?
        repository.config.enabled?(AUTOFIX_ENABLED_KEY)
      end
    end

    def can_enable?(actor:, options:)
      log_timing do
        return Result.new(false, :feature_not_available) if repository.public? || !feature_enabled?
        return Result.new(false, :actions_disabled) if repository.actions_disabled?
        Result.new(true)
      end
    end

    def on_enable(actor:, options:)
      log_timing do
        # If the repository is public, we treat this as a noop rather than an error.
        return Result.new(ToggledServiceCollection.empty) if repository.public?
        return Result.new(ToggledServiceCollection.create(to_sym, options)) if repository.deleted?

        repository.config.enable(AUTOFIX_ENABLED_KEY, actor)
        GlobalInstrumenter.instrument(AUTOFIX_ENABLED_KEY, instrumentation_payload)
        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    def on_disable(actor:, options:)
      log_timing do
        repository.config.delete(AUTOFIX_ENABLED_KEY, actor)

        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    def to_sym
      :dependabot_autofix
    end

    def self.name
      "Dependabot Autofix"
    end

    def self.error_to_message(symbol)
      case symbol
      when :actions_disabled
        "Dependabot Autofix cannot be enabled because GitHub Actions is disabled for this repository."
      else
        super
      end
    end

    def feature_enabled?
      Dependabot.dependabot_autofix_available_for?(repository)
    end

    def instrumentation_payload
      {
        repository: repository,
        owner: repository.owner
      }
    end
  end
end
