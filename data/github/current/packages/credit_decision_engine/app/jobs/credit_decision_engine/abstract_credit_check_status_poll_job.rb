# typed: strict
# frozen_string_literal: true

class CreditDecisionEngine::AbstractCreditCheckStatusPollJob < ApplicationJob
  extend T::Helpers

  abstract!

  retry_on_dirty_exit
  retry_on Faraday::Error, GitHub::AzureServiceBus::HttpClient::FailedRequestError, wait: :polynomially_longer, attempts: 5

  DEFAULT_TIMEOUT_IN_SECONDS = 5

  sig { params(credit_checks_to_process: Integer).void }
  def process_credit_checks(credit_checks_to_process:)
    credit_check_count = 0
    GitHub.dogstats.increment("get_credit_check_status_message_job", tags: ["polling"])

    while credit_check_count < credit_checks_to_process do
      message = service_bus_client.peek_lock_message(timeout: DEFAULT_TIMEOUT_IN_SECONDS)
      return if message.nil?

      GitHub.dogstats.increment("get_credit_check_status_message_job", tags: ["processing"])
      body = message.body
      response = CreditDecisionEngine::ServiceBusResponse.parse(response: JSON.parse(body, symbolize_names: true))
      process_credit_check(request_id: response.request_id, status: response.status)
      service_bus_client.delete_message(message)
      credit_check_count += 1
      GitHub.dogstats.increment("get_credit_check_status_message_job", tags: ["processed"])

      GitHub.logger.info("credit_decision_engine_status_message.success",
      "gh.credit_decision_engine_status_message.reference_id": response.reference_id,
      "gh.credit_decision_engine_status_message.request_id": response.request_id,
      "gh.credit_decision_engine_status_message.status": response.status,
      )
    end
  rescue CreditDecisionEngine::ServiceBusResponseError, JSON::ParserError => e
    Failbot.report(e)
    GitHub.dogstats.increment("get_credit_check_status_message_job", tags: ["failed"])
    raise
  end

  private

  sig { abstract.params(request_id: String, status: Symbol).void }
  def process_credit_check(request_id:, status:); end

  sig { returns(GitHub::AzureServiceBus::QueueClient) }
  def service_bus_client
    @service_bus_client ||= T.let(
      GitHub::AzureServiceBus::QueueClient.new(queue_name: GitHub.credit_decision_engine_queue_name, connection_string: GitHub.credit_decision_engine_connection_string),
      T.nilable(GitHub::AzureServiceBus::QueueClient))
  end
end
