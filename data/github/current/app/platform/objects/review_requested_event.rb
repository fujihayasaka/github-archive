# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ReviewRequestedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents an 'review_requested' event on a given pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, review_requested_event)
        permission.belongs_to_issue_event(review_requested_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rrre, :repo_id, :issue_id, :review_requested_event_id]
      ], as: "RRE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rrre,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          review_requested_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :pull_request, Objects::PullRequest, description: "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: false

      field :review_request, Objects::ReviewRequest, method: :async_review_request, visibility: :internal, description: "Identifies the review request associated to this event.", null: true

      field :requested_reviewer, Unions::RequestedReviewer, description: "Identifies the reviewer whose review was requested.", null: true

      def requested_reviewer
        @object.async_visible_subject(@context[:permission])
      end

      # NOTE: We do not intend to publish this field. Since `Team` types are protected
      #   from anonymous users and secret `Team`s from non-members and non-org-admins,
      #   we need a way to support our current UI which shows team names for
      #   review requests.
      #
      #   Once we can allow access to `Team`s when the requester only wants the team name,
      #   we can drop this field and just use `requestedReviewer { ... on Team { name } }`.
      field :requested_review_team_name, String, description: "Identifies the name of the team whose review was requested.", visibility: :internal, null: true

      def requested_review_team_name
        @object.async_subject.then do |subject|
          next unless subject&.is_a?(::Team)

          subject.async_organization.then do |org|
            "#{org.name}/#{subject.slug}"
          end
        end
      end

      # NOTE: We do not intend to publish this field. Since `Team` types are protected
      #   from anonymous users and secret `Team`s from non-members and non-org-admins,
      #   we need a way to support our current UI which shows team names for
      #   review requests.
      #
      #   Once we can allow access to `Team`s when the requester only wants the team name,
      #   we can drop this field and just use `reviewRequest { delegatedFromTeam { name } }`.
      field :requested_review_assigned_from_team_name, String, description: "Identifies the name of the team whose review was requested before being assigned to a user.", visibility: :internal, null: true

      def requested_review_assigned_from_team_name
        @object.async_review_request.then do |request|
          next unless request

          request.async_assigned_from_review_request.then do |team_request|
            next unless team_request
            team_request.async_reviewer.then do |team|
              next unless team.is_a?(::Team)

              team.async_organization.then do |org|
                next unless org
                team.to_s
              end
            end
          end
        end
      end
    end
  end
end
