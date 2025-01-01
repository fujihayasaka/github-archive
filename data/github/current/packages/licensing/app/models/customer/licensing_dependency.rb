# typed: strict
# frozen_string_literal: true

module Customer::LicensingDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Customer }

  included do
    T.bind(self, T.class_of(Customer))

    has_many :licensing_model_transitions, class_name: "Licensing::LicensingModelTransition", dependent: :destroy
  end

  sig do
    params(
      licensing_model: String,
      actor: T.nilable(User),
      transition_date: T.nilable(T.any(Date, String)),
      ghas_only: T.nilable(T::Boolean),
      reset_ghas_configuration: T.nilable(T::Boolean),
      unbundle_ghas: Symbol
    ).returns(Licensing::LicensingModelTransition)
  end
  def new_licensing_model_transition(licensing_model:, actor: User.ghost, transition_date: Date.current, ghas_only: false, reset_ghas_configuration: false, unbundle_ghas: :noop_ghas)
    ::Licensing::LicensingModelTransition.new(
      customer: self,
      licensing_model: licensing_model,
      transition_date: transition_date,
      status: "scheduled",
      actor: actor,
      reset_ghas_configuration: reset_ghas_configuration,
      ghas_only: ghas_only,
      unbundle_ghas: unbundle_ghas
    )
  end

  sig { returns(T::Hash[T::untyped, T::untyped]) }
  def to_licensify_customer_payload
    entity = self.billable_owner

    {
      id: id,
      sdlcLicensingModel: sdlc_licensify_licensing_model,
      sdlcTrial: !!business&.trial?,
      ghasLicensingModel: ghas_licensify_licensing_model,
      ghasTrial: ghas_trial_enabled?(entity),
      codeSecurityLicensingModel: code_security_licensify_licensing_model,
      codeSecurityTrial: code_security_trial_enabled?(entity),
      secretProtectionLicensingModel: secret_protection_licensify_licensing_model,
      secretProtectionTrial: secret_protection_trial_enabled?(entity),
    }
  end

  private

  sig { params(entity: T.nilable(T.any(User, Business))).returns(T::Boolean) }
  def ghas_trial_enabled?(entity)
    return false unless entity.is_a?(Business)

    self_serve_trial_enabled?(entity) && entity.ghas_sku_purchased_for_entity?
  end

  sig { params(entity: T.nilable(T.any(User, Organization, Business))).returns(T::Boolean) }
  def code_security_trial_enabled?(entity)
    return false unless entity.is_a?(Organization) || entity.is_a?(Business)

    (self_serve_trial_enabled?(entity) && entity.code_security_purchased_for_entity?) ||
      EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: entity).enabled?
  end

  sig { params(entity: T.nilable(T.any(User, Organization, Business))).returns(T::Boolean) }
  def secret_protection_trial_enabled?(entity)
    return false unless entity.is_a?(Organization) || entity.is_a?(Business)

    (self_serve_trial_enabled?(entity) && entity.secret_protection_purchased_for_entity?) ||
      EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: entity).enabled?
  end

  sig { params(entity: T.any(User, Organization, Business)).returns(T::Boolean) }
  def self_serve_trial_enabled?(entity)
    entity.is_a?(Business) && entity.has_active_advanced_security_trial?
  end

  sig { returns(Integer) }
  def ghas_licensify_licensing_model
    entity = self.billable_owner
    return Licensify::Services::V1::LicensingModel::LICENSING_MODEL_VOLUME unless entity&.is_a?(Organization) || entity&.is_a?(Business)

    enabled_type = entity.advanced_security_enabled_type_for_entity

    case enabled_type
    when Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME
      Licensify::Services::V1::LicensingModel::LICENSING_MODEL_VOLUME
    when Configurable::AdvancedSecurityBillingConfig::GHAS_METERED
      Licensify::Services::V1::LicensingModel::LICENSING_MODEL_METERED
    else
      Licensify::Services::V1::LicensingModel::LICENSING_MODEL_VOLUME
    end
  end

  sig { returns(Integer) }
  def code_security_licensify_licensing_model
    entity = self.billable_owner
    return Licensify::Services::V1::LicensingModel::LICENSING_MODEL_VOLUME unless entity&.is_a?(Organization) || entity&.is_a?(Business)

    enabled_type = entity.advanced_security_enabled_type_for_entity

    case enabled_type
    when Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME,
         Configurable::AdvancedSecurityBillingConfig::CODE_SECURITY_VOLUME
      Licensify::Services::V1::LicensingModel::LICENSING_MODEL_VOLUME
    when Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED
      Licensify::Services::V1::LicensingModel::LICENSING_MODEL_METERED
    else
      Licensify::Services::V1::LicensingModel::LICENSING_MODEL_VOLUME
    end
  end

  sig { returns(Integer) }
  def secret_protection_licensify_licensing_model
    entity = self.billable_owner
    return Licensify::Services::V1::LicensingModel::LICENSING_MODEL_VOLUME unless entity&.is_a?(Organization) || entity&.is_a?(Business)

    enabled_type = entity.advanced_security_enabled_type_for_entity

    case enabled_type
    when Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME,
         Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME
      Licensify::Services::V1::LicensingModel::LICENSING_MODEL_VOLUME
    when Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED
      Licensify::Services::V1::LicensingModel::LICENSING_MODEL_METERED
    else
      Licensify::Services::V1::LicensingModel::LICENSING_MODEL_VOLUME
    end
  end

  sig { returns(Integer) }
  def sdlc_licensify_licensing_model
    if metered_plan?
      return Licensify::Services::V1::LicensingModel::LICENSING_MODEL_METERED
    end

    Licensify::Services::V1::LicensingModel::LICENSING_MODEL_VOLUME
  end
end
