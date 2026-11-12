# frozen_string_literal: true

module DebugService
  module V1
    class Handler
      def get_encrypted_config_payload(req, _env)
        public_key = req.public_key
        return Twirp::Error.invalid_argument("Public key not provided") if public_key.blank?

        update_config = UpdateConfig.find_by(id: req.update_config_id)
        return Twirp::Error.not_found("UpdateConfig ID not found.") unless update_config

        payload = EncryptRegistryCredentialsForDebugging.new(update_config, public_key).run

        {
          encrypted_config_payload: payload.encrypted_credential_blob,
        }
      end
    end
  end
end
