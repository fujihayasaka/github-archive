# typed: true
# frozen_string_literal: true

module DependencyGraphPlatform
  module Twirp
    class HealthClient < DependencyGraphPlatform::Twirp::BaseClient
      def ping
        rpc(:Ping, {})
      end

      private

      def client_name
        "health"
      end

      def twirp_class
        Github::DependencyGraphPlatform::Health::V1::HealthServiceClient
      end
    end
  end
end
