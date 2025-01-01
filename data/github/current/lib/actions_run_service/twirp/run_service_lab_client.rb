# typed: true
# frozen_string_literal: true

require "actions-run-service"

module ActionsRunService
  module Twirp
    class RunServiceLabClient < ActionsRunService::Twirp::RunServiceClient
      def initialize(base_url:)
        super(
          base_url: base_url,
          actions_run_service_twirp_hmac_keys: GitHub.actions_run_service_lab_twirp_hmac_keys,
          )
      end
    end
  end
end
