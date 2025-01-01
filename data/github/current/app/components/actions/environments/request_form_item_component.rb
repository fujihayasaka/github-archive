# typed: true
# frozen_string_literal: true

module Actions
  module Environments
    class RequestFormItemComponent < ApplicationComponent
      attr_reader :gate_requests

      def initialize(gate_requests:, can_break_glass:)
        @gate_requests = gate_requests
        @can_break_glass = can_break_glass
      end

      # This component takes one or more gate requests that should be for the same environment
      # and displays only one of them.
      memoize def shown_request
        @gate_requests.first
      end

      memoize def hidden_requests
        @gate_requests[1..]
      end

      def environment
        @environment = shown_request.gate.environment.name
      end

      # Environments are ID'ed by name, so every gate request here should have the same set of approvers.
      memoize def approvers
        shown_request.gate.gate_approvers.filter_map { |gate_approver| gate_approver.approver if show_approver?(gate_approver.approver) }
      end

      def show_approver?(approver)
        return approver.visible_to?(current_user) if approver.is_a?(Team)

        if approver == current_user
          !shown_request.gate.prevent_self_review?
        else
          true
        end
      end

      def approvers_text
        approvers.map { |approver| name_for(approver) }.join(", ")
      end

      memoize def truncated_approvers_list
        if approvers.size <= 2
          @truncated_approvers_list = approvers.map { |approver| name_for(approver) }
        else
          @truncated_approvers_list = [name_for(approvers.first), name_for(approvers.second), pluralize(approvers.size - 2, "other")]
        end
      end

      def name_for(approver)
        approver.is_a?(User) ? approver.display_login : approver.name
      end

      memoize def aria_id_prefix
        "gate_request_#{SecureRandom.hex(4)}"
      end
    end
  end
end
