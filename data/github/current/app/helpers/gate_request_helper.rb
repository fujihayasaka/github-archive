# typed: false
# frozen_string_literal: true

# Helper methods for approvals
module GateRequestHelper
  def gate_requests_for(pull_request:, user:)
    return @gate_requests if defined?(@gate_requests)
    @gate_requests = []
    repository = pull_request.repository

    if repository.adminable_by?(user) && repository.can_use_environments?
      check_suites = with_database_error_fallback(fallback: []) do
        pull_request.matching_check_suites(head_sha: pull_request.head_sha).to_a
      end

      check_suites.each do |check_suite|
        @gate_requests = @gate_requests.concat(pending_gate_requests(check_suite))
      end
    end
    @gate_requests
  end

  def is_pending_approval(gate_requests)
    pending_requests(gate_requests).any?
  end

  def pending_requests(gate_requests)
    gate_requests.filter { |gate_request| gate_request.approval_status(current_user) == "pending" }
  end

  def approval_pending_environments(pending_gate_requests)
    pending_gate_requests.map { |gate_request| gate_request.gate&.environment }
  end

  def workflow_name(job_name, workflow_number)
    "#{job_name} ##{workflow_number}"
  end

  def pending_gate_requests(check_suite)
    return [] unless check_suite
    GateRequest.includes(gate: :environment).where(check_run_id: check_suite.fetch_latest_waiting_check_run_ids)
  end
end
