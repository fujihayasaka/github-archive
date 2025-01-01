# typed: true
# frozen_string_literal: true

module Search
  class Aggregator
    def self.instance
      Thread.current[:search_aggregator] ||= new
    end

    def initialize
      reset
    end

    def reset
      @enabled = false
      @indexes_rollup = Hash.new
    end

    def aggregate
      @enabled = true
      yield
    ensure
      @enabled = false
    end

    def enabled?
      @enabled
    end

    attr_reader :indexes_rollup

    def enqueue(job, message, job_options = {})
      type = message[0]
      id = message[1]
      opts = message.last.is_a?(::Hash) ? message.last.symbolize_keys : nil

      key = opts&.dig(:guid) || [type, id]
      key = Array(key).unshift(job)
      @indexes_rollup[key] = [job, message, job_options, DatabaseSelector::ReplicationState.current&.to_hash]
    end

    def rollup
      @indexes_rollup.each_value do |job, message, options, replication_state|
        yield(job, message, options, replication_state) if block_given?
      end
      @indexes_rollup.clear
    end
  end
end
