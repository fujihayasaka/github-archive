# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class AlertDismissalRequestModalComponent < ApplicationComponent
    attr_reader :request_path, :alert_number, :button_system_arguments, :bulk_items_system_arguments, :system_arguments

    renders_one :summary

    def initialize(dismissal_path:, alert_number: nil, button_system_arguments: {}, bulk_items_system_arguments: {}, **system_arguments)
      @request_path = dismissal_path  # Keep the same parameter name for compatibility
      @alert_number = alert_number
      @button_system_arguments = button_system_arguments
      @bulk_items_system_arguments = bulk_items_system_arguments
      @system_arguments = system_arguments
    end

    def dismissal_reasons
      RepositoryVulnerabilityAlert::DISMISS_REASONS
    end
  end
end
