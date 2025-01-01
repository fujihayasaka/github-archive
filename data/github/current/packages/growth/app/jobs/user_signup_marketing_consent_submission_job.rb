# typed: true
# frozen_string_literal: true

class UserSignupMarketingConsentSubmissionJob < ApplicationJob
  retry_on_dirty_exit
  retry_on_recoverable_exceptions attempts: 5
  retry_on Faraday::Error, wait: :polynomially_longer, attempts: 5

  queue_as :user_signup_marketing_consent

  sig { params(email: String, country: String).void }
  def perform(email:, country:)
    MarketingForms::RestApiClient.post_consent(
      email: email,
      country: country,
      consent: MarketingForms::Consent::Explicit,
      source: "new-user-signup"
    )
  end
end
