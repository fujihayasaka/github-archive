# typed: strict
# frozen_string_literal: true

module SecurityProduct
  class TokenScanningPartnerMetadata < Service
    sig { params(repository: Repository).void }
    def initialize(repository)
      super(repository)
      @partner_metadata = T.let(SecretScanning::Features::Repo::PartnerMetadata.new(repository), SecretScanning::Features::Repo::PartnerMetadata)
    end


    sig { override.returns(T::Boolean) }
    def enabled?
      @partner_metadata.enabled?
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_enable?(actor:, options:)
      @partner_metadata.feature_available? ? Result.new(true) : Result.new(false, :token_scanning_partner_metadata_unavailable)
    end

    sig do
      override
      .params(
        actor: User,
        options: T.untyped
      )
      .returns(SecurityProduct::Result)
    end
    def on_disable(actor:, options:)
      @partner_metadata.disable(actor: actor)
      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    sig do
      override
      .params(
        actor: User,
        options: T.untyped
      )
      .returns(SecurityProduct::Result)
    end
    def on_enable(actor:, options:)
      return Result.new(ToggledServiceCollection.empty) unless @partner_metadata.feature_available?
      @partner_metadata.enable(actor: actor)

      Result.new(ToggledServiceCollection.create(to_sym, options))
    end

    sig { override.returns(Symbol) }
    def to_sym
      :token_scanning_partner_metadata
    end
  end
end
