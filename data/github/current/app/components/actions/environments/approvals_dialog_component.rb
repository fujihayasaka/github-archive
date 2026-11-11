# typed: true
# frozen_string_literal: true

module Actions
  module Environments
    class ApprovalsDialogComponent < ApplicationComponent
      include GateRequestHelper

      def initialize(pending_gate_requests:, approval_path:, actor: nil, check_suite:, in_check_run_logs_page:)
        @pending_gate_requests = pending_gate_requests
        @approval_path = approval_path
        @actor = actor
        @check_suite = check_suite
        @in_check_run_logs_page = in_check_run_logs_page
      end

      # A hash of environment names to the list of requests for that environment.
      memoize def pending_gate_requests_by_environment
        @pending_gate_requests.group_by { |gate_request| gate_request.gate&.environment&.name }
      end

      # Requests that the current user has permission to approve
      memoize def approvable_gate_requests
        pending_requests(@pending_gate_requests)
      end

      memoize def approvable_gate_requests_by_environment
        approvable_gate_requests.group_by { |gate_request| gate_request.gate&.environment&.name }
      end

      # Requests that the current user does not have permission to approve
      memoize def unapprovable_gate_requests
        @pending_gate_requests.filter { |gate_request| gate_request.approval_status(current_user).to_s != "pending" }
      end

      memoize def unapprovable_gate_requests_by_environment
        unapprovable_gate_requests.group_by { |gate_request| gate_request.gate&.environment&.name }
      end

      memoize def environments
        @pending_gate_requests.map { |gate_request| gate_request.gate&.environment }
      end

      memoize def aria_id_prefix
        "#{SecureRandom.hex(4)}"
      end
    end
  end
end
