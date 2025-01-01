# typed: true
# frozen_string_literal: true

module Actions
  module Environments
    class RequestFormListComponent < ApplicationComponent

      # This component takes a hash of environment names to approval requests
      # for that environment.
      # It chooses one to show and sends the rest as hidden fields.
      def initialize(gate_requests_by_environment:, can_break_glass:)
        @gate_requests_by_environment = gate_requests_by_environment
        @can_break_glass = can_break_glass
      end

    end
  end
end
