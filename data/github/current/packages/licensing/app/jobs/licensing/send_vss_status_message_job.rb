# typed: true
# frozen_string_literal: true

class Licensing::SendVssStatusMessageJob < ApplicationJob
  queue_as :licensing
  retry_on_dirty_exit

  retry_on Faraday::Error, GitHub::AzureServiceBus::HttpClient::FailedRequestError, wait: :polynomially_longer, attempts: 20

  locked_by key: -> (job) { job.locking_key }, timeout: 5.minutes

  LOCK_KEY_PREFIX = "licensing/send_vss_status_message_job"
  QUIET_PERIOD_SECONDS = 30
  CLIENT_CONFIG = {
    queue_name: GitHub.vss_status_messages_queue_name,
    connection_string: GitHub.vss_status_messages_connection_string
  }.freeze

  before_enqueue do
    throw(:abort) unless GitHub.billing_enabled?
  end

  def perform(assignment:, event_type: nil)
    GitHub.dogstats.increment("send_vss_status_message_job", tags: ["perform:perform"])
    if assignment.updated_at > QUIET_PERIOD_SECONDS.seconds.ago
      GitHub.dogstats.increment("send_vss_status_message_job", tags: ["perform:delayed"])
      clear_lock
      self.class.
        set(wait_until: assignment.updated_at + QUIET_PERIOD_SECONDS.seconds).
        perform_later(assignment: assignment, event_type: event_type)
      return
    else
      GitHub.dogstats.increment("send_vss_status_message_job", tags: ["perform:not_delayed"])
    end

    event_type_to_send = Licensing::BundledLicenseAssignmentStatusCalculator.calculate_highest_priority(assignment, requested_status: event_type)
    message = Licensing::Vss::StatusMessage.new(
      event_type: event_type_to_send,
      assignment: assignment
    ).serialize_message

    service_bus_client.send_message(message)
    assignment.instrument("status_message_sent", status_sent: event_type_to_send)
    GitHub.dogstats.increment("send_vss_status_message_job", tags: ["perform:performed"])
  end

  def locking_key
    "#{LOCK_KEY_PREFIX}:#{arguments.first[:assignment].id}"
  end

  private

  def service_bus_client
    @service_bus_client ||= GitHub::AzureServiceBus::QueueClient.new(**CLIENT_CONFIG)
  end
end
