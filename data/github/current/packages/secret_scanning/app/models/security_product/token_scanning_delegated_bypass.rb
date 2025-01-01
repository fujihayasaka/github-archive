# typed: strict
# frozen_string_literal: true

module SecurityProduct
  class TokenScanningDelegatedBypass < Service
    sig do
      params(repository: Repository).void
    end
    def initialize(repository)
      super(repository)
      @token_scanning_security_product = T.let(SecurityProduct::TokenScanning.new(repository), SecurityProduct::TokenScanning)
      @push_protection_security_product = T.let(SecurityProduct::TokenScanningPushProtection.new(repository), SecurityProduct::TokenScanningPushProtection)
      @delegated_bypass = T.let(SecretScanning::Features::Repo::DelegatedBypass.new(repository), SecretScanning::Features::Repo::DelegatedBypass)
    end

    sig { override.returns(T::Boolean) }
    def enabled?
      @delegated_bypass.enabled?
    end

    # Enablement of this service depends entirely on TokenScanning and Push Protection being able to be enabled
    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_enable?(actor:, options:)
      ignore_import = options[:ignore_import] || false

      if !@token_scanning_security_product.enabled?
        Result.new(false, :token_scanning_disabled)
      elsif !@push_protection_security_product.enabled?(ignore_import: ignore_import)
        Result.new(false, :token_scanning_push_protection_disabled)
      else
        Result.new(true)
      end
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_enable(actor:, options:)
      @delegated_bypass.enable(actor: actor)

      GitHub.instrument("repository_secret_scanning_push_protection_bypass_list.enable", build_instrumentation_payload(actor))
      GitHub.dogstats.increment("repository_secret_scanning_push_protection_bypass_list.enable", tags: dogstats_tags)

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
      @delegated_bypass.disable(actor: actor)

      GitHub.instrument("repository_secret_scanning_push_protection_bypass_list.disable", build_instrumentation_payload(actor))
      GitHub.dogstats.increment("repository_secret_scanning_push_protection_bypass_list.disable", tags: dogstats_tags)

      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def force_disable(actor:, options: {})
      on_disable(actor: actor, options: options)
    end

    sig { override.returns(Symbol) }
    def to_sym
      :token_scanning_delegated_bypass
    end

    sig { override.returns(String) }
    def self.name
      "Secret scanning delegated bypass"
    end

    sig { override.params(symbol: T.nilable(SecurityProduct::Result::Error)).returns(String) }
    def self.error_to_message(symbol)
      case symbol
      when :token_scanning_disabled
        "Usage of delegated bypass reviewers can only be toggled on repositories with secret scanning enabled"
      when :token_scanning_push_protection_disabled
        "Usage of delegated bypass reviewers can only be toggled on repositories with secret scanning push protection enabled"
      else
        "Failed to toggle enablement of secret scanning delegated bypass reviewers"
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
