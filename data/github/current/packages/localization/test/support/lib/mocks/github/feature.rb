# typed: true
# frozen_string_literal: true

module Mocks
  module GitHub
    class Feature
      def initialize(name, enabled:)
        @name = name
        @enabled = enabled
        @actors = {}
      end

      def enabled?(actor = nil)
        if @enabled
          return true
        end

        if actor && @actors.key?(actor_key(actor))
          return @actors[actor_key(actor)]
        end

        @enabled
      end

      def enable(actor = nil)
        if actor
          return for_actor(actor, true)
        end

        @enabled = true
      end

      def disable(actor = nil)
        if actor
          return for_actor(actor, false)
        end

        @enabled = false
      end

      private

      def for_actor(actor, flag)
        @actors[actor_key(actor)] = flag
      end

      def actor_key(actor)
        "#{actor.class}::#{actor.id}"
      end
    end
  end
end
