# typed: true
# frozen_string_literal: true

module ActionsDataStream
  module Twirp

    autoload :BaseClient, "actions_data_stream/twirp/base_client"
    autoload :NullClient, "actions_data_stream/twirp/null_client"
    autoload :SinkClient, "actions_data_stream/twirp/sink_client"

    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < BaseError; end

    sig { returns(SinkClient) }
    def self.sink_client
      @sink_client ||= SinkClient.new
    end
  end
end
