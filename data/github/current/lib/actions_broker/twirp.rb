# typed: true
# frozen_string_literal: true

module ActionsBroker
  module Twirp
    autoload :BaseClient, "actions_broker/twirp/base_client"
    autoload :NullClient, "actions_broker/twirp/null_client"

    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < BaseError; end
  end
end
