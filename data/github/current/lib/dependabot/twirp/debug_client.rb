# typed: true
# frozen_string_literal: true

module Dependabot
  module Twirp
    class DebugClient < Dependabot::Twirp::BaseClient
      def get_encrypted_config_payload(update_config_id:, public_key:)
        rpc(:GetEncryptedConfigPayload, update_config_id: update_config_id, public_key: public_key)
      end

      private

      def twirp_class
        DependabotApi::V1::DebugServiceClient
      end
    end
  end
end
