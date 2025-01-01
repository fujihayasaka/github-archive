# frozen_string_literal: true

require_relative "fjord_sink"
require_relative "utilities"

module Cargo
  # base class w/shared boilerplate for API and snapshot backed importer impls
  class Base
    include Logging

    attr_accessor :fjord_sink

    def initialize(fjord_sink: nil)
      @fjord_sink = fjord_sink || Cargo::FjordSink.new(fjord_url: FJORD_URL, checkpoints_url: CHECKPOINTS_URL)
      # we must use the logger once without context to initialize it
      logger.info("Initialized Cargo PMA")
    end

    def get_checkpoint(checkpoint_name)
      value = fjord_sink.get_checkpoint(checkpoint_name)
      checkpoint = value.to_i
      Scrolls.context(
        "gh.dependency_graph.backfill.checkpoint_name" => checkpoint_name,
        "gh.dependency_graph.backfill.checkpoint_value" => checkpoint,
      ) do
        logger.info("Checkpoint found")
      end

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
      Scrolls.context(
        "gh.dependency_graph.backfill.checkpoint_name" => checkpoint_name,
        "gh.dependency_graph.backfill.checkpoint_value" => unixtime,
      ) do
        logger.info("Set new checkpoint")
      end
    end
  end
end
