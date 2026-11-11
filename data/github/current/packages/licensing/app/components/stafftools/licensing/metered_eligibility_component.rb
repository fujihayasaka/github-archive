# typed: true
# frozen_string_literal: true

module Stafftools
  module Licensing
    class MeteredEligibilityComponent < ApplicationComponent
      sig { params(business: Business, tag: Symbol, omit: T::Array[String]).void }
      def initialize(business, tag: :div, omit: [])
        @business = business
        @tag = tag
        @omit = omit
      end

      def call
        content_tag(tag) do
          safe_join([
            render(Stafftools::StatusListItemComponent.new(
              status: overall_status,
              message: summary_message,
              test_selector: "metered-eligibility-status",
              tag: :div
            )),
            content_tag(:ul, class: "list-style-none tmp-pl-3 mt-2") do
              safe_join(eligibility_checks.map { |check| render_check(check) })
            end
          ])
        end
      end

      private

      attr_reader :business, :tag, :omit

      sig { returns(T::Boolean) }
      def render?
        !GitHub.enterprise? && !business.metered_plan?
      end

      memoize def eligibility_checker
        ::Licensing::MeteredTransitionEligibilityChecker.new(business)
      end

      memoize def eligibility_checks
        eligibility_checker&.all_checks(omit: omit) || []
      end

      memoize def eligible_for_metered?
        eligibility_checker&.eligible?(omit: omit) || false
      end

      def overall_status
        eligible_for_metered? ? :success : :neutral
      end

      def summary_message
        if eligible_for_metered?
          "Eligible for self-serve metered transition"
        else
          failed_count = eligibility_checks.count(&:failed?)
          "Not eligible for self-serve metered transition (#{pluralize(failed_count, 'criterion')} not met)"
        end
      end

      def render_check(check)
        content_tag(:li, class: "mb-1") do
          render Stafftools::StatusListItemComponent.new(
            status: check.passed ? :success : :error,
            message: check.description,
            test_selector: "metered-eligibility-check-#{check.name}",
            tag: :span
          )
        end
      end
    end
  end
end
