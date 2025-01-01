# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MarkNotificationSubjectAsRead < Platform::Mutations::Base
      description "Marks a notification as read"
      mobile_only true
      required_capabilities [:access_internal_graphql_notifications]
      minimum_accepted_scopes ["notifications"]

      argument :subject_id, ID, "The id of the notification subject to mark as read.", required: true, loads: Unions::NotificationsSubject

      field :success, Boolean, "Did the operation succeed?", null: true
      field :viewer, Objects::User, "The user that the saved notification belongs to.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, subject:, **inputs)
        case subject
        when ::DiscussionPost
          # The `access_allowed?` call below needs two inputs based on the
          # subject: `current_repo` and `current_org`. `DiscussionPost`s don't
          # have repos, so it's nil here.
          repo_promise = Promise.resolve(nil)
          org_promise = subject.async_team.then(&:async_organization)
        when ::Gist
          # The `access_allowed?` call below needs two inputs based on the
          # subject: `current_repo` and `current_org`. `Gist`s don't
          # have repos or orgs.
          repo_promise = Promise.resolve(nil)
          org_promise = Promise.resolve(nil)
        when ::CheckSuite, ::Issue, ::Commit, ::PullRequest, ::RepositoryVulnerabilityAlert, ::Release, ::RepositoryAdvisory, ::Discussion, ::DiscussionComment, ::Actions::WorkflowRun
          repo_promise = subject.async_repository
          org_promise = repo_promise.then { |r| permission.async_owner_if_org(r) }
        else
          raise Platform::Errors::Internal, "Unexpected subject type: #{Newsies::Thread.to_key(subject)}"
        end

        Promise.all([repo_promise, org_promise]).then do |repo, org|
          permission.access_allowed?(:mark_notification_subject_as_read, current_repo: repo, current_org: org, resource: subject, allow_integrations: false, allow_user_via_granular_actor: false)
        end
      end

      def resolve(subject:, **inputs)
        notification = GitHub.newsies.web.by_thread(context[:viewer], subject.notifications_thread)

        # A notification can be in one of three states read/unread/archived.
        # In the case that the notification is archived we simply noop.
        # Ref: https://github.com/github/project-nova/issues/173
        if notification.present? && !notification[:archived]
          response = GitHub.newsies.web.mark_thread_read(context[:viewer], subject.notifications_thread)

          raise Errors::Unprocessable.new("Unable to mark notification as read.") unless response.success?
        end

        {
          success: true,
          viewer: context[:viewer],
        }
      end
    end
  end
end
