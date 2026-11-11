# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class PlanHistoryComponent < ApplicationComponent

      class ActionType < T::Enum
        enums do
          SwitchedTo = new("switched_to")
          Seats = new("seats")
          AssetPacks = new("asset_packs")
          FirstTimePaidUpgrade = new("first_time_paid_upgrade")
          RecurringCharge = new("recurring_charge")
          ProrateCharge = new("prorate_charge")
          Refunded = new("refunded")
          PlanChange = new("plan_change")
          Other = new("other")
        end
      end

      sig { params(billing_transaction: ::Billing::BillingTransaction).void }
      def initialize(billing_transaction)
        @bt = billing_transaction
      end

      sig { returns(String) }
      def action
        case @bt.transaction_type
        when "prorate-seat-charge"
          current_seats_count = current_seats
          old_seats_count = old_seats
          if !current_seats_count.nil? && !old_seats_count.nil?
            current_seats_count > old_seats_count ? "added_seats" : "removed_seats"
          else
            "seat_change"
          end
        when "prorate-asset-pack-charge"
          current_packs = asset_packs_total
          old_packs = old_data_packs
          if !current_packs.nil? && !old_packs.nil?
            current_packs > old_packs ? "added_asset_packs" : "removed_asset_packs"
          else
            "asset_pack_change"
          end
        when "plan-change"
          "changed"
        when "signed-up"
          "enabled"
        when "refund"
          "refunded"
        when "prorate-charge"
          "prorate_charge"
        when "recurring-charge"
          "recurring_charge"
        when "first-time-paid-upgrade"
          "first_time_paid_upgrade"
        else
          @bt.transaction_type.to_s
        end
      end

      sig { returns(String) }
      def humanized_action
        action.humanize
      end

      sig { returns(ActionType) }
      def action_type
        if action.start_with?("switched-to-")
          ActionType::SwitchedTo
        elsif action.include?("_seats")
          ActionType::Seats
        elsif action.include?("_asset_packs")
          ActionType::AssetPacks
        elsif action == "first_time_paid_upgrade"
          ActionType::FirstTimePaidUpgrade
        elsif action == "recurring_charge"
          ActionType::RecurringCharge
        elsif action == "prorate_charge"
          ActionType::ProrateCharge
        elsif action == "refunded"
          ActionType::Refunded
        elsif current_plan
          ActionType::PlanChange
        else
          ActionType::Other
        end
      end

      sig { returns(String) }
      def charge_details
        plan = current_plan_name ? current_plan_name.to_s.humanize : ""
        old_plan = old_plan_name ? old_plan_name.to_s.humanize : ""
        seats = current_seats

        case action_type
        when ActionType::RecurringCharge
          if old_plan.present? && old_plan != plan
            "Subscription charge for #{pluralize(seats, 'seat')} on #{plan} (previously #{old_plan})"
          else
            "Subscription charge for #{pluralize(seats, 'seat')} on #{plan}"
          end
        when ActionType::ProrateCharge
          if old_plan.present? && old_plan != plan
            "Prorated charge for #{pluralize(seats, 'seat')} on #{plan} (previously #{old_plan})"
          else
            "Prorated charge for #{pluralize(seats, 'seat')} on #{plan}"
          end
        when ActionType::Refunded
          if old_plan.present? && old_plan != plan
            "Refund for #{pluralize(seats, 'seat')} on #{plan} (previously #{old_plan})"
          else
            "Refund for #{pluralize(seats, 'seat')} on #{plan}"
          end
        when ActionType::FirstTimePaidUpgrade
          if old_plan.present? && old_plan != plan
            "First-time paid upgrade for #{pluralize(seats, 'seat')} on #{plan} (previously #{old_plan})"
          else
            "First-time paid upgrade for #{pluralize(seats, 'seat')} on #{plan}"
          end
        else
          ""
        end
      end

      sig { returns(String) }
      def period_change_direction
        match = action.match(/\Aswitched-to-(.+)\z/)
        period = match && match[1]
        if period == "monthly"
          "yearly → monthly"
        elsif period == "yearly"
          "monthly → yearly"
        else
          ""
        end
      end

      sig { returns(T.nilable(Integer)) }
      def current_seats
        @bt.seats_total
      end

      sig { returns(T.nilable(Integer)) }
      def old_seats
        cs = current_seats
        sd = seats_delta
        return nil if cs.nil? || sd.nil?
        cs - sd
      end

      sig { returns(T.nilable(Integer)) }
      def seats_delta
        @bt.seats_delta
      end

      sig { returns(T.nilable(String)) }
      def current_plan_name
        @bt.plan_name
      end

      sig { returns(T.nilable(String)) }
      def old_plan_name
        @bt.old_plan_name
      end

      sig { returns(T.nilable(Integer)) }
      def asset_packs_total
        @bt.asset_packs_total
      end

      sig { returns(T.nilable(Integer)) }
      def asset_packs_delta
        @bt.asset_packs_delta
      end

      sig { returns(T.nilable(Integer)) }
      def old_data_packs
        total = asset_packs_total
        delta = asset_packs_delta
        return nil if total.nil? || delta.nil?
        total - delta
      end

      sig { returns(T.nilable(GitHub::Plan)) }
      def current_plan
        plan_name = @bt.plan_name
        return nil unless plan_name
        GitHub::Plan.find(plan_name)
      end

      sig { returns(T.nilable(GitHub::Plan)) }
      def old_plan
        old_plan_name = @bt.old_plan_name
        return nil unless old_plan_name
        GitHub::Plan.find(old_plan_name)
      end

      sig { returns(String) }
      def formatted_date
        @bt.created_at.strftime("on %b %-d, %Y")
      end
    end
  end
end
