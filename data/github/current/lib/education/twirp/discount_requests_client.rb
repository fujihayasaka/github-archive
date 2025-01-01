# typed: true
# frozen_string_literal: true

module Education
  module Twirp
    class DiscountRequestsClient < Education::Twirp::BaseClient
      def create_discount_request(discount_request:)
        rpc(
          :CreateDiscountRequest,
          discount_request:
        )
      end

      private

      def twirp_class
        EducationWeb::V1::DiscountRequestsClient
      end
    end
  end
end
