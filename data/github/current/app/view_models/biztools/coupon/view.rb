# typed: true
# frozen_string_literal: true

module Biztools
  module Coupon
    class View
      # Internal: Call various text and application helpers through this
      # object.
      def helpers
        @helpers ||= ViewModel::Helpers.new(self)
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
