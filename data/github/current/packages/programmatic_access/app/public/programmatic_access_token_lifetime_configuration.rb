# typed: strict
# frozen_string_literal: true

class ProgrammaticAccessTokenLifetimeConfiguration
  MAX_ORGANIZATIONS_TO_DISPLAY = 100
  EXPIRATION_LIMIT_CONFIG_NAMES = T.let({
    ProgrammaticAccessTokenType::FineGrained => Configurable::PersonalAccessTokenExpirationLimit::FG_PAT_KEY,
    ProgrammaticAccessTokenType::Classic => Configurable::PersonalAccessTokenExpirationLimit::PAT_CLASSIC_KEY
  }.freeze, T::Hash[ProgrammaticAccessTokenType, String])

  extend T::Helpers


  sig { params(configurable: T.any(Business, Organization), pat_type: ProgrammaticAccessTokenType).void }
  def initialize(configurable, pat_type)
    @configurable = configurable
    @pat_type = pat_type
  end

  sig { params(target: T.any(Business, Organization, User)).returns(T.nilable(T.any(Business, Organization))) }
  def self.limit_enforcer_for(target)
    case target
    when Business, Organization
      target
    when User
      business_target_for_user(target)
    end
  end

  sig { params(business: Business, pat_type: ProgrammaticAccessTokenType, limit: Integer).returns(ActiveRecord::Relation) }
  def self.business_organizations_exceeding_limit(business, pat_type, limit)
    config_key = EXPIRATION_LIMIT_CONFIG_NAMES.fetch(pat_type)

    org_ids = business.organizations.pluck(:id)
    return Organization.none if org_ids.empty?

    exceeding_org_ids = Configuration::Entry
      .where(target_type: "User", target_id: org_ids, name: config_key)
      .where("CAST(value AS SIGNED) > ?", limit)
      .limit(MAX_ORGANIZATIONS_TO_DISPLAY + 1)
      .pluck(:target_id)

    business.organizations.where(id: exceeding_org_ids)
  end

  sig { params(actor: User, expiration: Integer, exempt_administrators: T::Boolean, exempt_missing_issue_date: T::Boolean).void }
  def set_maximum_lifetime_configuration(actor, expiration, exempt_administrators = false, exempt_missing_issue_date = false)
    old_limit = expiration_limit
    if @pat_type == ProgrammaticAccessTokenType::FineGrained
      @configurable.set_fine_grained_personal_access_token_expiration_limit(actor: actor, expiration: expiration)
    else
      @configurable.set_personal_access_token_classic_expiration_limit(actor: actor, expiration: expiration)
    end

    if exempt_administrators
      enable_exemptions(actor)
    else
      disable_exemptions(actor)
    end

    if exempt_missing_issue_date
      enable_issued_at_exemption(actor)
    else
      disable_issued_at_exemption(actor)
    end

    instrument_lifetime_configuration(actor, expiration, old_limit, exempt_administrators)
  end

  sig { returns(T.nilable(T.any(Business, Organization))) }
  def target_with_limit
    return nil if @configurable.user?

    if @pat_type == ProgrammaticAccessTokenType::FineGrained
      @configurable.fine_grained_personal_access_token_expiration_limit_target
    else
      @configurable.personal_access_token_classic_expiration_limit_target
    end
  end

  sig { returns(T.nilable(String)) }
  def target_and_type_with_limit
    target = target_with_limit
    return nil unless target

    type = target.organization? ? "organization" : "enterprise"
    "#{target.display_login} #{type}"
  end

  sig { params(ignore_inheritance: T::Boolean).returns(T.nilable(Integer)) }
  def expiration_limit(ignore_inheritance: false)
    if @pat_type == ProgrammaticAccessTokenType::FineGrained
      @configurable.fine_grained_personal_access_token_expiration_limit(ignore_inheritance: ignore_inheritance)
    else
      @configurable.personal_access_token_classic_expiration_limit(ignore_inheritance: ignore_inheritance)
    end
  end

  sig { params(configurable: T.nilable(T.any(User, Business, Organization)), pat_type: ProgrammaticAccessTokenType).returns(T.nilable(Integer)) }
  def self.expiration_limit_for(configurable, pat_type)
    return nil if configurable.nil?
    if configurable.user?
      configurable = T.cast(configurable, User)
      return expiration_limit_for(business_target_for_user(configurable), pat_type)
    end

    configurable = T.cast(configurable, T.any(Business, Organization))
    self.new(configurable, pat_type).expiration_limit
  end

  sig { params(user: User).returns(T.nilable(Business)) }
  def self.business_target_for_user(user)
    GitHub.enterprise? ? GitHub.global_business : user.enterprise_managed_business
  end

  sig { params(ignore_inheritance: T::Boolean).returns(T::Boolean) }
  def personal_access_token_expiration_limit_enabled?(ignore_inheritance: false)
    if @pat_type == ProgrammaticAccessTokenType::FineGrained
      @configurable.fine_grained_personal_access_token_expiration_limit_enabled?(ignore_inheritance: ignore_inheritance)
    else
      @configurable.personal_access_token_classic_expiration_limit_enabled?(ignore_inheritance: ignore_inheritance)
    end
  end

  sig { params(actor: User).void }
  def disable_personal_access_token_expiration_limit(actor)
    old_expiration = expiration_limit
    if @pat_type == ProgrammaticAccessTokenType::FineGrained
      @configurable.disable_fine_grained_personal_access_token_expiration_limit(actor: actor)
    else
      @configurable.disable_personal_access_token_classic_expiration_limit(actor: actor)
    end
    disable_exemptions(actor)
    disable_issued_at_exemption(actor)
    instrument_disable_lifetime_configuration(actor, old_expiration)
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

  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def exempted_for?(actor)
    return false unless actor
    target = @configurable.is_a?(Business) ? @configurable : @configurable.business
    return false unless target

    if @pat_type == ProgrammaticAccessTokenType::FineGrained
      target.fine_grained_personal_access_token_expiration_limit_exempted_for?(actor)
    else
      target.personal_access_token_classic_expiration_limit_exempted_for?(actor)
    end
  end

  sig { params(configurable: T.any(Business, Organization), pat_type: ProgrammaticAccessTokenType).returns(T::Boolean) }
  def self.exemptions_enabled_for?(configurable, pat_type)
    self.new(configurable, pat_type).exemptions_enabled?
  end

  sig { returns(T::Boolean) }
  def issued_at_exemption_enabled?
    target = @configurable.is_a?(Business) ? @configurable : @configurable.business
    return false unless target

    if @pat_type == ProgrammaticAccessTokenType::FineGrained
      false # Fine grained PATs does not have a missing creation date exemption
    else
      target.personal_access_token_classic_missing_issued_at_exemption_enabled?
    end
  end

  sig { params(actor: User).void }
  def enable_issued_at_exemption(actor)
    return unless GitHub.enterprise?
    return unless @configurable.is_a?(Business)

    if @pat_type == ProgrammaticAccessTokenType::Classic
      @configurable.enable_personal_access_token_classic_missing_issued_at_exemption(actor: actor)
    end
  end

  sig { params(actor: User).void }
  def disable_issued_at_exemption(actor)
    return unless @configurable.is_a?(Business)

    if @pat_type == ProgrammaticAccessTokenType::Classic
      @configurable.disable_personal_access_token_classic_missing_issued_at_missing_exemption(actor: actor)
    end
  end

  private

  sig { params(actor: User, new_expiration: T.nilable(Integer), old_expiration: T.nilable(Integer), exempt_administrators: T::Boolean).void }
  def instrument_lifetime_configuration(actor, new_expiration, old_expiration, exempt_administrators = false)
    payload = lifetime_configuration_instrumentation_payload(actor)
    payload[:token_expiration] = new_expiration
    payload[:old_token_expiration] = old_expiration
    payload[:exempt_administrators] = exempt_administrators

    GitHub.instrument("personal_access_token.expiration_limit_set", payload)
  end

  sig { params(actor: User, old_expiration: T.nilable(Integer)).void }
  def instrument_disable_lifetime_configuration(actor, old_expiration)
    payload = lifetime_configuration_instrumentation_payload(actor)
    payload[:old_token_expiration] = old_expiration

    GitHub.instrument("personal_access_token.expiration_limit_unset", payload)
  end

  sig { params(actor: User).returns(T::Hash[Symbol, T.untyped]) }
  def lifetime_configuration_instrumentation_payload(actor)
    payload = { actor: actor, programmatic_access_type: @pat_type.name }

    case @configurable
    when ::Business
      payload[:business] = @configurable
    when ::Organization
      payload[:org] = @configurable
      payload[:business] = @configurable.business if @configurable.business
    end

    payload
  end
end
