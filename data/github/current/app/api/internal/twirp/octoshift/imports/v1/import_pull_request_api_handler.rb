# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handles the creation of imported pull request data.
      class ImportPullRequestAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::Attribution

        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportPullRequestAPIService
        allow_access_for :client, allowed_clients: %w[octoshift migrations_vnext]

        # Public: Implementation of the ImportPullRequest Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportPullRequestRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportPullRequestResponse, or a Twirp::Error.
        def import_pull_request(req, env)
          check_model_replication_delay!(ImportablePullRequest)

          if req.author_login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "author_login")
          end
          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end
          if req.title.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "title")
          end
          if req.number.zero? || req.number.negative?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "number")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          # Validate head and base refs, and ensure they exist on the repository
          if twirp_error = validate_refs(req, repository)
            return twirp_error
          end

          user = find_mannequin_or_user_by_login(req.author_login)
          unless user
            return Twirp::Error.not_found("User not found.", argument: "author_login", value: req.author_login.to_s)
          end

          reviewers = req.reviewers.map do |reviewer|
            find_mannequin_or_user_by_login(reviewer)
          end

          assignee_map = build_user_map(req.assignees.to_a)

          return already_exists_error_handler("PullRequest") if already_exists?(req.number, repository.id)

          # Fix issue where head ref comes from a forked repository. We have the commits but we don't have the ref
          # so create it on the target repo
          if create_fork_head_ref?(req, repository)
            repository.heads.create(req.head_ref_name, req.head_ref_commit_sha, user)
          end

          pull_request = ImportablePullRequest.build_pull_request(
            repository: repository,
            user: user,
            base_ref: req.base_ref_name,
            head_ref: req.head_ref_name,
            base_sha: req.base_ref_commit_sha,
            head_sha: req.head_ref_commit_sha,
            created_at: req.created_at.to_time,
            merged_at: req.merged_at&.to_time,
            closed_at: req.closed_at&.to_time,
            draft: req.is_draft,
            status: req.closed_at&.present? ? "closed" : "open",
            issue_attributes: {
              title: req.title,
              body: req.body,
              number: req.number
            },
          )

          pull_request.merge_commit_sha = req.merge_commit_sha.presence

          rate_limited_mode(pull_request) do
            unless pull_request.save
              return save_model_error_handler(pull_request)
            end
          end

          reviewers.each do |reviewer|
            ImportableReviewRequest.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, skip_reporting: true) do
              ActiveRecord::Base.connected_to(role: :writing) do
                review_request = ImportableReviewRequest.new(
                  pull_request:  pull_request,
                  reviewer:      reviewer
                  )

                unless review_request.save
                  # TODO: return review_request validation errors https://github.com/github/octoshift/issues/6629
                  next
                end
              end
            end
          end

          req.assignees&.each do |assignee_login|
            assignee = assignee_map[assignee_login]
            unless assignee
              # TODO: return assignee validation errors https://github.com/github/octoshift/issues/6629
              next
            end

            Assignment.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, skip_reporting: true) do
              ActiveRecord::Base.connected_to(role: :writing) do
                assignment = Assignment.new({
                  issue: pull_request.issue,
                  assignee: assignee,
                  skip_trigger_assigned_event: true,
                  skip_ensure_assignee_is_a_collaborator: true
                })
                unless assignment.save
                  # TODO: return assignee validation errors https://github.com/github/octoshift/issues/6629
                  next
                end
              end
            end
          end

          {
            pull_request: build_pull_request_hash(pull_request)
          }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def build_pull_request_hash(pull_request)
          {
            id: pull_request.id,
            issue_id: pull_request.issue.id,
            issue_number: pull_request.issue.number
          }
        end

        def create_fork_head_ref?(req, repository)
          return unless GitHub.flipper[:octoshift_create_head_from_pr_forks].enabled?(repository.owner)

          # Only create the head ref for fork PR if the PR originates from fork and if the PR is not closed and not merged
          req.originates_from_fork.present? && req.closed_at.blank? && req.merged_at.blank?
        end

        # Private: Checks if a ref name is invalid.
        # Checks to see if ref_name includes a ":" or "refs/head" prefix.
        #
        # Returns bool.
        def ref_name_invalid?(ref_name)
          ref_name.include?(":") || ref_name.starts_with?("refs/head")
        end

        def already_exists?(number, repository_id)
          replica(Issue).query do |klass|
            klass.where(number: number, repository_id: repository_id).exists?
          end
        end

        def validate_refs(req, repository)
          base_ref_name = req.base_ref_name
          head_ref_name = req.head_ref_name
          base_ref_commit_sha = req.base_ref_commit_sha
          head_ref_commit_sha = req.head_ref_commit_sha

          # Validate ref args
          if base_ref_name.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "base_ref_name")
          end
          if head_ref_name.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "head_ref_name")
          end
          if base_ref_commit_sha.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "base_ref_commit_sha")
          end
          if head_ref_commit_sha.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "head_ref_commit_sha")
          end
          if ref_name_invalid?(base_ref_name)
            return Twirp::Error.invalid_argument("should contain the branch name only, without a repository owner scope.", argument: "base_ref_name")
          end
          if ref_name_invalid?(head_ref_name)
            return Twirp::Error.invalid_argument("should contain the branch name only, without a repository owner scope.", argument: "head_ref_name")
          end

          if check_for_missing_refs?
            if check_both_refs_missing?(repository)
              Twirp::Error.not_found("Base and head refs not found and commit data is missing",
                octoshift_error_code: "REF_NOT_FOUND"
              ) if ref_missing?(base_ref_name, base_ref_commit_sha, repository) && ref_missing?(head_ref_name, head_ref_commit_sha, repository)
            else
              # Base ref might be missing if the default branch was changed (e.g, master -> main) and the old branch was deleted.
              return build_missing_ref_error(base_ref_name, base_ref_commit_sha, "Base", "base_ref_name") if ref_missing?(base_ref_name, base_ref_commit_sha, repository)

              # Head ref might be missing due to deleted branch on close/merging of PR. Check for existance of commit object in repo instead
              build_missing_ref_error(head_ref_name, head_ref_name, "Head", "head_ref_name") if ref_missing?(head_ref_name, head_ref_commit_sha, repository)
            end
          end
        end

        def build_missing_ref_error(ref_name, ref_commit_sha, ref_type, ref_arg)
          Twirp::Error.not_found("#{ref_type} ref not found and commit data is missing",
            argument: ref_arg,
            value: ref_name,
            octoshift_error_code: "REF_NOT_FOUND"
          )
        end

        def check_for_missing_refs?
          GitHub.flipper[:octoshift_check_missing_refs_in_prs].enabled?
        end

        def check_both_refs_missing?(repo)
          GitHub.flipper[:octoshift_check_missing_head_and_base_refs_in_prs].enabled?
        end

        def ref_missing?(ref_name, ref_commit_sha, repository)
          repository.heads.exclude?(ref_name) && !repository.rpc.object_exists?(ref_commit_sha, "commit")
        end
      end
    end
  end
end
