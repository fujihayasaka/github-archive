# typed: strict
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class MembershipStatusComponent < ApplicationComponent
      extend T::Sig

      class MembershipStatus
        extend T::Sig

        sig { returns Symbol }
        attr_reader :icon_color, :octicon

        sig { returns String }
        attr_reader :text_class, :label

        sig do
          params(icon_color: Symbol, text_class: String, octicon: Symbol, label: String).void
        end
        def initialize(icon_color:, text_class:, octicon:, label:)
          @icon_color = icon_color
          @text_class = text_class
          @octicon = octicon
          @label = label
        end
      end

      sig { params(sponsors_listing: T.nilable(SponsorsListing)).void }
      def initialize(sponsors_listing:)
        @sponsors_listing = sponsors_listing
      end

      private

      sig { returns SponsorsListing }
      def sponsors_listing
        T.must_because(@sponsors_listing) { "#render? ensures non-nil" }
      end

      sig { returns T::Boolean }
      def render?
        @sponsors_listing.present?
      end

      sig { returns MembershipStatus }
      memoize def listing_status
        if sponsors_listing.approved?
          MembershipStatus.new(
            icon_color: :success,
            text_class: "color-fg-success",
            octicon: :check,
            label: "Public"
          )
        elsif sponsors_listing.pending_approval? || sponsors_listing.requires_additional_review?
          MembershipStatus.new(
            icon_color: :attention,
            text_class: "color-fg-attention",
            octicon: :hourglass,
            label: "Needs approval"
          )
        elsif sponsors_listing.draft?
          MembershipStatus.new(
            icon_color: :attention,
            text_class: "color-fg-attention",
            octicon: :pencil,
            label: "Draft"
          )
        elsif sponsors_listing.disabled?
          MembershipStatus.new(
            icon_color: :danger,
            text_class: "color-fg-danger",
            octicon: :lock,
            label: "Disabled"
          )
        elsif sponsors_listing.queued_for_auto_approval?
          MembershipStatus.new(
            icon_color: :attention,
            text_class: "color-fg-attention",
            octicon: :eye,
            label: "Queued for auto-approval"
          )
        else
          MembershipStatus.new(
            icon_color: :danger,
            text_class: "color-fg-danger",
            octicon: :question,
            label: "Unknown"
          )
        end
      end

      sig { returns T.nilable(::Billing::StripeConnect::Account) }
      memoize def stripe_connect_account
        sponsors_listing.active_stripe_connect_account
      end

      sig { returns T::Boolean }
      memoize def matching_enabled?
        !sponsors_listing.match_disabled?
      end

      sig { returns MembershipStatus }
      memoize def matching_status
        if sponsors_listing.match_disabled?
          MembershipStatus.new(
            icon_color: :attention,
            text_class: "color-fg-attention",
            octicon: :lock,
            label: "Disabled"
          )
        elsif sponsors_listing.reached_match_limit?
          MembershipStatus.new(
            icon_color: :success,
            text_class: "color-fg-success",
            octicon: :star,
            label: "Reached"
          )
        elsif sponsors_listing.matchable?
          MembershipStatus.new(
            icon_color: :success,
            text_class: "color-fg-success",
            octicon: :check,
            label: "On"
          )
        else
          MembershipStatus.new(
            icon_color: :danger,
            text_class: "color-fg-danger",
            octicon: :x,
            label: "Not matchable"
          )
        end
      end
    end
  end
end
