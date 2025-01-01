
# typed: strict
# frozen_string_literal: true

module Configurable
  # Tracks which entities have enabled an exemption for the personal access token expiration limit
  # This exemption applies to Enterprise Admins
  module PersonalAccessTokenExpirationLimitExemptionEnabled
    extend T::Helpers
    extend T::Sig

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    PAT_CLASSIC_KEY = T.let("personal_access_token_classic_expiration_limit_exemption", String)
    FG_PAT_KEY = T.let("fine_grained_personal_access_token_expiration_limit_exemption", String)

    class ConfigurationError < StandardError; end

    sig { params(actor: ::User).void }
    def enable_personal_access_token_classic_expiration_limit_exemption(actor:)
      enable_personal_access_token_expiration_limit_exemption(actor: actor, key: PAT_CLASSIC_KEY)
    end

    sig { params(actor: ::User).void }
    def disable_personal_access_token_classic_expiration_limit_exemption(actor:)
      disable_personal_access_token_expiration_limit_exemption(actor: actor, key: PAT_CLASSIC_KEY)
    end

    sig { params(actor: ::User).void }
    def enable_fine_grained_personal_access_token_expiration_limit_exemption(actor:)
      enable_personal_access_token_expiration_limit_exemption(actor: actor, key: FG_PAT_KEY)
    end

    sig { params(actor: ::User).void }
    def disable_fine_grained_personal_access_token_expiration_limit_exemption(actor:)
      disable_personal_access_token_expiration_limit_exemption(actor: actor, key: FG_PAT_KEY)
    end

    sig { returns(T::Boolean) }
    def personal_access_token_classic_expiration_limit_exemption_enabled?
      config.enabled?(PAT_CLASSIC_KEY)
    end

    sig { returns(T::Boolean) }
    def fine_grained_personal_access_token_expiration_limit_exemption_enabled?
      config.enabled?(FG_PAT_KEY)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def personal_access_token_classic_expiration_limit_exempted_for?(actor)
      T.bind(self, Business)

      personal_access_token_classic_expiration_limit_exemption_enabled? && (owner?(actor) || billing_manager?(actor))
    end

    private

    sig { params(actor: ::User, key: String).void }
    def enable_personal_access_token_expiration_limit_exemption(actor:, key:)
      return unless config.enable!(key, actor)
      instrument_expiration_limit_exemption(actor, "#{key}_enabled")
    end

    sig { params(actor: ::User, key: String).void }
    def disable_personal_access_token_expiration_limit_exemption(actor:, key:)
      return unless config.delete(key, actor)
      instrument_expiration_limit_exemption(actor, "#{key}_disabled")
    end

    sig { params(actor: ::User, key: String).void }
    def instrument_expiration_limit_exemption(actor, key)
      payload = { user: actor, business: self }
      GitHub.instrument(key, payload)
      GlobalInstrumenter.instrument(key, payload)
    end
  end
end
