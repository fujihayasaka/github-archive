# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class SponsorshipItemComponent < ApplicationComponent
      include BillingSettingsHelper
      include ::AvatarHelper

      # item - a Billing::SubscriptionItem with subscribable_type=SponsorsTier
      # user_or_org - the User or Organization associated with the subscription item
      # allowed_to_responsor - Boolean indicating whether the given `user_or_org` can restart the sponsorship if it has been cancelled
      def initialize(item:, user_or_org:, allowed_to_responsor: true)
        @item = item
        @user_or_org = user_or_org
        @allowed_to_responsor = allowed_to_responsor
      end

      private

      attr_reader :item, :user_or_org

      delegate :sponsorship, to: :item

      def render?
        GitHub.sponsors_enabled? && item&.subscribable_SponsorsTier? && user_or_org
      end

      sig { returns T.any(::User, ::Organization) }
      memoize def sponsorable
        item.sponsorable || User.ghost
      end

      memoize def pending_change
        item.pending_subscription_item_change
      end

      def show_admin_controls?
        !sponsorable.ghost? && item.active? && !pending_change&.cancellation?
      end

      def show_pending_change_controls?
        item.has_pending_cycle_change? && pending_change.present?
      end

      memoize def user_or_orgs_pending_cycle
        pending_cycle(user_or_org)
      end

      def cancel_msg
        return unless item.account_has_been_charged?

        effective_date = user_or_org.next_sponsors_billing_date.to_formatted_s(:date)

        "Are you sure you want to cancel this sponsorship? The cancellation will be effective on #{effective_date}."
      end

      def allowed_to_responsor?
        @allowed_to_responsor && !pending_change.present? && !sponsorable.ghost?
      end
    end
  end
end
