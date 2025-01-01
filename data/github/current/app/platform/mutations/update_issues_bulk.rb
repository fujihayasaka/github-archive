# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateIssuesBulk < Platform::Mutations::Base
      description "Perform a bulk update to a set of issues."

      minimum_accepted_scopes ["public_repo"]
      visibility :internal

      error_fields
      field :job_id, ID, "The ID of the bulk edit job .", null: true
      input_object_class Platform::Inputs::IssueBulkInput
      argument :ids, [ID], "The IDs of the Issue to modify. Limit #{Platform::Inputs::IssueBulkInput::MAX_ISSUES}", required: true, loads: Objects::Issue, as: :issues, validates: { length: { minimum: 1, maximum: Platform::Inputs::IssueBulkInput::MAX_ISSUES } }

      include Shared::IssuesBulkUpdate
      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        promises = inputs[:issues].map do |issue|
          permission.async_repo_and_org_owner(issue).then do |repo, org|
            permission.access_allowed?(:edit_issue, resource: issue, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
        promises.map(&:value).all?
      end

      def resolve(**inputs)
        if inputs.key?(:issue_type_id)
          issue_type = Helpers::IssueTypes.load_by_id(inputs[:issue_type_id], context)
          inputs[:issue_type] = issue_type
        end

        current_repo_id = T.let(nil, T.untyped)
        issues = inputs[:issues]

        issues.each do |issue|
          if current_repo_id.nil?
            current_repo_id = issue.repository_id
          elsif current_repo_id != issue.repository_id
            raise Errors::Forbidden, "All issues must be in the same repository."
          end
        end

        # only check the first issue for permissions since we already checked that all issues are in the same repo
        if !context[:actor].can_have_granular_permissions? && !issues[0].async_viewer_can_update?(context[:viewer]).sync
          message = "#{context[:viewer].display_login} does not have permission to update the issue #{issues[0].global_relay_id}."
          raise Errors::Forbidden.new(message)
        end

        job_params = construct_job_params(inputs)
        if job_params.empty?
          raise Errors::Unprocessable.new("No parameters were provided. Please provide at least one parameter to update.")
        end

        status_params = {
          user_id: context[:viewer].id,
          parent_global_relay_id: issues[0].repository.global_relay_id,
          ttl: Platform::Inputs::IssueBulkInput::TTL
        }
        if context[:viewer]&.feature_flag_enabled_or_raise?(:issue_triage_job_new_kv_storage_for_status) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          status = Issues::JobStatusSubscription.create(status_params.merge(repository_id: issues.first.repository_id))
        else
          status = JobStatusSubscription.create(status_params)
        end

        # the job runs on the database ids
        job = IssueTriageJob.perform_later(status.id, issues.map(&:id), context[:viewer].id, job_params)
        if job.respond_to?(:job_id)
          status.set_job_id(T.unsafe(job).job_id)
        end

        # add telemetry
        tags = get_tags(inputs, issues.length)
        tags << "is_using_query:false"

        GitHub.dogstats.increment(Platform::Inputs::IssueBulkInput::DATADOG_METRIC_NAME, tags: tags)

        {
          job_id: status.id,
          errors: []
        }
      end
    end
  end
end
