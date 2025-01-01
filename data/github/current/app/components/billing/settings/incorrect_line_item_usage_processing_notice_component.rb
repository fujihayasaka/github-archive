# typed: true
# frozen_string_literal: true

class Billing::Settings::IncorrectLineItemUsageProcessingNoticeComponent < ApplicationComponent
  def render?
    FeatureFlag.vexi.enabled?(:billing_incident_incorrect_usage_flash, default: false)
  end
end
