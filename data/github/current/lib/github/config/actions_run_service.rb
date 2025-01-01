# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module ActionsRunService
      # List of space delimited HMAC secrets used to sign requests between dotcom and actions-run-service
      attr_accessor :actions_run_service_twirp_hmac_keys

      # List of space delimited HMAC secrets used to sign requests between dotcom and actions-run-service-lab
      attr_accessor :actions_run_service_lab_twirp_hmac_keys

    end
  end

  extend Config::ActionsRunService
end
