# typed: true
# frozen_string_literal: true

class LeadIngestionSubmissionJob < ApplicationJob
  class LeadIngestionError < StandardError; end

  retry_on_dirty_exit
  retry_on LeadIngestionError, wait: :polynomially_longer, attempts: 5

  queue_as :lead_ingestion_submissions

  sig { params(lead_payload: T::Hash[Symbol, String]).void }
  def perform(lead_payload)
    @response = LeadIngestion::RestApiClient.put_lead(lead_payload)
    raise LeadIngestionError, @response.error.message if @response.error?
  end

  def logging_context
    super.tap do |ctx|
      if @response.present?
        ctx.merge!({
          "gh.request_id" => @response.payload[:batchRequestId],
          "gh.lead_ingestion.lead_id" => @response.payload.dig(:input, 0, :requestItemId),
        })
      end
    end
  end
end
