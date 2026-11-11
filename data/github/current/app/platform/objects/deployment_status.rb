# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DeploymentStatus < Platform::Objects::Base
      description "Describes the status of a given deployment attempt."

      implements_node templates: [[:rdes, :repo_id, :deployment_status_id]], as: "DES", ready_date: "2021-07-02" do |deployment_status|
        deployment_status.async_deployment.then do |deployment|
          deployment.async_repository.then do |repository|
            {
              prefix: :rdes,
              repo_id: repository.id,
              deployment_status_id: deployment_status.id
            }
          end
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, deployment_status)
        deployment_status.async_deployment.then do |deployment|
          permission.typed_can_access?("Deployment", deployment)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_deployment.then do |deployment|
          permission.typed_can_see?("Deployment", deployment)
        end
      end

      scopeless_tokens_as_minimum

      implements Interfaces::PerformableViaApp

      field :creator, Interfaces::Actor, "Identifies the actor who triggered the deployment.", null: false
      def creator
        @object.async_creator.then do |creator|
          creator || ::User.ghost
        end
      end

      field :deployment, Deployment, "Identifies the deployment associated with status.", null: false
      field :state, Enums::DeploymentStatusState, "Identifies the current state of the deployment.", null: false
      field :description, String, "Identifies the description of the deployment.", null: true
      field :environment_url, Scalars::URI, "Identifies the environment URL of the deployment.", null: true
      created_at_field
      updated_at_field
      field :environment, String, "Identifies the environment of the deployment at the time of this deployment status", null: true
      field :log_url, Scalars::URI, "Identifies the log URL of the deployment.", null: true, method: :encoded_log_url
    end
  end
end
