# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module ActionsBrokerWorker
      # The address of the broker-worker service.
      #
      # e.g. "https://actions-broker-worker-production.service.iad.github.net"
      attr_accessor :actions_broker_worker_address

      # The address of the broker-worker service.
      # e.g. "https://actions-broker-worker-lab.service.iad.github.net"
      attr_accessor :actions_broker_worker_address_lab

      # List of space delimited HMAC secrets used to sign requests between dotcom and actions-broker-worker
      attr_accessor :actions_broker_worker_twirp_hmac_keys

      # List of space delimited HMAC secrets used to sign requests between dotcom and actions-broker-worker-lab
      attr_accessor :actions_broker_worker_twirp_hmac_keys_lab
    end
  end

  extend Config::ActionsBrokerWorker
end
