# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module ActionsResults
      # The address of the results-core service.
      #
      # e.g. "https://actions-results-blob-production.service.iad.github.net"
      attr_accessor :actions_results_core_address

      # List of space delimited HMAC secrets used to sign requests between dotcom and actions-results
      attr_accessor :actions_results_core_twirp_hmac_keys
    end
  end

  extend Config::ActionsResults
end
