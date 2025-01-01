# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

module TradeControls
  class UserHighRiskGeoJob < ApplicationJob

    queue_as :trade_screening

    RETRYABLE_ERRORS = T.let([
      ActiveRecord::RecordNotFound,
      ActiveRecord::RecordNotUnique,
      *Resiliency::Response::UnavailableExceptions, # Recoverable exceptions
    ].freeze, T::Array[T.class_of(StandardError)])

    retry_on_dirty_exit

    RETRYABLE_ERRORS.each do |error|
      retry_on error, wait: :polynomially_longer, attempts: 2 do |_job, error|
        Failbot.report(error)
      end
    end

    before_enqueue do |_job|
      throw(:abort) unless GitHub.billing_enabled?
    end

    sig { params(user: ::User, location: T.nilable(T::Hash[Symbol, String]), email: T.nilable(String)).void }
    def perform(user, location: nil, email: nil)
      return if user.trade_controls_restriction.trade_restricted_country_code.present?

      return if location.nil? && email.nil?

      high_risk_geo = UserHighRiskGeoManager.new(location: location, email: email).high_risk_geo

      if high_risk_geo.present?
        with_write { user.trade_controls_restriction.update(trade_restricted_country_code: high_risk_geo) }
      end
    end
  end
end
