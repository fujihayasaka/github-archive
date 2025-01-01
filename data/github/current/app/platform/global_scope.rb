# typed: true
# frozen_string_literal: true
module Platform
  class GlobalScope
    class << self
      delegate :queries, :tracers, :accessed_objects, to: :collector
    end

    def self.collector
      GitHub::DataCollector::PlatformGlobalScopeCollector.get_instance
    end

    def self.reset!
      collector.reset
      self.origin = nil
      self.mutation = false
      Platform::LoaderTracker.reset!
    end

    def self.origin
      Thread.current[:platform_global_scope_origin]
    end

    def self.origin=(origin)
      Thread.current[:platform_global_scope_origin] = origin
    end

    def self.mutation
      Thread.current[:platform_global_scope_mutation]
    end

    def self.mutation=(mutation)
      Thread.current[:platform_global_scope_mutation] = mutation
    end

    def self.query_count
      self.queries.count
    end

    def self.query_time
      return 0.0 if self.queries.blank?
      self.queries.reduce(0.0) { |acc, hash| acc + hash[:stats][:real] } / 1000
    end

    def self.mutation?
      !!self.mutation
    end

    def self.origin_api?
      Platform::ORIGIN_API == self.origin
    end

    def self.origin_rest_api?
      Platform::ORIGIN_REST_API == self.origin
    end

    def self.origin_internal?
      Platform::ORIGIN_INTERNAL == self.origin
    end

    def self.origin_manual_execution?
      Platform::ORIGIN_MANUAL_EXECUTION == self.origin
    end
  end
end
