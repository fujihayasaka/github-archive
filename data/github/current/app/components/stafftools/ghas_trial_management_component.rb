# typed: strict
# frozen_string_literal: true

class Stafftools::GhasTrialManagementComponent < ViewComponent::Base
  sig { params(billable_entity: T.any(Organization, Business), sku: GitHub::Turboghas::SKU).void }
  def initialize(billable_entity:, sku:)
    @billable_entity = T.let(billable_entity, T.any(Organization, Business))
    @sku = T.let(sku, GitHub::Turboghas::SKU)
    @trial = T.let(make_trial(billable_entity: billable_entity, sku: sku), EnterpriseCloudOnboard::SKUTrial)
  end

  private

  sig { returns(T.any(Organization, Business)) }
  attr_reader :billable_entity

  sig { returns(GitHub::Turboghas::SKU) }
  attr_reader :sku

  sig { returns(EnterpriseCloudOnboard::SKUTrial) }
  attr_reader :trial

  sig { returns(T::Boolean) }
  def trial_enabled?
    trial.enabled?
  end

  sig { returns(T::Boolean) }
  def can_start_trial?
    errors = trial.enablement_errors(actor: User.ghost, api_access: false, stafftools_access: true)
    errors.empty?
  end

  sig { returns(T::Array[String]) }
  def enablement_errors
    trial.enablement_errors(actor: User.ghost, api_access: false, stafftools_access: true)
  end

  sig { returns(T.nilable(Date)) }
  def expires_at
    trial.expires_at
  end

  sig { returns(T::Boolean) }
  def organization?
    billable_entity.is_a?(Organization)
  end

  sig { returns(T::Boolean) }
  def enterprise?
    billable_entity.is_a?(Business)
  end

  sig { returns(String) }
  def trial_form_path
    if enterprise?
      update_stafftools_ghas_trials_path(T.cast(billable_entity, Business).slug, sku.to_param)
    else
      update_stafftools_user_ghas_trials_path(T.cast(billable_entity, Organization).login, sku.to_param)
    end
  end

  sig { returns(String) }
  def redirect_path
    if enterprise?
      stafftools_advanced_security_path(T.cast(billable_entity, Business).slug)
    else
      stafftools_user_advanced_security_path(T.cast(billable_entity, Organization).login)
    end
  end

  sig { returns(T::Boolean) }
  def delegated_billing?
    organization? && billable_entity.delegate_billing_to_business?
  end

  sig { returns(T.nilable(String)) }
  def enterprise_slug
    T.cast(billable_entity, Organization).business&.slug if organization?
  end

  sig { returns(T.nilable(String)) }
  def trial_type_display_name
    sku.title
  end

  sig { returns(String) }
  def trial_type_param
    sku.to_param
  end

  sig { returns(T.nilable(T::Boolean)) }
  def reset_on_expiration?
    trial.reset_on_expiration? if trial_enabled?
  end

  sig { returns(T.nilable(Integer)) }
  def current_trial_duration_days
    return nil unless trial_enabled?
    trial.number_of_days
  end

  sig { returns(T.nilable(Date)) }
  def trial_start_date
    return nil unless trial_enabled?
    T.must(trial.started_at).to_date
  end

  sig { params(billable_entity: T.any(Organization, Business), sku: GitHub::Turboghas::SKU).returns(EnterpriseCloudOnboard::SKUTrial) }
  def make_trial(billable_entity:, sku:)
    case sku
    when GitHub::Turboghas::SKU::SecretSecurity
      EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: billable_entity)
    when GitHub::Turboghas::SKU::CodeSecurity
      EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: billable_entity)
    else
      raise ArgumentError, "Unsupported SKU: #{sku}"
    end
  end
end
