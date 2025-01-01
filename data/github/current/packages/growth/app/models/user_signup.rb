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

  def country_in_marketing_targeted_countries
    if !TradeControls::Countries.marketing_targeted_country?(country_code)
      errors.add(:country_code, "is not in the list of marketing targeted countries")
    end
  end
end
