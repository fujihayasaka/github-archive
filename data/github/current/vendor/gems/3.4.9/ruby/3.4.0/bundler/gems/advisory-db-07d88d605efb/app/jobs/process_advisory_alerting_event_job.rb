# frozen_string_literal: true

# Consumes incoming AdvisoryAlertingEvent hydro messages and delegates handling to the AdvisoryAlertingEvent model
class ProcessAdvisoryAlertingEventJob < ApplicationJob
  queue_as :high

  def perform(message)
    AdvisoryAlertingEvent.create_or_update_from_hydro(message)
  end
end
