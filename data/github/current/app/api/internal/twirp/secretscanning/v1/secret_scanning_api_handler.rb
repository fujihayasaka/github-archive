# typed: true
# frozen_string_literal: true

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class SecretScanningAPIHandler < Api::Internal::Twirp::Handler
        # Internal: See Api::Internal::Twirp::Handler#allow_client?
        def allow_client?(client_name, env)
          client_name == "token_scanning_service"
        end
      end
    end
  end
end
