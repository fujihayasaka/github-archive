# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class EnablePullRequestAutoMerge < Platform::Mutations::Base
      docs_category :pulls
      include GitHub::Memoizer
      description "Enable the default auto-merge on a pull request."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "ID of the pull request to enable auto-merge on.", required: true, loads: Objects::PullRequest
      argument :commit_headline, String, "Commit headline to use for the commit when the PR is mergable; if omitted, a default message will be used. NOTE: when merging with a merge queue any input value for commit headline is ignored.", required: false
      argument :commit_body, String, "Commit body to use for the commit when the PR is mergable; if omitted, a default message will be used. NOTE: when merging with a merge queue any input value for commit message is ignored.", required: false
      argument :merge_method, Enums::PullRequestMergeMethod, "The merge method to use. If omitted, defaults to `MERGE`. NOTE: when merging with a merge queue any input value for merge method is ignored.", required: false, default_value: :merge
      argument :merge_queue_method, Enums::MergeQueueMethod, "The merge queue method to use. If omitted, defaults to `GROUP`.", required: false, visibility: :internal
      argument :author_email, String, "The email address to associate with this merge.", required: false
      argument :expected_head_oid, Scalars::GitObjectID, "The expected head OID of the pull request.", required: false

      error_fields
      field :pull_request, Objects::PullRequest, "The pull request auto-merge was enabled on.", null: true
      field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        pull = inputs[:pull_request]
        permission.async_repo_and_org_owner(pull).then do |repo, org|
          pull.async_issue.then do |_issue|
            permission.access_allowed?(:enable_pull_request_auto_merge, repo: repo, resource: pull, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(execution_errors:, **inputs)
        pull         = inputs[:pull_request]
        repository   = pull.repository
        author_email = inputs[:author_email]
        expected_head_oid = inputs[:expected_head_oid]
        merge_method = inputs[:merge_queue_method] || inputs[:merge_method]

        context[:permission].authorize_content(:pull_request, :auto_merge, repo: repository)

        check_database_resource_update_rate_limit!(resource: pull, current_user: context[:viewer])

        am_logger.append_pull_request_context(pull)
        am_logger.append_repository_context(repository)

        log_context = {
          user_id: context[:viewer].id,
          user_login: context[:viewer].display_login,
          merge_method: merge_method,
          pr_state: pull.state,
        }

        am_logger.append(log_context)

        # Early validation to avoid unnecessary processing when auto-merge is not allowed
        if FeatureFlag.vexi.enabled?(:early_auto_merge_validation, repository, default: false)
          unless repository.auto_merge_allowed?
            am_logger.append_outcome("auto merge not allowed on repo")
            am_logger.flush
            raise Errors::Unprocessable.new("Auto merge is not allowed for this repository")
          end
        end

        if author_email
          author_email_record = UserEmail.verified.where(user_id: context[:viewer].id, email: author_email)
          unless author_email_record.exists?
            message = "#{context[:viewer].display_login} does not have a verified email, which is required to enable auto-merging."
            am_logger.append_outcome("author email not verified")
            am_logger.flush
            raise Errors::Unprocessable.new(message)
          end
        end

        if expected_head_oid && pull.head_sha != expected_head_oid
          am_logger.append_outcome("head oid mismatch")
          am_logger.flush
          raise Errors::MergeQueue::PullRequestHeadOidMismatch.new(pull)
        end

        merge_queue = MergeQueue.for(repository: pull.base_repository, branch: pull.base_ref)

        merge_queue_context = {
          merge_queue_present: merge_queue.present?,
          in_merge_queue: pull.in_merge_queue?,
        }

        am_logger.append(merge_queue_context)

        if FeatureFlag.vexi.enabled?(:am_refactor_graphql_entrypoint, repository, default: false) && !merge_queue
          case auto_merge_result = PullRequests::AsyncMerge.call(
            pull_request: pull,
            repository: repository,
            actor: context[:viewer],
            mode: :wait,
            merge_method:,
            commit_title: inputs[:commit_headline],
            commit_message: inputs[:commit_body],
            commit_email_address: author_email ? author_email_record.first : nil,
            actor_ip_address: context[:rails_request]&.remote_ip
          )
          when PullRequests::Merge::Results::Created, PullRequests::Merge::Results::AlreadyEnqueued
            # continue if auto merge request is successfully created
          when PullRequests::Merge::Results::AlreadyMerged
            raise Errors::Unprocessable.new("Pull request is already merged")
          when PullRequests::Merge::Results::Error, PullRequests::Merge::Results::Invalid
            raise Errors::Unprocessable.new(auto_merge_result.message)
          else
            T.absurd(auto_merge_result)
          end
        elsif !pull.auto_merge_request && !pull.in_merge_queue?
          am_logger.append_outcome("enable auto merge success")

          AutoMergeRequest.enqueue!(
            pull_request: pull,
            user: context[:viewer],
            merge_method: merge_method,
            email: author_email ? author_email_record.first : nil,
            commit_title: inputs[:commit_headline],
            commit_message: inputs[:commit_body],
            remote_ip: context[:rails_request]&.remote_ip,
          )
        end

        am_logger.flush

        {
          pull_request: pull,
          actor: context[:viewer],
          errors: [],
        }
      rescue AutoMergeRequest::Invalid => e
        raise Errors::Unprocessable.new(e.to_s)
      end

      sig { returns(PullRequests::Shared::Logger) }
      memoize def am_logger
        log = PullRequests::Shared::Logger.new(feature: "auto_merge", default_prefix: "gh.pull_request.auto_merge_request")
        log.append({ phase: "enable_auto_merge" })
        log
      end
    end
  end
end
