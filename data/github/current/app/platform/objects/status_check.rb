# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class StatusCheck < Platform::Objects::Base
      include StatusHelper

      description "A status check for a commit."

      required_capabilities [:mobile_only_schema_mask]

      def self.async_api_can_access?(permission, status)
        Platform::Loaders::ActiveRecord.load(::Repository, status.repository_id).then do |repo|
          permission.async_owner_if_org(repo).then do |org|
            permission.access_allowed?(:read_status, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def self.async_viewer_can_see?(permission, object)
        Platform::Loaders::ActiveRecord.load(::Repository, object.repository_id).then do |source|
          permission.typed_can_see?("Repository", source)
        end
      end

      def self.load_from_global_id(id)
        Platform::Models::StatusCheck.load_from_global_id(id)
      end

      def self.load_from_next_global_id(parsed_id)
        prefix = parsed_id.parts[:prefix]
        repo_id = parsed_id.parts[:repo_id]&.to_i
        id = parsed_id.parts[:id]

        case prefix
        when :sch_status
          Platform::Models::StatusCheck.load_from_global_id("status:#{repo_id}:#{id}")
        when :sch_check_run
          Platform::Models::StatusCheck.load_from_global_id("check_run:#{repo_id}:#{id}")
        when :sch_required
          Platform::Models::StatusCheck.load_from_global_id("required:#{repo_id}:#{id}")
        when :sch_memory
          rule_config_id = parsed_id.parts[:rule_config_id]
          Platform::Models::StatusCheck.load_from_global_id("memory:#{repo_id}:#{rule_config_id}:#{id}")
        when :sch
          # Fallback for generic template
          Platform::Models::StatusCheck.load_from_global_id("#{repo_id}:#{id}")
        else
          raise Platform::Errors::NotFound, "Template prefix '#{prefix}' does not match an existing global id template"
        end
      end

      implements_node templates: [
        [:sch, :repo_id, :id],
        [:sch_status, :repo_id, :id],
        [:sch_check_run, :repo_id, :id],
        [:sch_required, :repo_id, :id],
        [:sch_memory, :repo_id, :rule_config_id, :id]
      ], as: "SCH", ready_date: "1970-01-01", uses_database_id: false do |status_check|
        case status_check.status
        when ::Status
          {
            prefix: :sch_status,
            repo_id: status_check.repository_id,
            id: status_check.status.id
          }
        when CombinedStatus::CheckRunAdapter
          {
            prefix: :sch_check_run,
            repo_id: status_check.repository_id,
            id: status_check.status.id
          }
        when ::RequiredStatusCheck
          {
            prefix: :sch_required,
            repo_id: status_check.repository_id,
            id: status_check.status.id
          }
        when InMemoryRequiredStatusCheck
          if status_check.status.protected_branch_backed?
            # For ProtectedBranch-backed checks, use the underlying RequiredStatusCheck's ID
            {
              prefix: :sch_required,
              repo_id: status_check.repository_id,
              id: T.must(status_check.status.status_check).id
            }
          else
            # For Ruleset-backed checks, use rule_config.id and context_hash
            {
              prefix: :sch_memory,
              repo_id: status_check.repository_id,
              rule_config_id: status_check.status.rule_config.id,
              id: status_check.status.context_hash
            }
          end
        else
          {
            prefix: :sch,
            repo_id: status_check.repository_id,
            id: status_check.id
          }
        end
      end

      field :description, String, null: true, description: "The description of the status check."

      def description
        @object.status.description || default_status_check_description(@object.status.state)
      end

      field :duration_in_seconds, Integer, null: false, description: "The duration of the status check in seconds."

      def duration_in_seconds
        @object.status.duration_in_seconds
      end

      field :state_changed_at, Scalars::DateTime, null: false, description: "The time when the state of the status check last changed."

      def state_changed_at
        @object.status.state_changed_at
      end

      field :is_required, Boolean, null: false, description: "Whether the status check is required."

      def is_required
        return false unless @object.pull_request

        case @object.status
        when PullRequests::External::Domain::StatusChecks::IStatusCheck
          @object.status.required?
        else
          @object.status.required_for_pull_request?(@object.pull_request) || false
        end
      end

      field :display_name, String, null: false, description: "The display name of the status check."

      def display_name
        @object.status.contextual_name || ""
      end

      field :state, Platform::Enums::StatusCheckState, null: false, description: "The state of the status check."

      def state
        @object.status.state
      end

      field :target_url, Scalars::URI, null: true, description: "The target URL of the status check."

      def target_url
        status_check_target_url(@object.status, @object.pull_request)
      end

      field :avatar_url, Scalars::URI, null: true, description: "The avatar URL associated with the status check."

      def avatar_url
        status_check_avatar_url(@object.status, size: 40)
      end

      field :additional_context, String, null: false, description: "Additional context for the status check."

      def additional_context
        status = @object.status
        status_check_additional_context(status.state, status.duration_in_seconds, status.state_changed_at)
      end

      field :copilot_check_run_failure_context, Platform::Objects::CopilotCheckRunFailureContext, null: true, description: "Context for Copilot check run failures, if applicable."

      def copilot_check_run_failure_context
        job_id = status_check_copilot_failure_job_id(@object.status)
        return nil unless job_id

        # Try to get head_ref from the associated pull request
        # If PR is not already set, try to find it from the check_suite
        head_ref = @object.pull_request&.head_ref
        if head_ref.nil? && @object.status.is_a?(CombinedStatus::CheckRunAdapter)
          check_suite = @object.status.check_suite
          if check_suite
            matching_pr = check_suite.matching_pull_requests.first
            head_ref = matching_pr&.head_ref
          end
        end

        CopilotCheckRunFailureContext.new(job_id: job_id, head_ref: head_ref)
      end

      field :underlying_context, Unions::StatusCheckRollupContext, null: true, description: "The underlying status context or check run for this status check."

      def underlying_context
        status = @object.status

        case status
        when ::Status
          status
        when CombinedStatus::CheckRunAdapter
          status.__getobj__
        when PullRequests::External::StatusCheckFinder::Record
          if (check_run = status.as_check_run)
            check_run.__getobj__
          elsif status.check_type == "Status"
            Platform::Loaders::ActiveRecord.load(::Status, status.identifier.to_i)
          else
            nil
          end
        else
          nil
        end
      end
    end
  end
end
