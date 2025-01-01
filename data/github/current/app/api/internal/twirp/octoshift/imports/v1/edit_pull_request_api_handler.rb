# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditPullRequestAPIService
      class EditPullRequestAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::Attribution
        include Imports::Helpers::ContentCreation
        include Imports::Helpers::LiveMigrations
        include Imports::Helpers::ModelDelay
        include Helpers::ErrorHandler

        STATE_MAP = {
          EDIT_PULL_REQUEST_STATE_OPEN: "open",
          EDIT_PULL_REQUEST_STATE_CLOSED: "closed",
          EDIT_PULL_REQUEST_STATE_MERGED: "merged"
        }.freeze

        REVIEWABLE_STATE_MAP = {
          EDIT_PULL_REQUEST_REVIEWABLE_STATE_DRAFT: "draft",
          EDIT_PULL_REQUEST_REVIEWABLE_STATE_READY_FOR_REVIEW: "ready"
        }.freeze

        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::EditPullRequestAPIService

        # Public: Implementation of the EditPullRequest Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditPullRequestRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::EditPullRequestResponse, or a Twirp::Error.
        def edit_pull_request(req, env)
          check_model_replication_delay!(ImportablePullRequest)

          # Validate args
          err = validate(req.id, req.updated_at, req.closed_at, req.merged_at, req.user_login, req.body&.value, req.state, req.base_ref, req.merge_commit_sha&.value)
          return err if err

          pull_request = replica(ImportablePullRequest).find_by(id: req.id)
          unless pull_request
            return Twirp::Error.not_found("PullRequest '#{req.id}' was not found.")
          end

          unless Repository.active.where(id: pull_request.repository_id).exists?
            return Twirp::Error.not_found("Repository not found.", octoshift_error_code: "REPOSITORY_DELETED")
          end

          # Only update if the incoming updated_at is newer than the latest timestamp on the pull request
          err = check_outdated_updated_at(pull_request, req.updated_at)
          return err if err

          rate_limited_mode(pull_request) do
            edit(pull_request, req.updated_at, req.closed_at, req.merged_at, req.user_login, req.title, req.body&.value, req.assignees, req.state, req.reviewable_state, req.labels, req.base_ref, req.merge_commit_sha&.value)
          end
        rescue Errors::UnableToEditError => error
          error.message
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def validate(id, updated_at, closed_at, merged_at, user_login, body, state, base_ref, merge_commit_sha)
          if id.negative? || id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "id")
          end
          if updated_at.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "updated_at")
          end
          if !body.nil? && user_login.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_login")
          end
          if state == :EDIT_PULL_REQUEST_STATE_CLOSED && closed_at.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "closed_at")
          end
          if state == :EDIT_PULL_REQUEST_STATE_MERGED
            if user_login.blank?
              return Twirp::Error.invalid_argument("must be non-empty", argument: "user_login")
            end
            if merged_at.blank?
              return Twirp::Error.invalid_argument("must be non-empty", argument: "merged_at")
            end
            if base_ref.blank?
              return Twirp::Error.invalid_argument("must be non-empty", argument: "base_ref")
            end
            if merge_commit_sha.nil?
              return Twirp::Error.invalid_argument("must be non-empty", argument: "merge_commit_sha") # rubocop:disable Style/RedundantReturn
            end
          end
        end

        def edit(pull_request, updated_at, closed_at, merged_at, user_login, title, body, assignees, state, reviewable_state, labels, base_ref, merge_commit_sha)
          if title.present? && pull_request.title != title
            pull_request.issue.update(title: title) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
          end

          if !body.nil? && pull_request.body != body
            # Fetch the user who edited the pull request
            user = user_or_ghost(user_login)
            raise Errors::UnableToEditError, Twirp::Error.not_found("User '#{user_login}' was not found.") unless user

            pull_request.issue.update_body(body, user)
          end

          if pull_request.assignees.map(&:login).sort != assignees.sort
            edit_assignees(pull_request, assignees)
          end

          if state != :EDIT_PULL_REQUEST_STATE_MERGED && base_ref.present? && pull_request.base_ref != base_ref
            edit_base_ref(pull_request, base_ref)
          end

          if STATE_MAP.has_key?(state) && pull_request.state != STATE_MAP[state].to_sym
            edit_state(pull_request, STATE_MAP[state], user_login, closed_at, merged_at, base_ref, merge_commit_sha)
          end

          if pull_request.open? && REVIEWABLE_STATE_MAP.has_key?(reviewable_state) && pull_request.reviewable_state != REVIEWABLE_STATE_MAP[reviewable_state]
            begin
              edit_reviewable_state(pull_request, REVIEWABLE_STATE_MAP[reviewable_state])
            rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved, ActiveRecord::Rollback => e
              raise Errors::UnableToEditError, Twirp::Error.canceled("Pull request could not be marked as #{REVIEWABLE_STATE_MAP[reviewable_state]}: #{e.message}")
            end
          end

          if pull_request.labels.map(&:lowercase_name).sort != labels.map { |label| label.downcase }.sort
            edit_labels(pull_request, labels)
          end

          pull_request.update(updated_at: updated_at&.to_time)

          build_pull_request_hash(pull_request)
        end

        def edit_assignees(pull_request, assignees)
          assignee_map = build_user_map(assignees.to_a)

          ActiveRecord::Base.connected_to(role: :writing) do
            pull_request.assignees.each do |assignee|
              next if assignees.include?(assignee.login)

              remove_assignee(pull_request, assignee)
            end

            assignees&.each do |assignee_login|
              assignee = assignee_map[assignee_login]
              next unless assignee

              add_assignee(pull_request, assignee)
            end
          end
        end

        def remove_assignee(pull_request, assignee)
          return unless pull_request.assignees.include?(assignee)

          assignment = Assignment.find_by(issue: pull_request.issue, assignee: assignee)
          return unless assignment

          assignment.destroy # domain-isolation-query-violation:ignore:packages/issues (SELECT)

          pull_request.assignees.reload
        end

        def add_assignee(pull_request, assignee)
          Assignment.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, skip_reporting: true) do
            return if pull_request.assignees.include?(assignee)

            assignment = Assignment.create({
              issue: pull_request.issue,
              assignee: assignee,
              skip_trigger_assigned_event: true,
              skip_ensure_assignee_is_a_collaborator: true
            })
            return unless assignment.save

            pull_request.issue.add_assignees(assignee)
            pull_request.save! # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
          end
        end

        def edit_labels(pull_request, labels)
          pull_request.labels.each do |label|
            next if labels.map { |label| label.downcase }.include?(label.lowercase_name)

            pull_request.labels.delete(label)
          end

          labels.each do |label|
            next if pull_request.labels.find_by_name(label)

            new_label = pull_request.repository.labels.find_by_name(label) || Label.new(repository: pull_request.repository, name: label)
            pull_request.labels << new_label
          end
        end

        def merge(pull_request, user_login, merged_at, base_ref, merge_commit_sha, err)
          # Fetch the user who merged the pull request
          user = user_or_ghost(user_login)

          PullRequest.transaction do
            # The synced git data will include the merge commit from the source, so the target pull request's merge
            # commit should be updated to that SHA
            edit_merge_commit_sha(pull_request, merge_commit_sha)

            # TODO: remove this event creation once timeline event support is added to the ELM crawler
            #       https://github.ghe.com/github/octoshift/issues/10131
            merged_event = pull_request.issue.events.create(actor: user, event: "merged", commit_id: pull_request.merge_commit_sha) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
            merged_event.update(created_at: merged_at.to_time)

            unless pull_request.update(merged_at: merged_at.to_time)
              err += ": merged_at could not be updated"
              raise Errors::UnableToMergeError, err
            end

            unless pull_request.update(status: "closed")
              err += ": status could not be updated"
              raise Errors::UnableToMergeError, err
            end

            # Bypass authzd policy check which fails when closing importable models
            non_importable_pull_request = replica(PullRequest).find_by(id: pull_request.id)
            unless non_importable_pull_request
              err += ": PullRequest '#{pull_request.id}' was not found"
              raise Errors::UnableToMergeError, err
            end
            # This will make the pull request render in the UI as merged
            unless non_importable_pull_request.issue.close(user, attributes: { commit: { id: pull_request.merge_commit_sha } }) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
              raise Errors::UnableToMergeError, err
            end

            unless pull_request.reload.issue.update(closed_at: pull_request.merged_at) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
              err += ": closed_at could not be updated"
              raise Errors::UnableToMergeError, err
            end
          end
        end

        def edit_state(pull_request, state, user_login, closed_at, merged_at, base_ref, merge_commit_sha)
          if pull_request.state == :merged
            return
          end

          err = if state == "open"
            "Pull request could not be opened"
          else
            "Pull request could not be #{state}"
          end

          if state == "merged"
            edit_base_ref(pull_request, base_ref) if pull_request.base_ref != base_ref

            begin
              merge(pull_request, user_login, merged_at, base_ref, merge_commit_sha, err)
            rescue Errors::UnableToMergeError => e
              raise Errors::UnableToEditError, Twirp::Error.canceled(e.message)
            end
          else
            unless pull_request.issue.update(state: state, closed_at: closed_at&.to_time) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
              raise Errors::UnableToEditError, Twirp::Error.canceled(err)
            end
          end
        end

        def edit_reviewable_state(pull_request, reviewable_state)
          PullRequest.transaction do
            pull_request.draft = reviewable_state == "draft"
            pull_request.reviewable_state = reviewable_state.to_sym
            pull_request.save!
          end
        end

        def edit_base_ref(pull_request, base_ref)
          err = "base_ref could not be updated"

          unless pull_request.repository.heads.find(base_ref)
            raise Errors::UnableToEditError, Twirp::Error.canceled("#{err} because branch '#{base_ref}' does not exist")
          end

          unless pull_request.update(base_ref: base_ref)
            raise Errors::UnableToEditError, Twirp::Error.canceled(err)
          end
        end

        def edit_merge_commit_sha(pull_request, merge_commit_sha)
          err = "merge_commit_sha could not be updated"

          unless pull_request.repository.commits.find(merge_commit_sha)
            raise Errors::UnableToMergeError, "#{err} because commit '#{merge_commit_sha}' does not exist"
          end

          unless pull_request.update(merge_commit_sha: merge_commit_sha)
            raise Errors::UnableToMergeError, err
          end
        end

        def build_pull_request_hash(pull_request)
          {
            id: pull_request.id
          }
        end
      end
    end
  end
end
