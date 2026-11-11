# typed: true
# frozen_string_literal: true

module Launch
  module Twirp
    class EnvironmentClient < Launch::Twirp::BaseClient
      sig do
        params(
          launch_deployer_twirp_address: T.nilable(String),
          launch_deployer_hmac_secret: T.nilable(String),
        ).void
      end
      def initialize(
        launch_deployer_twirp_address: GitHub.launch_deployer_twirp_address,
        launch_deployer_hmac_secret: GitHub.launch_deployer_hmac_secret
      )
        super(
          launch_deployer_twirp_address: launch_deployer_twirp_address,
          launch_deployer_hmac_secret: launch_deployer_hmac_secret,
          client_name: "#{Launch::Twirp::BaseClient::SERVICE_NAME}-environment",
          retry_options: {
            max: 2, # 3 attempts total
            retry_statuses: [500, 503],
            methods: [:post], # All Twirp requests are POSTs
            interval: 0.05, # 50 milliseconds
            interval_randomness: 0.5,
            backoff_factor: 2,
            retry_block: proc { |_env, _options, retries, exception|
              GitHub::Logger.log(msg: "Request failed with a retriable error and will be retried", attempt: retries, max_attempt: 3, error: exception.class)
            }
          }
        )
      end

      def notify_gate(request)
        rpc(
          :NotifyGate,
          request
        )
      end

      private

      def twirp_class
        GitHub::Launch::Services::Environment::EnvironmentClient
      end
    end
  end
end
