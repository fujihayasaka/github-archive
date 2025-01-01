# typed: true
# frozen_string_literal: true

module Flipper
  module Adapters
    # LazyActors is a flipper adapter that lazily evaluates
    # features, per-actor, for a given set of features.
    class LazyActors
      include ::Flipper::Adapter

      attr_reader :name

      # Public.
      #
      # adapter - a Flipper::Adapter that responds to 'feature_enabled?'.
      #
      # lazy_features - The list of feature keys (strings) that should be
      #                 checked lazily.
      def initialize(adapter, lazy_features)
        @name = :lazy_actors
        @adapter = adapter
        @lazy_features = lazy_features
      end

      delegate :features, :add, :remove, :clear, :enable, :disable,
        to: :@adapter

      # Public.
      def get(feature)
        if lazy?(feature.key)
          @adapter.get(feature).merge(lazy_gate.key => actors_for(feature.key))
        else
          @adapter.get(feature)
        end
      end

      # Public.
      def get_multi(features)
        @adapter.get_multi(features).to_h do |key, feature_flag_config|
          if lazy?(key)
            [key, feature_flag_config.merge(lazy_gate.key => actors_for(key))]
          else
            [key, feature_flag_config]
          end
        end
      end

      private

      def lazy?(feature_key)
        @lazy_features.include?(feature_key)
      end

      def lazy_gate
        @lazy_gate ||= Flipper::Gates::Actor.new
      end

      def actors_for(feature_key)
        ActorLookup.new(@adapter, feature_key)
      end

      # ActorLookup acts enough like a Set so that Flipper will
      # use this to check if a feature is enabled for an actor.
      class ActorLookup
        def initialize(adapter, feature_key)
          @adapter = adapter
          @feature_key = feature_key
        end

        # Public.
        #
        # Evaluate the current feature for the given actor.
        def include?(actor_flipper_id)
          @adapter.feature_enabled?(@feature_key, actor_flipper_id)
        end

        # Public.
        #
        # We don't know yet if this is actually empty, but flipper
        # will call this method and expect it to return false in
        # order to keep using it.
        def empty?
          return @actors_value.empty? if @actors_value
          false
        end

        # Public.
        #
        # Flipper tries to coerce this object into a Set, but we
        # don't want to!
        def to_set
          return @actors_value.to_set if @actors_value
          self
        end

        # Public.
        #
        # Used by the InMemory adapter to check the size (in actors)
        # of all the flags it loads.
        def size
          return @actors_value.to_set.size if @actors_value
          0
        end

        include Enumerable
        delegate :each, to: :actors_value

        private

        def actors_value
          @actors_value ||= @adapter.actors_value(@feature_key)
        end
      end
    end
  end
end
