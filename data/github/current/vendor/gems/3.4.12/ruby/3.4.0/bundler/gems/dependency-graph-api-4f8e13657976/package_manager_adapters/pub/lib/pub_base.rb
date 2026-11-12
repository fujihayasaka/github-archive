# frozen_string_literal: true

require_relative "fjord_sink"
require_relative "utilities"

module Pub
  # base class w/shared boilerplate for API and snapshot backed importer impls
  class Base
    include Logging

    attr_accessor :fjord_sink

    def initialize(fjord_sink: nil)
      @fjord_sink = fjord_sink || Pub::FjordSink.new(fjord_url: FJORD_URL, checkpoints_url: CHECKPOINTS_URL)
    end

    def get_checkpoint(checkpoint_name)
      value = fjord_sink.get_checkpoint(checkpoint_name)
      checkpoint = value.to_i
      logger.info("Found checkpoint '#{checkpoint_name}' of value: #{checkpoint}")

      checkpoint
    end

    def set_checkpoint(checkpoint_name, value)
      unixtime = case value
        when DateTime
          value.to_time.to_i
        when Time
          value.to_i
        when String
          DateTime.parse(value).to_time.to_i
        else
          raise ArgumentError, "Invalid checkpoint input: #{value}"
        end

      fjord_sink.set_checkpoint(checkpoint_name, unixtime)
      logger.info("Set checkpoint '#{checkpoint_name}' to #{value} as: #{unixtime}")
    end
  end
end
