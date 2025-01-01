# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class PlatformGlobalScopeCollector < Collector
      set_callback :reset, :after do |collector|
        collector.queries = []
        collector.tracers = []
        collector.accessed_objects = {}
      end

      attributes :queries, :tracers, :accessed_objects

      def self.collector_name
        :platform_global_scope_collector
      end
    end
  end
end
