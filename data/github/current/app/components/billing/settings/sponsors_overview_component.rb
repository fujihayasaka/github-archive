# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    class SponsorsOverviewComponent < ApplicationComponent
      extend T::Sig
      include ::TextHelper
      include ::AvatarHelper
      include BillingSettingsHelper

      class HistoryTab < T::Enum
        enums do
          Current = new
          Past = new
        end
      end

      sig { params(user_or_org: User, active_tab: HistoryTab).void }
      def initialize(user_or_org:, active_tab:)
        @user_or_org = user_or_org
        @active_tab = active_tab
      end

      private

      sig { returns(User) }
      attr_reader :user_or_org

      sig { returns(HistoryTab) }
      attr_reader :active_tab

      sig { returns(T::Boolean) }
      def render?
        return false unless GitHub.sponsors_enabled?
        return false if user_or_org.invoiced? && !user_or_org.sponsors_invoiced?
        true
      end

      sig { returns(T::Boolean) }
      def show_start_sponsoring_button?
        return false if current_subscription_items.present?
        return false unless allowed_to_sponsor?
        true
      end

      sig { returns(T::Boolean) }
      memoize def include_credit_balance?
        return false if past_tab_active?
        user_or_org.sponsors_invoiced?
      end

      sig { returns(T::Boolean) }
      def past_tab_active?
        active_tab == HistoryTab::Past
      end

      sig { params(selected_tab: HistoryTab).returns(String) }
      def billing_path(selected_tab:)
        if user_or_org.organization?
          settings_org_billing_path(user_or_org, sponsorships_tab: selected_tab.serialize)
        else
          settings_user_billing_path(sponsorships_tab: selected_tab.serialize)
        end
      end

      sig { returns(T::Array[Billing::SubscriptionItem]) }
      memoize def all_current_subscription_items
        all_sponsorship_subscription_items.select do |sub_item|
          sub_item.active? || sub_item.pending_sponsorship_activation?
        end
      end

      sig { returns(T::Set[Integer]) }
      memoize def all_current_sponsorable_ids
        Set.new(all_current_subscription_items.map(&:sponsorable_id))
      end

      sig { returns(T::Array[Billing::SubscriptionItem]) }
      memoize def current_subscription_items
        sub_items = all_current_subscription_items.take(30)
        sub_items.reject!(&:sdn_disabled?)
        sub_items
      end

      sig { returns(T::Boolean) }
      def show_tabs?
        past_tab_active? || any_past_subscription_items?
      end

      sig { returns(T::Boolean) }
      def any_past_subscription_items?
        all_sponsorship_subscription_items.any? { |item| !item.active? }
      end

      sig { returns(T::Array[Billing::SubscriptionItem]) }
      memoize def past_subscription_items
        sub_items = all_sponsorship_subscription_items.reject do |sub_item|
          sub_item.active? || sub_item.pending_sponsorship_activation?
        end
        sub_items = sub_items.take(30).uniq(&:sponsorable_id).select do |item|
          sponsorable_id = item.sponsorable_id
          sponsorable_id.present? && !all_current_sponsorable_ids.include?(sponsorable_id)
        end
        sub_items
      end

      sig { params(items: T::Array[Billing::SubscriptionItem]).void }
      def prefill_sponsors_listings(items)
        tiers = items.map(&:subscribable)
        GitHub::PrefillAssociations.prefill_associations(tiers, :sponsors_listing)
      end

      sig { params(items: T::Array[Billing::SubscriptionItem]).void }
      def preload_adminable_by(items)
        GitHub::PrefillAssociations.prefill_batch_method(items, :async_adminable_by?, user_or_org)
      end

      sig { params(items: T::Array[Billing::SubscriptionItem]).void }
      def preload_sponsorable(items)
        GitHub::PrefillAssociations.prefill_batch_method(items, :async_sponsorable)
      end

      sig { params(items: T::Array[Billing::SubscriptionItem]).void }
      def preload_pending_subscription_item_changes(items)
        GitHub::PrefillAssociations.prefill_batch_method(items, :pending_subscription_item_change)
      end

      sig { params(items: T::Array[Billing::SubscriptionItem]).void }
      def preload_sponsorships(items)
        GitHub::PrefillAssociations.prefill_associations(items, { sponsorship: [:sponsor, :sponsorable] })
      end

      sig { returns(Billing::Money) }
      def total_sponsors_subscriptions_cost
        sub_items = all_sponsorship_subscription_items
        sub_items.reject!(&:sdn_disabled?)
        cents = Billing::SubscriptionItem.total_monthly_price_in_cents(sub_items, include_fees: true)
        Billing::Money.new(cents)
      end

      sig { returns(Billing::Money) }
      def total_sponsors_subscriptions_cost_excluding_fees
        sub_items = all_sponsorship_subscription_items
        sub_items.reject!(&:sdn_disabled?)
        cents = Billing::SubscriptionItem.total_monthly_price_in_cents(sub_items, include_fees: false)
        Billing::Money.new(cents)
      end

      sig { returns(Billing::Money) }
      memoize def total_sponsors_fees
        total_sponsors_subscriptions_cost - total_sponsors_subscriptions_cost_excluding_fees
      end

      sig { returns(T::Array[Billing::SubscriptionItem]) }
      memoize def all_sponsorship_subscription_items
        sub_items = T.unsafe(user_or_org.sponsors_and_general_plan_subscription_items).latest_first.limit(1000)
          .includes(:subscribable).to_a
        prefill_sponsors_listings(sub_items)
        preload_sponsorable(sub_items)
        preload_adminable_by(sub_items)
        preload_pending_subscription_item_changes(sub_items)
        preload_sponsorships(sub_items)
        sub_items
      end

      sig { params(money: Billing::Money).returns(String) }
      def format_money(money)
        money.format(no_cents_if_whole: false)
      end

      sig { returns(Integer) }
      memoize def subscription_items_count
        current_subscription_items.count
      end

      sig { returns(T::Boolean) }
      memoize def allowed_to_sponsor?
        !user_or_org.has_strict_commercial_interaction_restriction?
      end
    end
  end
end
