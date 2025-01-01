# typed: true
# frozen_string_literal: true

class UserSignup < ApplicationRecord::Domain::Users
  include GitHub::Validations
  include ::Instrumentation::Model

  self.table_name = "user_signups"

  belongs_to :user, strict_loading: false

  validates :user, presence: true
  validates :email, presence: true, length: { maximum: 255 }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :country_code, presence: true, length: { is: 2 }, format: { with: /\A[A-Z]{2}\z/ }
  validate :country_in_marketing_targeted_countries
  enum :marketing_consent, { not_specified: 0, explicit_optin: 1, implicit_optin: 2 }, validate: { allow_nil: true }, prefix: true
  validates :onboarding_optout_date, datetime_in_supported_range: true, allow_nil: true

  sig { params(user: User, email: String, country_code: String, gave_explicit_marketing_consent: T.nilable(T::Boolean)).returns(UserSignup) }
  def self.capture_user_signup_data(user:, email:, country_code:, gave_explicit_marketing_consent:)
    user_signup = UserSignup.create do |u|
      u.user = user
      u.email = email
      u.country_code = country_code
      u.marketing_consent = map_marketing_consent(gave_explicit_marketing_consent)
    end

    if user_signup.persisted?
      user_signup.enqueue_marketing_consent_submission_job
    end

    user_signup
  end

  sig { params(gave_explicit_marketing_consent: T.nilable(T::Boolean)).returns(Symbol) }
  def self.map_marketing_consent(gave_explicit_marketing_consent)
    # if the user has checked the marketing consent checkbox, they have explicitly opted in
    # if the user has not checked the marketing consent checkbox, they have not specified
    return :explicit_optin if gave_explicit_marketing_consent

    :not_specified
  end

  sig { void }
  def enqueue_marketing_consent_submission_job
    return unless marketing_consent_explicit_optin?

    UserSignupMarketingConsentSubmissionJob.perform_later(
      email: email,
      country: country_code
    )
  end

  private

  sig { void }
  def country_in_marketing_targeted_countries
    if !TradeControls::Countries.marketing_targeted_country?(country_code)
      errors.add(:country_code, "is not in the list of marketing targeted countries")
    end
  end
end
