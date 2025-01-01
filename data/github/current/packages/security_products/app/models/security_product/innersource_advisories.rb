# typed: strict
# frozen_string_literal: true

module SecurityProduct
  # This service inverts enable/disable behaviour for innersource advisories. This is because we want to have
  # innersource advisories enabled by default for all repos, so we use the presence of a key to indicate that
  # innersource advisories are disabled.
  class InnersourceAdvisories < Service
    DISABLED_KEY = T.let("innersource_advisories.disabled".freeze, String)

    # Currently always return true so that repos that cannot turn on innersource advisories do not get an error
    # when doing full enablement of all services.
    sig { override.params(actor: User, options: T::Hash[Symbol, T.untyped]).returns(SecurityProduct::Result) }
    def can_enable?(actor:, options:)
      log_timing do
        Result.new(true)
      end
    end

    sig { override.params(actor: User, options: T::Hash[Symbol, T.untyped]).returns(SecurityProduct::Result) }
    def can_disable?(actor:, options:)
      log_timing do
        Result.new(true)
      end
    end

    sig { override.params(actor: User, options: T::Hash[Symbol, T.untyped]).returns(SecurityProduct::Result) }
    def on_enable(actor:, options:)
      log_timing do
        # No-op if the repo is not authorized to avoid causing an error for repos not enrolled in the innersource beta.
        return Result.new(ToggledServiceCollection.empty) unless AdvisoryDB::Innersource.eligible_repo?(repo: repository) || options[:force?].present?

        repository.config.delete(DISABLED_KEY, actor)

        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    sig { override.params(actor: User, options: T::Hash[Symbol, T.untyped]).returns(SecurityProduct::Result) }
    def on_disable(actor:, options:)
      log_timing do
        repository.config.enable(DISABLED_KEY, actor)

        Result.new(ToggledServiceCollection.create(to_sym, options))
      end
    end

    # should return true or false
    sig { override.returns(T::Boolean) }
    def enabled?
      log_timing do
        GitHub.repository_advisories_enabled? &&
          AdvisoryDB::Innersource.eligible_repo?(repo: repository) &&
          !repository.config.enabled?(DISABLED_KEY)
      end
    end

    sig { override.returns(Symbol) }
    def to_sym
      :innersource_advisories
    end

    sig { override.returns(String) }
    def self.name
      "Innersource Advisories"
    end

    sig { override.params(symbol: T.nilable(SecurityProduct::Result::Error)).returns(String) }
    def self.error_to_message(symbol)
      "Failed to toggle #{self.name.downcase}. Reason: #{symbol}."
    end
  end
end
