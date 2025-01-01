# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class LockStatusComponent < ApplicationComponent
      extend T::Sig

      sig { params(billable_entity: ::Billing::Interfaces::BillableEntity, tag: Symbol).void }
      def initialize(billable_entity:, tag: :li)
        @billable_entity = billable_entity
        @tag = tag
      end

      def call
        render Stafftools::StatusListItemComponent.new(status: status, message: message, test_selector: "lock-status", tag: tag)
      end

      private

      attr_reader :billable_entity, :tag

      def status
        return :success if unlocked?
        return :neutral if no_private_repo_support? || over_plan_limit?
        :error
      end

      memoize def unlocked?
        !billable_entity.disabled?
      end

      memoize def no_private_repo_support?
        !billable_entity.plan_supports?(:repos, visibility: :private)
      end

      memoize def over_plan_limit?
        billable_entity.over_plan_limit?
      end

      memoize def rbi_customer_past_dunning_period?
        billable_entity.autopay_disabled_by_india_rbi? &&
        billable_entity.disabled?
      end

      memoize def locked_reasons
        billable_entity.disabled_reasons.to_a.join(", ")
      end

      def message
        suffix = if unlocked?
          "Unlocked"
        elsif no_private_repo_support?
          "Locked - Plan doesn't support private repos"
        elsif over_plan_limit?
          "Locked - Over allotment of private repos"
        elsif rbi_customer_past_dunning_period?
          "Locked - RBI & past dunning period"
        elsif locked_reasons.present?
          "Locked - #{locked_reasons}"
        elsif billable_entity.has_billing_record?
          "Locked - Payment attempt declined"
        else
          "Locked - Coupon expired or staff locked"
        end
        "Lock status: #{suffix}"
      end
    end
  end
end
