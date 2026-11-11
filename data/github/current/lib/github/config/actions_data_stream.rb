# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module ActionsDataStream
      # The address of the actions-data-stream Twirp endpoint.
      #
      # e.g. "https://actions-data-stream-twirp-production.service.iad.github.net"
      attr_accessor :actions_data_stream_twirp_address

      # List of space delimited HMAC secrets used to sign requests between dotcom and actions-data-stream
      attr_accessor :actions_data_stream_twirp_hmac_key
    end
  end

  extend Config::ActionsDataStream
end
