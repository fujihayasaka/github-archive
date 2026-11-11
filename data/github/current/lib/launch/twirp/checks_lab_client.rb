# typed: strict
# frozen_string_literal: true

module Launch
  module Twirp
    class ChecksLabClient < ChecksClient

      sig { void }
      def initialize
        super(
          launch_deployer_twirp_address: GitHub.launch_lab_deployer_twirp_address,
          launch_deployer_hmac_secret: GitHub.launch_lab_deployer_hmac_secret,
        )
      end
    end
  end
end
