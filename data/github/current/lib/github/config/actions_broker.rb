# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module ActionsBroker
      # The address of the results-core service.
      #
      # e.g. "https://actions-broker-blob-production.service.iad.github.net"
      attr_accessor :actions_broker_address

      # The address of the runner-admin service.
      # e.g. "https://actions-broker-lab.service.iad.github.net"
      attr_accessor :actions_broker_address_lab

      # List of space delimited HMAC secrets used to sign requests between dotcom and actions-broker
      attr_accessor :actions_broker_twirp_hmac_keys

      # List of space delimited HMAC secrets used to sign requests between dotcom and actions-broker
      attr_accessor :actions_broker_twirp_hmac_keys_lab
    end
  end

  extend  Config::ActionsBroker
end
