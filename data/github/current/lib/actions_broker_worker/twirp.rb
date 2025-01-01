# typed: true
# frozen_string_literal: true

module ActionsBrokerWorker
  module Twirp
    autoload :BaseClient, "actions_broker_worker/twirp/base_client"
    autoload :NullClient, "actions_broker_worker/twirp/null_client"

    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < BaseError; end
  end
end
