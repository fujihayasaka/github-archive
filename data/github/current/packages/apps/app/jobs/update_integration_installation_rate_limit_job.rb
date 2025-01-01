# typed: true
# frozen_string_literal: true

class UpdateIntegrationInstallationRateLimitJob < ApplicationJob
  queue_as :update_integration_installation_rate_limit

  discard_on ActiveRecord::RecordNotFound
  retry_on_dirty_exit

  def perform(installation_id)
    installation = ActiveRecord::Base.connected_to(role: :reading) do
      IntegrationInstallation.includes(:integration, :target).find(installation_id)
    end

    installation.recalculate_rate_limit
  end
end
