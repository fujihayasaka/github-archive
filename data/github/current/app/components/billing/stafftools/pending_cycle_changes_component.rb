# typed: true
# frozen_string_literal: true

module Billing
  module Stafftools
    class PendingCycleChangesComponent < ApplicationComponent

      sig { returns(T.any(Business, User)) }
      attr_reader :account

      sig { params(account: T.any(Business, User)).void }
      def initialize(account:)
        @account = account
      end

      sig { returns(Billing::PendingCycle) }
      def pending_cycle
        account.pending_cycle
      end

      sig { params(change: Billing::PendingPlanChange).returns(String) }
      def cancel_pending_changes_path(change)
        if FeatureFlag.vexi.enabled?(:billing_cancel_pending_plan_changes_via_stafftools, default: false)
          helpers.stafftools_billing_pending_plan_change_path(change)
        else
          if account.business?
            helpers.business_update_pending_plan_change_path(T.cast(account, Business).slug)
          else
            helpers.update_pending_plan_change_path(T.cast(account, User).display_login)
          end
        end
      end

      sig { returns(String) }
      def run_pending_changes_path
        if account.business?
          helpers.run_pending_changes_stafftools_enterprise_path(T.cast(account, Business))
        else
          helpers.run_pending_changes_stafftools_user_path(T.cast(account, User))
        end
      end

      sig { returns(T::Boolean) }
      def render?
        account.incomplete_pending_plan_changes.present?
      end

      def changes(pending_plan_change)
        changes = []

        changes << "plan" if pending_plan_change.changing_plan?
        changes << "seats" if pending_plan_change.changing_seats?
        changes << "duration" if pending_plan_change.changing_duration?
        changes << "data packs" if pending_plan_change.changing_data_packs?
        changes << pluralize(pending_plan_change.pending_subscription_item_changes.length, "subscription") if pending_plan_change.has_item_changes?

        changes
      end
    end
  end
end
