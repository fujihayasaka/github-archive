# typed: true
# frozen_string_literal: true

class Stafftools::GhasTrialsSectionComponent < ViewComponent::Base
  def initialize(billable_entity:)
    @billable_entity = billable_entity
  end

  private

  attr_reader :billable_entity

  def unified_trials_enabled?
    billable_entity.is_a?(Business) && FeatureFlag.vexi.enabled?(:unified_self_serve_ghas_trials, billable_entity, default: false)
  end

  def secret_security_sku
    GitHub::Turboghas::SKU::SecretSecurity
  end

  def code_security_sku
    GitHub::Turboghas::SKU::CodeSecurity
  end
end
