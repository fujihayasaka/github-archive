# typed: strict
# frozen_string_literal: true

class ProgrammaticAccessTokenLifetimeConfiguration
  extend T::Helpers
  extend T::Sig

  sig { params(configurable: T.any(Business, Organization), pat_type: ProgrammaticAccessTokenType).void }
  def initialize(configurable, pat_type)
    @configurable = configurable
    @pat_type = pat_type
  end

  sig { params(actor: User, expiration: Integer, exempt_administrators: T::Boolean).void }
  def set_maximum_lifetime_configuration(actor, expiration, exempt_administrators)
    if @pat_type == ProgrammaticAccessTokenType::FineGrained
      @configurable.set_fine_grained_personal_access_token_expiration_limit(actor: actor, expiration: expiration)
    else
      @configurable.set_personal_access_token_classic_expiration_limit(actor: actor, expiration: expiration)
    end
  end

  sig { returns(T.nilable(Integer)) }
  def expiration_limit
    if @pat_type == ProgrammaticAccessTokenType::FineGrained
      @configurable.fine_grained_personal_access_token_expiration_limit
    else
      @configurable.personal_access_token_classic_expiration_limit
    end
  end

  sig { params(configurable: T.any(Business, Organization), pat_type: ProgrammaticAccessTokenType).returns(T.nilable(Integer)) }
  def self.expiration_limit_for(configurable, pat_type)
    self.new(configurable, pat_type).expiration_limit
  end

  sig { returns(T::Boolean) }
  def personal_access_token_expiration_limit_enabled?
    if @pat_type == ProgrammaticAccessTokenType::FineGrained
      @configurable.fine_grained_personal_access_token_expiration_limit_enabled?
    else
      @configurable.personal_access_token_classic_expiration_limit_enabled?
    end
  end

  sig { params(actor: User).void }
  def disable_personal_access_token_expiration_limit(actor)
    if @pat_type == ProgrammaticAccessTokenType::FineGrained
      @configurable.disable_fine_grained_personal_access_token_expiration_limit(actor: actor)
    else
      @configurable.disable_personal_access_token_classic_expiration_limit(actor: actor)
    end
    disable_exemptions(actor)
  end

  sig { params(actor: User).void }
  def enable_exemptions(actor)
    return unless @configurable.is_a?(Business)

    if @pat_type == ProgrammaticAccessTokenType::FineGrained
      @configurable.enable_fine_grained_personal_access_token_expiration_limit_exemption(actor: actor)
    else
      @configurable.enable_personal_access_token_classic_expiration_limit_exemption(actor: actor)
    end
  end

  sig { params(actor: User).void }
  def disable_exemptions(actor)
    return unless @configurable.is_a?(Business)

    if @pat_type == ProgrammaticAccessTokenType::FineGrained
      @configurable.disable_fine_grained_personal_access_token_expiration_limit_exemption(actor: actor)
    else
      @configurable.disable_personal_access_token_classic_expiration_limit_exemption(actor: actor)
    end
  end

  sig { returns(T::Boolean) }
  def exemptions_enabled?
    return false unless @configurable.is_a?(Business)

    if @pat_type == ProgrammaticAccessTokenType::FineGrained
      @configurable.fine_grained_personal_access_token_expiration_limit_exemption_enabled?
    else
      @configurable.personal_access_token_classic_expiration_limit_exemption_enabled?
    end
  end

  sig { params(configurable: T.any(Business, Organization), pat_type: ProgrammaticAccessTokenType).returns(T::Boolean) }
  def self.exemptions_enabled_for?(configurable, pat_type)
    self.new(configurable, pat_type).exemptions_enabled?
  end
end
