# typed: true
# frozen_string_literal: true

module Education
  module Twirp
    class DiscountRequestsClient < Education::Twirp::BaseClient
      def create_discount_request(discount_request:, ip_address:)
        rpc(:CreateDiscountRequest, discount_request:, ip_address:)
      end

      def is_eligible_for_reverification(github_user_id:)
        rpc(:IsEligibleForReverification, github_user_id:)
      end

      def is_blocked(github_user_id:)
        rpc(:IsBlocked, github_user_id:)
      end

      private

      def twirp_class
        EducationWeb::V1::DiscountRequestsClient
      end
    end
  end
end
