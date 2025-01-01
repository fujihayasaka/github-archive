# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateIssuesBulkByQuery < Platform::Mutations::Base
      description "Perform a bulk update to a set of issues."

      minimum_accepted_scopes ["public_repo"]
      visibility :internal
      input_object_class Platform::Inputs::IssueBulkInput
      include Shared::IssuesBulkUpdate

      argument :query, String, "The search query to find the issues to modify. Limit #{Platform::Inputs::IssueBulkInput::MAX_ISSUES}", required: true
      argument :repository_id, ID, "The ID of the repository to search in.", required: true, loads: Objects::Repository, as: :repository
      # not required in case we want to add more arguments in the future (title or body)
      error_fields
      field :job_id, ID, "The ID of the bulk edit job status object.", null: true


      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :set_collab_only_attributes_on_new_issue,
          repo: inputs[:repository],
          current_org: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
          raise_on_error: false
        )
      end

      def resolve(**inputs)
        if inputs.key?(:issue_type_id)
          issue_type = Helpers::IssueTypes.load_by_id(inputs[:issue_type_id], context)
          inputs[:issue_type] = issue_type
        end

        job_params = construct_job_params(inputs)

        if job_params.empty?
          raise Errors::Unprocessable.new("No parameters were provided. Please provide at least one parameter to update.")
        end

        args = {
          phrase: inputs[:query],
          repo_id: inputs[:repository].id,
          aggregations: nil,
          page: 1,
          per_page: Platform::Inputs::IssueBulkInput::MAX_ISSUES,
          current_user: context[:viewer],
          source_fields: ["database_id"],
          context: "#{self.class.name&.demodulize.underscore}-#{__method__}",
        }
        result = Search::Queries::IssueQuery.new(args).execute

        if result.total > Platform::Inputs::IssueBulkInput::MAX_ISSUES
          raise Errors::Unprocessable.new("The search query returned more than #{Platform::Inputs::IssueBulkInput::MAX_ISSUES} issues. Please refine your search query.")
        elsif result.total == 0
          raise Errors::Unprocessable.new("The search query returned no issues. Please refine your search query.")
        end
        issues = result.results.map do |issue|
          issue["_model"]
        end

        status_params = {
          user_id: context[:viewer].id,
          parent_global_relay_id: issues[0].repository.global_relay_id,
          ttl: Platform::Inputs::IssueBulkInput::TTL
        }
        if context[:viewer]&.feature_flag_enabled_or_raise?(:issue_triage_job_new_kv_storage_for_status) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          status = Issues::JobStatusSubscription.create(status_params.merge(repository_id: inputs[:repository].id))
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
        tags << "is_using_query:true"

        GitHub.dogstats.increment(Platform::Inputs::IssueBulkInput::DATADOG_METRIC_NAME, tags: tags)

        {
          job_id: status.id,
          errors: []
        }
      end
    end
  end
end
