# typed: true
# frozen_string_literal: true

module Actions
  module Environments
    class ApprovalsBannerComponent < ApplicationComponent
      include GateRequestHelper

      attr_reader :workflow_run

      def initialize(pending_gate_requests:, approval_path:, workflow_run:, execution: nil)
        @pending_gate_requests = pending_gate_requests
        @approval_path = approval_path
        @workflow_run = workflow_run
        GitHub::PrefillAssociations.prefill_associations(workflow_run, [:repository, check_suite: [:creator]])
        @execution = execution
      end

      def render?
        return true unless @execution.present?
        # if an execution is passed in, only render for current execution
        @execution.is_latest_execution?
      end

      def workflow_run_actor
        check_suite = @workflow_run.check_suite
        check_suite&.creator || check_suite&.pusher
      end

      # Requests that the current user has permission to approve
      memoize def approvable_gate_requests
        pending_requests(@pending_gate_requests)
      end

      def pending_approval_requests
        @pending_gate_requests.filter { |r| r.state == "closed" && r.gate.type == "manual_approval" }
      end

      def environments
        if approvable_gate_requests.any?
          approvable_gate_requests.map { |gate_request| gate_request.gate&.environment }
        else
          @pending_gate_requests.map { |gate_request| gate_request.gate&.environment }
        end
      end
    end
  end
end
