# typed: true
# frozen_string_literal: true

module Biztools
  module Coupons
    class CouponsListComponent < ApplicationComponent
      include ActionView::Helpers::NumberHelper

      renders_one :header

      attr_reader :coupons, :empty_message, :pagination_params

      def initialize(coupons:, title: nil, empty_message: "No coupons found.", pagination_params: {})
        @coupons = coupons
        @title = title
        @empty_message = empty_message
        @pagination_params = pagination_params
      end

      def title
        @title
      end

      def paginated?
        coupons.respond_to?(:total_pages) && coupons.total_pages > 1
      end

      private

      def site_admin?
        helpers.site_admin?
      end

      def expiration(coupon)
        if coupon.expired?
          content_tag(:strong, "Expired")
        else
          safe_join(["Expires ", content_tag(:strong, coupon.human_expires_at)])
        end
      end

      def single_use?(coupon)
        (coupon.limit + coupon.redeemed_count) == 1
      end

      def usage(coupon)
        txt = []

        txt << number_with_delimiter(coupon.redeemed_count)
        txt << "used,"
        txt << number_with_delimiter(coupon.limit)
        txt << "left"

        safe_join(txt, " ")
      end

      def human_details(coupon)
        plan = coupon.plan

        txt = ["#{coupon.human_discount}/mo off"]
        txt << "the #{plan} plan" if plan.present?
        txt << "for #{coupon.human_duration}"
        txt.join(" ")
      end
    end
  end
end
