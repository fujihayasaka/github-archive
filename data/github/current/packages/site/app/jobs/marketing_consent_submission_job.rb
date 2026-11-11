# typed: true
# frozen_string_literal: true

class MarketingConsentSubmissionJob < ApplicationJob
  retry_on_dirty_exit
  retry_on_recoverable_exceptions attempts: 10
  retry_on Faraday::Error, wait: :polynomially_longer, attempts: 10

  queue_as :marketing_consent_submission

  sig { params(email: String, country: String, source: String).void }
  def perform(email:, country:, source:)
    MarketingForms::RestApiClient.post_consent(
      email: email,
      country: country,
      consent: MarketingForms::Consent::Explicit,
      source: source
    )
  end

  sig { returns(T::Array[String]) }
  def stats_tags
    ["source:#{source}"]
  end

  private

  sig { returns(String) }
  def source
    arguments.first&.fetch(:source)
  end
end
