# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::TimelineEventsAPIService
      class TimelineEventsAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::Attribution

        MAX_THROTTLE_RETRIES = 5

        LOCK_REASONS = {
          OFF_TOPIC: "off-topic",
          TOO_HEATED: "too heated",
          RESOLVED: "resolved",
          SPAM: "spam"
        }.freeze

        handles_service MonolithTwirp::Octoshift::Imports::V1::TimelineEventsAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]
        TIMELINE_EVENTS_HAVE_SUBJECT = %w[
          assigned
          unassigned
          review_request_removed
          review_requested
          connected
          disconnected
          referenced
          added_to_project
          removed_from_project
          moved_columns_in_project
          converted_note_to_issue
          marked_as_duplicate
          unmarked_as_duplicate
        ].freeze

        # Public: Implementation of the ImportTimelineEvents Twirp RPC for batching timeline events.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportTimelineEventsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportTimelineEventsResponse, or a Twirp::Error.
        def import_timeline_events(req, env)
          check_model_replication_delay!(ImportableIssueEvent)

          if req.timeline_events.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "timeline_events")
          end

          errors = []

          timeline_events = req.timeline_events.map.with_index do |timeline_event_req, index|
            if timeline_event_req.issue_number.zero?
              errors << { batch_index: index, error_message: "issue_number must be positive integer" }
              next
            end

            if timeline_event_req.repository_id.zero?
              errors << { batch_index: index, error_message: "repository_id must be positive integer" }
              next
            end

            if timeline_event_req.event.empty?
              errors << { batch_index: index, error_message: "event must be non-empty" }
              next
            end

            if timeline_event_req.created_at.blank?
              errors << { batch_index: index, error_message: "created_at must be non-empty" }
              next
            end

            repository = replica(Repository).find_by(id: timeline_event_req.repository_id)
            unless repository && repository.active?
              errors << { batch_index: index, error_message: "Repository '#{timeline_event_req.repository_id}' was not found." }
              next
            end

            cross_repo_ref = timeline_event_req.commit_repository_id.nonzero? && timeline_event_req.commit_repository_id != timeline_event_req.repository_id
            commit_repository = replica(Repository).find_by(id: timeline_event_req.commit_repository_id) if cross_repo_ref

            if cross_repo_ref
              unless commit_repository
                errors << { batch_index: index, error_message: "Referenced repository '#{timeline_event_req.commit_repository_id}' was not found." }
                next
              end
            end

            issue = replica(Issue).find_by(repository: repository, number: timeline_event_req.issue_number)

            unless issue
              errors << { batch_index: index, error_message: "Issue associated with the repository is not found. issue_number: #{timeline_event_req.issue_number}" }
              next
            end

            if timeline_event_req.milestone_title.present?
              milestone = replica(Milestone).find_by(id: timeline_event_req.milestone_id)

              # some older milestones might not have ids, so we fall back on looking up the title
              milestone ||= replica(Milestone).find_by(repository: repository, title: timeline_event_req.milestone_title)
            end

            unless timeline_event_req.referencing_issue_number.zero?

              referencing_issue = replica(Issue).find_by(repository: repository, number: timeline_event_req.referencing_issue_number)

              unless referencing_issue
                errors << { batch_index: index, error_message: "Referencing issue not found. referencing_issue_number: #{timeline_event_req.referencing_issue_number}" }
                next
              end
            end

            # The actor is present when using the GitHub Archive source adapter in Octoshift. Otherwise,
            # in the GitHub Api adapter, actor will always be empty.
            if timeline_event_req.actor.present?
              # Octoshift GitHub Archive source adapter path
              if timeline_event_req.actor.empty?
                errors << { batch_index: index, error_message: "actor must be non-empty" }
                next
              end

              actor = find_mannequin_or_user_by_login(timeline_event_req.actor)
              unless actor
                errors << { batch_index: index, error_message: "User not found. actor: #{timeline_event_req.actor}" }
                next
              end

              subject = map_subject_to_object(timeline_event_req.subject, timeline_event_req.event, issue, repository)
              if timeline_event_req.subject.present? && subject.nil?
                errors << { batch_index: index, error_message: "Subject not found. subject: #{timeline_event_req.subject}" }
                next
              end
            else
              # Octoshift GitHub Api source adapter path
              if timeline_event_req.user_login.empty?
                errors << { batch_index: index, error_message: "user_login must be non-empty" }
                next
              end

              user = find_mannequin_or_user_by_login(timeline_event_req.user_login)
              unless user
                errors << { batch_index: index, error_message: "User not found. user_login: #{timeline_event_req.user_login}" }
                next
              end

              if timeline_event_req.assignee_login.present?
                assignee = find_mannequin_or_user_by_login(timeline_event_req.assignee_login)
                unless assignee
                  errors << { batch_index: index, error_message: "User not found. assignee_login: #{timeline_event_req.assignee_login}" }
                  next
                end
              end

              if timeline_event_req.review_requester_login.present?
                review_requester = find_mannequin_or_user_by_login(timeline_event_req.review_requester_login)
                unless review_requester
                  errors << { batch_index: index, error_message: "User not found. review_requester_login: #{timeline_event_req.review_requester_login}" }
                  next
                end
              end

              if timeline_event_req.requested_reviewer_login.present?
                requested_reviewer = find_mannequin_or_user_by_login(timeline_event_req.requested_reviewer_login)
                unless requested_reviewer
                  errors << { batch_index: index, error_message: "User not found. requested_reviewer_login: #{timeline_event_req.requested_reviewer_login}" }
                  next
                end
              end

              actor = map_actor_and_subject_for_event_attributes(
                user,
                assignee,
                review_requester,
                requested_reviewer,
                timeline_event_req.event,
                issue,
                repository,
                timeline_event_req.subject_number
              ).first
              subject = map_actor_and_subject_for_event_attributes(
                user,
                assignee,
                review_requester,
                requested_reviewer,
                timeline_event_req.event,
                issue,
                repository,
                timeline_event_req.subject_number
              ).last
            end

            # use of master to avoid replication lag on this read
            next if already_exists?(timeline_event_req, issue, actor, subject)

            delete_commit_event_if_already_exists(timeline_event_req, issue) if timeline_event_req.commit_id.present?

            ## Build timeline event model
            timeline_event = ImportableIssueEvent.new do |issue_event|
              issue_event.event = timeline_event_req.event
              issue_event.repository = repository
              issue_event.actor = actor
              issue_event.issue = issue
              issue_event.created_at = timeline_event_req.created_at.to_time

              if valid_commit?(timeline_event_req)
                if cross_repo_ref
                  # Cross-repository reference
                  issue_event.commit_repository = commit_repository
                else
                  issue_event.commit_repository = repository
                end
              end

              if timeline_event_req.label_name.present?
                label = replica(Label).find_by(repository: repository, name: timeline_event_req.label_name)
                if label
                  issue_event.label = label
                else
                  issue_event.label_name = timeline_event_req.label_name
                end
              end

              issue_event.title_is = timeline_event_req.title_is if timeline_event_req.title_is.present?
              issue_event.title_was = timeline_event_req.title_was if timeline_event_req.title_was.present?
              issue_event.subject = subject if TIMELINE_EVENTS_HAVE_SUBJECT.include?(timeline_event_req.event)
              issue_event.commit_id = timeline_event_req.commit_id if timeline_event_req.commit_id.present?
              issue_event.before_commit_oid = timeline_event_req.before_commit_oid if timeline_event_req.before_commit_oid.present?
              issue_event.after_commit_oid = timeline_event_req.after_commit_oid if timeline_event_req.after_commit_oid.present?
              issue_event.ref = timeline_event_req.ref if timeline_event_req.ref.present?
              issue_event.column_name = timeline_event_req.column_name if timeline_event_req.column_name.present?
              issue_event.previous_column_name = timeline_event_req.previous_column_name if timeline_event_req.previous_column_name.present?

              if timeline_event_req.milestone_title.present?
                issue_event.milestone_title = timeline_event_req.milestone_title
                issue_event.milestone_id = milestone.id if milestone.present?
              end

              issue_event.lock_reason = LOCK_REASONS[timeline_event_req.lock_reason.to_sym] if timeline_event_req.lock_reason.present?
              issue_event.referencing_issue = referencing_issue unless timeline_event_req.referencing_issue_number.zero?
            end

            unless timeline_event.valid?
              errors << { batch_index: index, error_message: "Timeline event failed validation. error: #{timeline_event.errors.full_messages.join(", ")}" }
              next
            end

            timeline_event
          end.compact

          timeline_events.each.with_index do |event, index|
            IssueEvent.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, skip_reporting: true) do
              ActiveRecord::Base.connected_to(role: :writing) do
                errors << { batch_index: index, error_message: "Timeline event failed validation. error: #{event.errors.full_messages.join(", ")}" } unless event.save
              rescue ActiveRecord::ActiveRecordError => e
                GitHub.logger.error(
                  exception: e,
                  "gh.repo.id": event.repository.id,
                  "gh.migration_tools.event.issue_number": event.issue.number,
                  "gh.migration_tools.event.batch_index": index,
                  "code.namespace": self.class
                )

                errors << { batch_index: index, error_message: "Timeline event failed creation. error: #{e.class}" }
              end
            end
          end if timeline_events.any?

          { batch_validation_errors: errors }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def valid_commit?(req)
          req.commit_id.present? || req.commit_repository_id.present? || req.before_commit_oid.present? || req.after_commit_oid.present?
        end

        def map_actor_and_subject_for_event_attributes(user, assignee, review_requester, requested_reviewer, event, issue, repository, number)
          actor = nil
          subject = nil

          case event
          when "review_requested"
            actor = review_requester
            subject = requested_reviewer
          when "review_request_removed"
            actor = review_requester
            subject = requested_reviewer
          when "labeled"
            actor = user
          when "unlabeled"
            actor = user
          when "assigned"
            actor = assignee
            subject = user
          when "unassigned"
            actor = assignee
            subject = user
          when "renamed"
            actor = user
            subject = issue.pull_request? ? issue.pull_request : issue
          when "connected", "disconnected", "referenced"
            actor = user
            subject = replica(Issue).find_by(repository: repository, number: number)
          else
            actor = user
          end

          [actor, subject]
        end

        def map_subject_to_object(subject, event, issue, repository)
          mapped_subject = nil

          case event
          when "connected", "disconnected", "referenced", "marked_as_duplicate", "unmarked_as_duplicate"
            mapped_subject = replica(Issue).find_by(repository: repository, number: subject)
          when "added_to_project", "removed_from_project", "moved_columns_in_project", "converted_note_to_issue"
            mapped_subject = replica(Project).find_by(owner: repository, number: subject)
          else
            mapped_subject = find_mannequin_or_user_by_login(subject) if subject.present?
          end

          mapped_subject
        end

        def delete_commit_event_if_already_exists(timeline_event_req, issue)
          issue_event_exists = replica(IssueEvent).query do |klass|
            klass.where(issue_id: issue.id, event: timeline_event_req.event, commit_id: timeline_event_req.commit_id).exists?
          end
          if issue_event_exists
            IssueEvent.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, skip_reporting: true) do
              ActiveRecord::Base.connected_to(role: :writing) do
                T.must(IssueEvent.where(issue_id: issue.id, event: timeline_event_req.event, commit_id: timeline_event_req.commit_id).first).delete
              end
            end
          end
        end

        def already_exists?(timeline_event_req, issue, actor, subject)
          # For performance reasons, we are querying on indexes:
          # `actor_id`, `event` and `created_at` compound index for IssueEvents
          # `subject_id` and `subject_type` compound index for IssueEventDetails
          if subject.present?
            subject_type = subject.class.name == "Mannequin" ? "User" : subject.class.name
            replica(IssueEvent).query do |klass|
              klass.where(issue: issue, actor_id: actor.id, event: timeline_event_req.event, created_at: timeline_event_req.created_at.to_time, issue_event_detail: { subject_id: subject.id, subject_type: subject_type }).joins(:issue_event_detail).exists?
            end
          elsif %w[labeled unlabeled].include?(timeline_event_req.event)
            replica(IssueEvent).query do |klass|
              klass.where(issue: issue, actor_id: actor.id, event: timeline_event_req.event, created_at: timeline_event_req.created_at.to_time).joins(:issue_event_detail).pluck(:label_name).include?(timeline_event_req.label_name)
            end
          else
            replica(IssueEvent).query do |klass|
              klass.where(issue: issue, actor_id: actor.id, event: timeline_event_req.event, created_at: timeline_event_req.created_at.to_time).exists?
            end
          end
        end
      end
    end
  end
end
