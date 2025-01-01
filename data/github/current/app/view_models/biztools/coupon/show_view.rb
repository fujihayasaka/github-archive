# typed: strict
# frozen_string_literal: true

module Biztools
  module Coupon
    class ShowView < View
      include UrlHelpers

      sig { returns(String) }
      attr_reader :state

      delegate :redeemed_count, to: :coupon

      sig { params(coupon: ::Coupon, state: String).void }
      def initialize(coupon, state: "active")
        @coupon = coupon
        @state = state
      end

      sig { returns(T::Boolean) }
      def active_state?
        state == "active"
      end

      sig { returns(T::Boolean) }
      def expired_state?
        state == "expired"
      end

      sig { returns(String) }
      def human_details
        super coupon
      end

      sig { params(user: T.any(User, Organization, Business)).void }
      def expires(user)
        user.coupon_redemption.expires_at.to_date
      end

      sig { returns(String) }
      def coupon_note
        helpers.auto_link(
          coupon.note,
          mode = :urls,
          link_attr = nil,
          skip_tags = nil,
        )
      end

      sig { params(billable_entity: T.any(User, Organization, Business)).returns(String) }
      def revoke_coupon_path(billable_entity)
        if billable_entity.business?
          biztools_business_revoke_coupon_path(billable_entity)
        else
          biztools_user_coupon_path(billable_entity)
        end
      end

      sig { params(billable_entity: T.any(User, Organization, Business)).returns(String) }
      def stafftools_entity_path(billable_entity)
        if billable_entity.business?
          stafftools_enterprise_path(billable_entity)
        else
          stafftools_user_path(billable_entity)
        end
      end

      private

      sig { returns(::Coupon) }
      attr_reader :coupon
    end
  end
end
