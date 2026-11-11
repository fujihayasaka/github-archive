# typed: true
# frozen_string_literal: true

module Dependabot
  module Twirp
    class SecretClient < Dependabot::Twirp::BaseClient
      def get_secret(workflow_run_id:)
        rpc(:GetSecret, workflow_run_id: workflow_run_id)
      end

      private

      def twirp_class
        DependabotApi::V1::SecretServiceClient
      end
    end
  end
end
