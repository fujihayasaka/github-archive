# typed: true
# frozen_string_literal: true

module Licensing
  # Evaluates all eligibility criteria for self-serve metered transition.
  # This class provides detailed information about each criterion for stafftools,
  # while also supporting the exit-early behavior for the customer-facing check.
  class MeteredTransitionEligibilityChecker
    sig { returns(Business) }
    attr_reader :business

    sig { returns(T.nilable(User)) }
    attr_reader :user

    sig { params(business: Business, user: T.nilable(User)).void }
    def initialize(business, user: nil)
      @business = business
      @user = user
    end

    # Returns true if the business is eligible for self-serve metered transition.
    # This method exits early on the first failing criterion for performance.
    sig { params(omit: T::Array[String]).returns(T::Boolean) }
    def eligible?(omit: [])
      eligibility_criteria(omit: omit).each do |criterion|
        return false unless criterion[:passed].call
      end
      true
    rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
      false
    end

    # Returns all eligibility checks with their status and description.
    # This is used by stafftools to show detailed information about each criterion.
    sig { params(omit: T::Array[String]).returns(T::Array[MeteredTransitionEligibilityCheck]) }
    def all_checks(omit: [])
      eligibility_criteria(omit: omit).map do |criterion|
        MeteredTransitionEligibilityCheck.new(
          name: criterion[:name],
          description: criterion[:description].call,
          passed: criterion[:passed].call
        )
      end
    rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
      []
    end

    private

    # Single source of truth for all eligibility criteria.
    # Each criterion has a name, a description (can be dynamic), and a passed check.
    # The order matters for exit-early behavior in eligible?.
    sig { params(omit: T::Array[String]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def eligibility_criteria(omit: [])
      utilization = license_utilization_percent
      utilization_display = business.purchased_enterprise_licenses.zero? ? "N/A" : "#{(utilization * 100).round(1)}%"

      [
        {
          name: "not_enterprise_server",
          description: -> { "Not running on Enterprise Server" },
          passed: -> { !GitHub.enterprise? }
        },
        {
          name: "is_owner",
          description: -> { "User is an owner of the business" },
          passed: -> { business.owner?(user) }
        },
        {
          name: "not_trial",
          description: -> { "Not on a trial plan" },
          passed: -> { !business.trial? }
        },
        {
          name: "not_already_metered",
          description: -> { "Not already on metered billing" },
          passed: -> { !business.metered_plan? }
        },
        {
          name: "no_scheduled_transition",
          description: -> { "No metered transition already scheduled" },
          passed: -> { business.future_metered_transition.blank? }
        },
        {
          name: "self_serve_customer",
          description: -> { "Self-serve customer (not invoiced and no sales subscription)" },
          passed: -> { !business.invoiced? && business.sales_serve_plan_subscription.blank? }
        },
        {
          name: "no_active_coupon",
          description: -> { "No active coupon applied" },
          passed: -> { !business.has_an_active_coupon? }
        },
        {
          name: "no_enterprise_agreement",
          description: -> { "No active enterprise agreement" },
          passed: -> { business.enterprise_agreements.active.none? }
        },
        {
          name: "not_standalone",
          description: -> { "Not a standalone/Copilot-only business" },
          passed: -> { !business.seats_plan_basic? }
        },
        {
          name: "no_trade_restriction",
          description: -> { "No commercial interaction restriction" },
          passed: -> { !business.has_commercial_interaction_restriction? }
        },
        {
          name: "license_utilization",
          description: -> { "License utilization >= 70% (current: #{utilization_display})" },
          passed: -> { business.purchased_enterprise_licenses > 0 && utilization >= 0.7 }
        }
      ].reject { |criterion| omit.include?(criterion[:name]) }
    end

    sig { returns(Float) }
    def license_utilization_percent
      return 0.0 if business.purchased_enterprise_licenses.zero?

      business.consumed_enterprise_licenses.to_f / business.purchased_enterprise_licenses
    end
  end
end
