# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class SponsorshipItemComponent < ApplicationComponent
      # sponsor - a User or Organization
      # sponsorship_item - a Billing::SubscriptionItem or Sponsorship
      sig do
        params(
          sponsor: T.nilable(::User),
          sponsorship_item: T.nilable(T.any(::Billing::SubscriptionItem, Sponsorship)),
        ).void
      end
      def initialize(sponsor:, sponsorship_item:)
        @sponsor = sponsor
        @item = sponsorship_item
      end

      private

      sig { returns(T::Boolean) }
      def render?
        GitHub.sponsors_enabled? && @sponsor.present? && @item.present?
      end

      sig { returns(::User) }
      def sponsor
        T.must(@sponsor)
      end

      sig { returns T.any(::Billing::SubscriptionItem, Sponsorship) }
      def item
        T.must(@item)
      end

      sig { returns GitHubSponsors::Types::Sponsorable }
      memoize def sponsorable
        sponsorship&.sponsorable || sub_item&.sponsorable || ::User.ghost
      end

      sig { returns(String) }
      def row_classes
        class_names(
          "color-fg-muted",
          "color-bg-closed" => pending_change.present?
        )
      end

      sig { returns T.nilable(::SponsorsTier) }
      memoize def tier
        if sponsorship?
          sponsorship&.tier
        else
          sub_item&.subscribable
        end
      end

      sig { returns(String) }
      def tier_price
        money = if tier
          price = T.must(tier).price_in_cents_per_cycle(plan_duration: sponsor.plan_duration)
          ::Billing::Money.new(price)
        else
          ::Billing::Money.zero
        end
        suffix = sponsorship&.payment_source == "patreon" ? "(Patreon)" : ""
        [money.format, suffix].join(" ")
      end

      sig { returns T.nilable(::Billing::SubscriptionItem) }
      memoize def sub_item
        if sponsorship?
          T.cast(item, Sponsorship).subscription_item
        else
          T.cast(item, ::Billing::SubscriptionItem)
        end
      end

      sig { returns(T.nilable(Sponsorship)) }
      memoize def sponsorship
        if sponsorship?
          T.cast(item, Sponsorship)
        else
          T.cast(item, ::Billing::SubscriptionItem).sponsorship
        end
      end

      sig { params(sponsorship: Sponsorship).returns(String) }
      def formatted_one_time_expiration_date_for(sponsorship)
        time = if sponsorship.expired?
          Sponsorship.expiration_time
        else
          sponsorship.expires_at
        end
        return "not set" unless time
        time.to_date.to_formatted_s(:long_ordinal)
      end

      sig { returns(T.nilable(String)) }
      def opposite_privacy_level
        sponsorship&.opposite_privacy_level
      end

      sig { returns(T.nilable(Sponsorship::PendingChange)) }
      memoize def pending_change
        sponsorship&.pending_change
      end

      sig { returns T.nilable(Integer) }
      memoize def sponsorship_id
        sponsorship? ? T.must(sponsorship).id : sub_item&.sponsorship_id
      end

      sig { returns T.nilable(String) }
      memoize def cancellation_path
        if sponsorship_id
          stafftools_sponsors_sponsorship_path(sponsorship_id)
        elsif sub_item
          stafftools_user_subscription_item_path(T.must(sub_item).managing_entity, T.must(sub_item).id)
        end
      end

      sig { returns T::Boolean }
      def show_cancellation_form?
        return false unless item.active? && cancellation_path.present?
        return false if pending_change&.activation?
        true
      end

      sig { returns(T::Boolean) }
      def sponsorship?
        item.is_a?(Sponsorship)
      end
    end
  end
end
