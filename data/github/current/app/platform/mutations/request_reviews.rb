# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RequestReviews < Platform::Mutations::Base
      description "Set review requests on a pull request."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "The Node ID of the pull request to modify.", required: true, loads: Objects::PullRequest, as: :pull
      argument :user_ids, [ID], "The Node IDs of the user to request.", required: false, loads: Objects::User
      argument :team_ids, [ID], "The Node IDs of the team to request.", required: false, loads: Objects::Team
      argument :union, Boolean, "Add users to the set rather than replace.", required: false, default_value: false
      argument :re_request, Boolean, "Whether or not the request is a re-request", required: false, default_value: false, visibility: :internal

      field :requested_reviewers_edge, Edges::User, "The edge from the pull request to the requested reviewers.", null: true

      field :pull_request, Objects::PullRequest, "The pull request that is getting requests.", null: true
      field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull:, **inputs)
        permission.async_repo_and_org_owner(pull).then do |repo, org|
          permission.access_allowed?(:request_pull_request_review, repo: repo, resource: pull, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(pull:, **inputs)
        reviewers = Array.wrap(inputs[:users]) + Array.wrap(inputs[:teams])

        unless pull.request_review_from(reviewers: reviewers, actor: context[:viewer], re_request: inputs[:re_request], append: inputs[:union])
          raise Errors::Unprocessable.new("Could not add requested reviewers to pull request.")
        end

        reviewers_relation = Platform::LoaderTracker.ignore_association_loads do
          pull.review_requests.pending.scoped
        end

        reviewers_connection = Platform::ConnectionWrappers::Relation.new(reviewers_relation, context: context)

        {
          requested_reviewers_edge: GraphQL::Pagination::Connection::Edge.new(pull, reviewers_connection),
          pull_request: pull,
          actor: context[:viewer],
        }
      end
    end
  end
end
