# typed: strict
# frozen_string_literal: true

require "vexi/adapters/in_memory_adapter"

module FeatureFlag
  module Adapters
    class InMemoryAdapter
      include TestAdapter

      delegate :features, :get_feature_flags, :get_segments, :adapter_name, to: :@vexi_in_memory_adapter

      sig { params(shared_storage: Vexi::FeatureFlagStorage).void }
      def initialize(shared_storage: Vexi::FeatureFlagStorage.new)
        @shared_storage = T.let(shared_storage, Vexi::FeatureFlagStorage)
        @vexi_in_memory_adapter = T.let(Vexi::Adapters::InMemoryAdapter.new(shared_storage: @shared_storage), Vexi::Adapters::InMemoryAdapter)
      end

      sig { override.void }
      def reset
        @shared_storage.reset
      end
    end
  end
end
