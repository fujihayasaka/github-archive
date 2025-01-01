# typed: true
# frozen_string_literal: true

module Actions
  module Environments
    class GatesBreakGlassDialogComponent < ApplicationComponent

      def initialize(gate_requests:, approvable_gate_requests_by_environment:, can_break_glass:)
        @gate_requests = gate_requests
        @approvable_gate_requests_by_environment = approvable_gate_requests_by_environment
        @can_break_glass = can_break_glass
      end
    end
  end
end
