# typed: true
# frozen_string_literal: true

class Billing::Settings::ZuoraMaintenanceBannerComponent < ApplicationComponent
  # zuora_maintenance_enabled - Boolean indicating whether the `zuora_maintenance` feature flag is enabled
  def initialize(zuora_maintenance_enabled:)
    @zuora_maintenance_enabled = zuora_maintenance_enabled
  end

  private

  def render?
    @zuora_maintenance_enabled && GitHub.billing_enabled?
  end
end
