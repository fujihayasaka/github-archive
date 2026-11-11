# typed: strict
# frozen_string_literal: true

module Signups
  module MarketingConsentDependency
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { ApplicationController }

    included do
      T.bind(self, T.class_of(ApplicationController))
    end

    EXCLUDED_MARKETING_COUNTRY_CODES = T.let(Set.new([
      "CA", # Canada
      "CN", # China
      "EH", # Western Sahara
      "KR", # South Korea
      "RU", # Russia
    ]).freeze, T::Set[T.untyped])

    sig { returns(T.nilable(ActionController::Parameters)) }
    def user_signup_params
      return unless params[:user_signup].present?

      params[:user_signup].permit(:country, :marketing_consent)
    end

    # Returns the user's marketing consent preference.
    # Context: https://github.com/github/new-user-experience/issues/377
    sig { returns(T.nilable(T::Boolean)) }
    def marketing_consent_granted?
      return unless user_signup_params
      return false if EXCLUDED_MARKETING_COUNTRY_CODES.include?(country)

      T.must(user_signup_params)[:marketing_consent] == "1"
    end

    # Returns the country code if the provided country parameter is recognized.
    sig { returns(T.nilable(String)) }
    def country
      return unless user_signup_params
      return if T.must(user_signup_params)[:country].blank?

      # Only take the first two characters of the string and capitalize for normalization.
      country_code = T.must(user_signup_params)[:country][0, 2].upcase

      ::TradeControls::Countries.currently_unsanctioned_country?(country_code) ? country_code : nil
    end

    # Determines the actor's country code based on their IP address.
    # Used to prefill to a valid country selection in the signup process.
    sig { returns(T.nilable(String)) }
    def actor_country_code
      # In development environment, default to "US" for testing purposes.
      return "US" if Rails.env.development?

      # If the remote IP is not present, return since we're unable to determine location.
      return unless remote_ip.present?

      # Look up the country code based on the user's IP address.
      country_code = GitHub::Location.look_up(remote_ip).dig(:country_code)

      ::TradeControls::Countries.currently_unsanctioned_country?(country_code) ? country_code : nil
    end
  end
end
