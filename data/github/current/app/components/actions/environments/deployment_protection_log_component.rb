# typed: true
# frozen_string_literal: true

module Actions
  module Environments
    class DeploymentProtectionLogComponent < ApplicationComponent
      def initialize(check_suite:, gate_approval_logs:, should_update:, execution:)
        @check_suite = check_suite
        @gate_approval_logs = gate_approval_logs
        @should_update = should_update
        @gate_requests = get_gate_requests(check_suite, execution)
      end

      def get_gate_requests(check_suite, execution)
        gate_requests = GateRequest.includes(gate: [:environment, :integration]).where(check_run_id: check_suite.check_run_ids)
        return gate_requests_for_execution(gate_requests, execution) if execution.present?
        gate_requests.to_a
      end

      def gate_requests_for_execution(gate_requests, execution)
        gate_requests.where("created_at BETWEEN ? and ?", execution.started_at || execution.created_at, execution.completed_at || DateTime.now).to_a
      end

      # entries are grouped by pending or complete, then by gate type, then by completed states, then by when they
      # were completed, and finally alphabetically
      memoize def sorted_log_entries
        sort_by_pending_or_complete_state = { "closed" => 0 } # complete states will default to 1 with get_value_or_max
        sort_by_gate_type = { "manual_approval" => 0, "timeout" => 1, "custom" => 2, "" => 3 } # an empty gate type indicates a deleted environment
        sort_by_complete_state = { "open" => 0, "rejected" => 1, "skipped" => 2, "canceled" => 3 }
        now = Time.zone.now

        # gracefully handle when the entry does not include a key by specifying a default value, nil values will cause
        # errors when trying to sort
        entries.sort_by do |e| [
            get_value_or_max(sort_by_pending_or_complete_state, e[:state]),
            get_value_or_max(sort_by_gate_type, e[:gate_type]),
            get_value_or_max(sort_by_complete_state, e[:state]),
            # sort by completed_at, if nil default to the unix epoch (0)
            e[:completed_at] != nil ? now - e[:completed_at] : 0,
            e[:gate_display_name] || ""
          ]
        end
      end

      def can_break_glass?
        is_admin? && break_glass_eligible_gate_requests.any?
      end

      def break_glass_eligible_gate_request_ids
        break_glass_eligible_gate_requests
          .map { |request| request.id }.to_a
      end

      def break_glass_eligible_environment_names
        break_glass_eligible_gate_requests
          .map { |request| request.gate&.environment&.name }.uniq.to_a
      end

      def approvable_gate_requests_by_environment
        break_glass_eligible_gate_requests
          .group_by { |request| request.gate&.environment&.name }
      end

      def live_update_channels
        channels = live_update_view_channel(@check_suite.workflow_run.gate_requests_channel) # gate requests channel, for pending gates
        channels << " " << live_update_view_channel(@check_suite.workflow_run.approval_logs_channel) # approval logs channel, for reviewed gates
        channels << " " << live_update_view_channel(@check_suite.workflow_run.execution_channel) # execution channel, for when the workflow is re-run

        channels
      end

      def show_invalid_gates_banner?
        is_admin? && pending_custom_gate_requests.any? { |gr| gr[:is_invalid_integration] == true }
      end

      private

      memoize def is_admin?
        current_repository.adminable_by?(current_user)
      end

      def entries
        pending_manual_approval_requests + pending_timer_requests + pending_custom_gate_requests + reviewed_requests
      end

      def break_glass_eligible_gate_requests
        @gate_requests
          .select { |request| request.state == "closed" && request.gate&.environment&.gates_admin_enforced == false }.to_a
      end

      def filter_gate_requests(type)
        return [] if @gate_requests.empty?
        @gate_requests.select { |request| request.gate&.type == type && request.state == "closed" }
      end

      # this returns pending timer gate requests (e.g. timer has not completed)
      def pending_timer_requests
        requests = filter_gate_requests("timeout")
        return [] unless requests.any?

        requests.map do |request|
          {
            comment: (request.gate&.timeout.to_s + " minute wait timer").dup.force_encoding("utf-8"),
            completed_at: request.updated_at,
            display_message: get_timer_display_message(gate_request_state: request.state),
            environments: [request.gate&.environment&.name],
            gate_display_name: "Wait timer",
            gate_type: request.gate&.type.to_s,
            icon_class_name: get_class_name(request.state),
            icon: get_icon(request.state),
            state: request.state,
            gate_request_id: request.id,
          }
        end
      end

      # returns `manual_approval` gate requests that are still `closed` / pending review.
      # we roll these up into one entry because there is only one user (the check suite creator)
      # who requested the review.
      def pending_manual_approval_requests
        requests = filter_gate_requests("manual_approval")
        return [] unless requests.any?

        environments = requests.map { |request| request.gate&.environment&.name }
        gate_request_state = "closed" # `filter_gate_requests` already filtered down to only closed

        [{
          avatar_entity: @check_suite.creator,
          comment: ("-").dup.force_encoding("utf-8"),
          display_message: "requested review",
          environments: environments,
          gate_display_name: @check_suite.creator&.display_login,
          gate_display_url: user_path(@check_suite.creator),
          gate_type: "manual_approval",
          icon_class_name: get_class_name(gate_request_state),
          icon: get_icon(gate_request_state),
          state: gate_request_state,
        }]
      end

      memoize def pending_custom_gate_requests
        requests = filter_gate_requests("custom")
        return [] unless requests.any?

        sorted_comment_logs = @gate_approval_logs.select { |approval_log| approval_log.state == "pending" }.sort_by(&:created_at)

        valid_integrations =
          IntegrationInstallation
          .with_repository(@check_suite.repository)
          .includes(:event_records)
          .filter { |i| i.event_records.map(&:name).include?("deployment_protection_rule") && !i.suspended? }
          .map(&:integration_id)

        requests.map do |request|
          # we only want to show the latest comment
          comment = sorted_comment_logs.reverse_each.find { |approval_log| approval_log.gate_approvals&.pluck(:gate_request_id).include? request.id }&.comment

          integration = request.gate&.integration
          is_invalid_integration = integration.nil? || !valid_integrations.include?(integration&.id)
          invalid_integration_message = "This rule is no longer valid."

          {
            avatar_entity: integration,
            comment: format_comment(comment),
            display_message: is_invalid_integration ? invalid_integration_message : "waiting for app",
            environments: [request.gate&.environment&.name],
            gate_display_name: integration.nil? ? "Deleted app" : integration&.name,
            gate_display_url: integration&.url,
            gate_type: request.gate&.type.to_s,
            icon_class_name: get_class_name(request.state),
            icon: is_invalid_integration ? "alert-fill" : get_icon(request.state),
            state: request.state,
            gate_request_id: request.id,
            is_invalid_integration: is_invalid_integration
          }
        end
      end

      # returns manual approval and custom gates that have been reviewed, or timer gates that are complete
      def reviewed_requests
        return [] unless @gate_approval_logs.any?

        requests = []

        @gate_approval_logs.each do |approval_log|
          next if approval_log.state == "pending"

          environments = approval_log.gate_approvals&.map { |approval| approval&.environment&.name }
          approver = approval_log.user

          gate_request = approval_log.gate_approvals&.first&.gate_request
          gate_type = gate_request&.gate&.type.to_s
          gate_request_state = gate_request&.state
          is_skipped = approval_log.state == "skipped"
          is_canceled = approval_log.state == "canceled"
          if is_skipped
            gate_request_state = "skipped"
          end
          if is_canceled
            gate_request_state = "canceled"
          end

          display_message = get_reviewed_display_message(gate_type: gate_type, gate_request_state: gate_request_state)
          is_deleted = display_message == "deleted"

          integration = gate_request&.gate&.integration

          requests << {
            avatar_entity: integration || approver,
            comment: format_comment(approval_log.comment.dup.force_encoding("utf-8")),
            completed_at: approval_log.created_at,
            display_message: display_message + (is_skipped || is_canceled || is_deleted ? " by #{approver&.display_login}" : ""),
            environments: environments,
            gate_approval_log_id: approval_log.id,
            gate_display_name: gate_type == "timeout" ? "Wait timer" : (integration&.name || approver&.display_login),
            gate_display_url: gate_type == "timeout" ? nil : (integration&.url || user_path(approver)),
            gate_type: gate_type,
            icon_class_name: get_class_name(gate_request_state),
            icon: get_icon(gate_request_state),
            state: gate_request_state,
            gate_request_id: gate_request.id
          }
        end
        requests
      end

      def get_timer_display_message(gate_request_state:)
        case gate_request_state
        when "open" then "completed"
        when "closed" then "waiting"
        end
      end

      def get_reviewed_display_message(gate_type:, gate_request_state:)
        if gate_type.empty?
          "deleted"
        elsif gate_request_state == "skipped"
          "skipped"
        elsif gate_request_state == "canceled"
          "canceled"
        elsif gate_type == "manual_approval"
          gate_request_state == "open" ? "approved" : "rejected"
        elsif gate_type == "custom"
          gate_request_state == "open" ? "passed" : "failed"
        elsif gate_type == "timeout"
          get_timer_display_message(gate_request_state: gate_request_state)
        end
      end

      def get_icon(state)
        case state
        when "skipped"
          "skip-fill"
        when "closed"
          "clock-fill"
        when "open"
          "check-circle-fill"
        when "canceled"
          "x-circle-fill"
        when "rejected"
          "x-circle-fill"
        else
          nil
        end
      end

      def get_class_name(state)
        case state
        when "skipped"
          "color-fg-subtle"
        when "closed"
          "color-fg-attention"
        when "open"
          "color-fg-success"
        when "canceled"
          "color-fg-danger"
        when "rejected"
          "color-fg-danger"
        else
          nil
        end
      end

      def get_value_or_max(hash, key)
        default = hash.values.max + 1
        hash.fetch(key, default)
      end

      def format_comment(comment)
        return "" if comment.blank?

        # this is need for TextDirectionFilter
        context = { entity: try(:current_repository) }
        GitHub::Goomba::ActionsDeploymentProtectionLogPipeline.to_html(comment, context, nil)
      end
    end
  end
end
