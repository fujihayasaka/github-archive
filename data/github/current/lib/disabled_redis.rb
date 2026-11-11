# typed: true
# frozen_string_literal: true

require "github/unexpected_datastore_access"

class DisabledRedis
  class Client
    # noop initialize
    def initialize(*args, &block); end

    # noop connect methods
    def connect; end
    def disconnect; end
    def reconnect; end

    def method_missing(method_name, *args, &block)
      raise ::GitHub::UnexpectedDatastoreAccess.new <<-ERR
        You have attempted to use a Redis connection that is disabled,
        likely because performing the operation would result in a round
        trip to the active datacenter.
      ERR
    end
  end

  attr_reader :client

  def initialize(*args, &block)
    @client = Client.new
  end

  def method_missing(method_name, *args, &block)
    raise ::GitHub::UnexpectedDatastoreAccess.new <<-ERR
      You have attempted to use a Redis connection that is disabled,
      likely because performing the operation would result in a round
      trip to the active datacenter.
    ERR
  end
end
