# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DeploymentReview < Platform::Objects::Base
      description "A deployment review."
      model_name "GateApprovalLog"

      implements_node templates: [[:rdr, :repo_id, :deployment_review_id]], as: "DR", ready_date: Platform::Helpers::GlobalId::COHORT_3 do |deployment_review|
        {
          prefix: :rdr,
          repo_id: deployment_review.repository_id,
          deployment_review_id: deployment_review.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, approval_log)
        permission.async_repo_and_org_owner(approval_log).then do |repo, org|
          permission.access_allowed?(:read_actions, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, approval_log)
        permission.load_repo_and_owner(approval_log).then do |repo|
          repo.resources.actions.async_readable_by?(permission.viewer)
        end
      end

      scopeless_tokens_as_minimum

      database_id_field

      field :user, Objects::User, description: "The user that reviewed the deployment.", null: false

      def user
        @object.async_user.then do |user|
          user || ::User.ghost
        end
      end

      field :comment, String, description: "The comment the user left.", null: false

      field :state, Enums::DeploymentReviewState, description: "The decision of the user.", null: false

      field :environments, Connections.define(Objects::Environment), description: "The environments approved or rejected", connection: true, null: false

      def environments
        @object.async_gate_approvals.then do |gate_approvals|
          Promise.all(gate_approvals.map(&:async_environment)).then do |environments|
            ArrayWrapper.new(environments)
          end
        end
      end

      def self.load_from_next_global_id(parsed_id)
        Promise.resolve(::GateApprovalLog.find(parsed_id.parts[:deployment_review_id]))
      end
    end
  end
end
