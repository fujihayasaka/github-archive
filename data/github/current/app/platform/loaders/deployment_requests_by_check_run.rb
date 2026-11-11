# typed: false
# frozen_string_literal: true

module Platform
  module Loaders
    class DeploymentRequestsByCheckRun < Platform::Loader
      def self.load(viewer, check_run_id)
        self.for(viewer).load(check_run_id)
      end

      def initialize(viewer)
        @viewer = viewer
      end

      def fetch(check_run_ids)
        gate_requests = ::GateRequest
          .includes(gate: [{ environment: :repository }, { gate_approvers: :approver }])
          .includes(gate_approvals: [:user])
          .where(check_run_id: check_run_ids)

        closed_requests = gate_requests.select { |gr| gr.state.to_s == "closed" }

        # Batch-preload the :business association on all BusinessTeam approvers
        all_biz_teams = closed_requests
          .flat_map { |gr| gr.gate.gate_approvers }
          .select { |ga| ga.approver_type == "BusinessTeam" }
          .filter_map(&:approver)
          .uniq
        ::ActiveRecord::Associations::Preloader.new(records: all_biz_teams, associations: :business).call if all_biz_teams.any?

        grouped_requests = closed_requests.group_by { |gr| gr.check_run_id }
        grouped_requests.transform_values do |gate_requests|
          gate_approvers = gate_requests.map { |gate_request| gate_request.gate.gate_approvers }.flatten
          environment = gate_requests.first.gate.environment
          repo_org = environment.repository.owner
          all_approvers = gate_approvers.map { |gate_approver| gate_approver.approver }.compact

          biz_teams = all_approvers.select { |a| a.is_a?(::BusinessTeam) }
          biz_teams.each { |bt| bt.set_organization_context(repo_org, check_association: false) } if biz_teams.any?

          reviewers = all_approvers
          reviewers_wrapper = ArrayWrapper.new(reviewers)
          can_approve = @viewer.nil? ? false : gate_requests.any? { |gate_request| gate_request.approval_status(@viewer) == "pending" }
          wait_timer = gate_requests.map { |gate_request| gate_request.gate.timeout }.max
          wait_timer_started_at = gate_requests.find { |gate_request| gate_request.gate.type == "timeout" }&.created_at
          ::DeploymentRequest.new(environment, reviewers_wrapper, can_approve, wait_timer, wait_timer_started_at)
        end
      end
    end
  end
end
