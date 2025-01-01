# typed: true
# frozen_string_literal: true

module Biztools
  module Coupon
    class IndexView < View
      include ActionView::Helpers::NumberHelper
      include ActionView::Helpers::TagHelper
      include ActionView::Helpers::UrlHelper
      include EscapeHelper

      def expiration(coupon)
        if coupon.expired?
          content_tag(:strong, "Expired") # rubocop:disable Rails/ViewModelHTML
        else
          safe_join(["Expires ", content_tag(:strong, coupon.human_expires_at)]) # rubocop:disable Rails/ViewModelHTML
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

      def group_count(group)
        ::Coupon.where(group: group).count
      end

    end
  end
end
