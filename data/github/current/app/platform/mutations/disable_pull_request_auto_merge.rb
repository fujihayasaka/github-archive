# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DisablePullRequestAutoMerge < Platform::Mutations::Base
      description "Disable auto merge on the given pull request"

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "ID of the pull request to disable auto merge on.", required: true, loads: Objects::PullRequest

      error_fields
      field :pull_request, Objects::PullRequest, "The pull request auto merge was disabled on.", null: true
      field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true

      extras [:execution_errors]

      def self.async_api_can_modify?(permission, **inputs)
        pull = inputs[:pull_request]
        permission.async_repo_and_org_owner(pull).then do |repo, org|
          pull.async_issue.then do |_issue|
            permission.access_allowed?(:disable_pull_request_auto_merge, repo: repo, resource: pull, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(execution_errors:, **inputs)
        pull       = inputs[:pull_request]
        repository = pull.repository

        context[:permission].authorize_content(:pull_request, :auto_merge, repo: repository)

        if !pull.disable_auto_merge_allowed?(actor: context[:viewer])
          message = "Can't disable auto-merge for this pull request."
          raise Errors::Unprocessable.new(message)
        end

        if pull.auto_merge_request
          pull.auto_merge_request.disable(:manually_disabled, actor: context[:viewer])
          # update database
          pull.reload

          if !pull.auto_merge_request
            # Auto merge successfully disabled
            {
              pull_request: pull,
              actor: context[:viewer],
              errors: []
            }
          else
            message = "Failed disabling auto-merge for pull request"
            raise Errors::Unprocessable.new(message)
          end
        else
          # Auto merge was never enabled in the first place.
          # this isn't technically an error since the PR is in the desired state.
          # but we should make note of it.
          message = "Can't disable auto-merge because it was not enabled."
          {
            pull_request: pull,
            actor: context[:viewer],
            errors: [{
              message: message,
              short_message: message,
              attribute: "Auto-merge was not enabled for this PR",
            }]
          }
        end
      rescue AutoMergeRequest::Invalid => e
        raise Errors::Unprocessable.new(e.to_s)
      end
    end
  end
end
