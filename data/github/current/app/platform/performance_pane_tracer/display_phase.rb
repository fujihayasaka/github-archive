# typed: true
# frozen_string_literal: true

module Platform
  module PerformancePaneTracer
    # This is like a `DisplayStep`, it's rendered into the tree
    # but it's always a first-level child of `DisplayQuery` and
    # it displays one of the phases of executing a query.
    class DisplayPhase
      attr_reader :name, :path, :total_ms, :own_ms, :total_allocated_objects, :children, :children_ms
      def initialize(name:, path:, total_ms:, children: {})
        @name = name
        @path = path
        @total_ms = total_ms
        @children = children
        @total_allocated_objects = nil
      end

      def freeze_stats
        @children.each_value(&:freeze_stats)
        @children_ms = children.values.sum(&:total_ms)
        @own_ms = @total_ms - @children_ms
        freeze
      end
    end
  end
end
