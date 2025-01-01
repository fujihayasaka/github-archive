# typed: true
# frozen_string_literal: true

module Education
  module Twirp
    class HealthClient < Education::Twirp::BaseClient
      def ping
        rpc(:Ping, {})
      end

      private

      def twirp_class
        EducationWeb::V1::HealthClient
      end
    end
  end
end
