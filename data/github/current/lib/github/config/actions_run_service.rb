# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module ActionsRunService
      # URL for direct round-robin access to run-service (used for stafftools)
      attr_accessor :actions_run_service_address

      # URL for direct round-robin access to run-service-lab (used for stafftools)
      attr_accessor :actions_run_service_lab_address

      # List of space delimited HMAC secrets used to sign requests between dotcom and actions-run-service
      attr_accessor :actions_run_service_twirp_hmac_keys

      # List of space delimited HMAC secrets used to sign requests between dotcom and actions-run-service-lab
      attr_accessor :actions_run_service_lab_twirp_hmac_keys

    end
  end

  extend Config::ActionsRunService
end
