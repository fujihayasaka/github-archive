# typed: strict
# frozen_string_literal: true

class Stafftools::AdvancedSecurity::GhasUnbundleTransitionComponent < ApplicationComponent
  sig { returns(Business) }
  attr_reader :business

  sig { returns(T.nilable(Licensing::GhasUnbundleTransition)) }
  attr_reader :transition

  sig { params(business: Business, transition: T.nilable(Licensing::GhasUnbundleTransition)).void }
  def initialize(business:, transition: nil)
    @business = business
    @transition = transition
  end

  sig { returns(String) }
  def target_sku_state
    business.advanced_security_products_bundled? ? "unbundled" : "bundled"
  end

  sig { returns(T::Boolean) }
  def target_sku_state_bundled?
    target_sku_state == "bundled"
  end

  sig { returns(T::Boolean) }
  def show_bundle_unbundle_action?
    return true if target_sku_state_bundled?

    self_serve = !@business.sales_managed?
    enabled_type = @business.advanced_security_enabled_type_for_entity
    is_volume = enabled_type == Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME ||
      enabled_type == Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME ||
      enabled_type == Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME ||
      enabled_type == Configurable::AdvancedSecurityBillingConfig::CODE_SECURITY_VOLUME
    if self_serve && is_volume
      return false
    end
    true
  end


  sig { params(target_sku_state: T.nilable(String)).returns(String) }
  def target_sku_state_text(target_sku_state: nil)
    text = nil
    if target_sku_state.present?
      text = target_sku_state == "bundled" ? "bundled GHAS" : "unbundled SKUs"
    else
      text = business.advanced_security_products_bundled? ? "unbundled SKUs" : "bundled GHAS"
    end

    text
  end
end
