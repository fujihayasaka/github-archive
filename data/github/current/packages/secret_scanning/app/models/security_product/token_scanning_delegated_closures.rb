# typed: strict
# frozen_string_literal: true

module SecurityProduct
  class TokenScanningDelegatedClosures < Service
    sig do
      params(repository: Repository).void
    end
    def initialize(repository)
      super(repository)
      @token_scanning_security_product = T.let(SecurityProduct::TokenScanning.new(repository), SecurityProduct::TokenScanning)
      @delegated_closures = T.let(SecretScanning::Features::Repo::DelegatedClosures.new(repository), SecretScanning::Features::Repo::DelegatedClosures)
    end

    sig { override.returns(T::Boolean) }
    def enabled?
      @delegated_closures.enabled?
    end

    # Enablement of this service depends entirely on TokenScanning being able to be enabled
    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_enable?(actor:, options:)
      ignore_import = options[:ignore_import] || false

      if !@token_scanning_security_product.enabled?
        Result.new(false, :token_scanning_disabled)
      else
        Result.new(true)
      end
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_enable(actor:, options:)
      @delegated_closures.enable(actor: actor)

      # No audit log event for now
      GitHub.dogstats.increment("repository_secret_scanning_delegated_closures.enable", tags: dogstats_tags)

      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def force_enable(actor:, options: {})
      on_enable(actor: actor, options: options)
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_disable?(actor:, options:)
      Result.new(true)
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_disable(actor:, options:)
      @delegated_closures.disable(actor: actor)

      GitHub.instrument("repository_secret_scanning_delegated_closures.disable", build_instrumentation_payload(actor))
      GitHub.dogstats.increment("repository_secret_scanning_delegated_closures.disable", tags: dogstats_tags)

      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def force_disable(actor:, options: {})
      on_disable(actor: actor, options: options)
    end

    sig { override.returns(Symbol) }
    def to_sym
      :token_scanning_delegated_closures
    end

    sig { override.returns(String) }
    def self.name
      "Secret scanning delegated closures"
    end

    sig { override.params(symbol: T.nilable(SecurityProduct::Result::Error)).returns(String) }
    def self.error_to_message(symbol)
      case symbol
      when :token_scanning_disabled
        "Usage of delegated alert closures can only be toggled on repositories with secret scanning enabled"
      else
        "Failed to toggle enablement of secret scanning delegated closures"
      end
    end

    private

    sig { params(actor: User).returns(T::Hash[Symbol, T.untyped]) }
    def build_instrumentation_payload(actor)
      payload = {
        actor: actor,
        repo: repository
      }

      if repository.in_organization?
        payload[:org] = repository.organization
      end

      payload
    end

    sig { returns(T::Array[String]) }
    def dogstats_tags
      [
        "visibility:#{repository.visibility}",
        "ghas_secret_scanning:#{SecretScanning::Features::Repo::Capabilities.new(repository).ghas_secret_scanning?}",
      ]
    end
  end
end
