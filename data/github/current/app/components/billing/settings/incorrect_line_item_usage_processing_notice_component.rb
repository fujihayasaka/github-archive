# typed: true
# frozen_string_literal: true

class Billing::Settings::IncorrectLineItemUsageProcessingNoticeComponent < ApplicationComponent
  def render?
    GitHub.flipper[:billing_incident_incorrect_usage_flash].enabled?
  end
end
