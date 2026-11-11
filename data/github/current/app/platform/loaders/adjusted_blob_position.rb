# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class AdjustedBlobPosition < Platform::Loader
      def self.load(rpc, adjustment_parameters)
        self.for(rpc).load(adjustment_parameters)
      end

      def initialize(rpc)
        @rpc = rpc
      end

      attr_reader :rpc

      def fetch(adjustment_parameters_list)
        adjusted_lines = rpc.read_commit_adjusted_positions_with_base(adjustment_parameters_list, skip_bad: true)
        Hash[adjustment_parameters_list.zip(adjusted_lines)]
      end
    end
  end
end
