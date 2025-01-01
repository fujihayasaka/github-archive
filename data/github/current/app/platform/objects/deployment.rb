# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Deployment < Platform::Objects::Base
      description "Represents triggered deployment instance."

      implements_node templates: [[:rde, :repo_id, :deployment_id]], as: "DE", ready_date: "2021-07-02" do |deployment|
        {
          prefix: :rde,
          repo_id: deployment.repository_id,
          deployment_id: deployment.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, deployment)
        permission.async_repo_and_org_owner(deployment).then do |repo, org|
          permission.access_allowed?(:read_deployment, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, deployment)
        permission.belongs_to_repository(deployment)
      end

      scopeless_tokens_as_minimum

      implements Interfaces::PerformableViaApp
      implements Interfaces::Trigger

      database_id_field

      field :description, String, description: "The deployment description.", null: true

      field :payload, String, description: "Extra information that a deployment system might need.", null: true

      def payload
        payload = @object.payload
        GitHub::JSON.encode(payload) if payload
      end

      field :creator, Interfaces::Actor, "Identifies the actor who triggered the deployment.", null: false
      def creator
        @object.async_creator.then do |creator|
          creator || ::User.ghost
        end
      end

      field :environment, String, "The latest environment to which this deployment was made.", null: true
      def environment
        @object.latest_environment
      end

      # Align with the REST API
      field :original_environment, String, "The original environment to which this deployment was made.", null: true
      def original_environment
        @object.environment
      end

      field :latest_environment, String, "The latest environment to which this deployment was made.", null: true

      field :task, String, "The deployment task.", null: true

      field :is_transient_environment, Boolean, "Check if the deployment environment temporary.", method: :transient_environment, visibility: :internal, null: false

      field :is_production_environment, Boolean, "Whether or not the deployment is to a production environment.", method: :production_environment, visibility: :internal, null: false

      field :repository, Repository, method: :async_repository, description: "Identifies the repository associated with the deployment.", null: false

      created_at_field
      updated_at_field

      field :commit, Objects::Commit, description: "Identifies the commit sha of the deployment.", null: true

      def commit
        @object.async_repository.then do |repository|
          Loaders::GitObject.load(repository, @object.sha, expected_type: :commit)
        end
      end

      field :commit_oid, String, "Identifies the oid of the deployment commit, even if the commit has been deleted.", method: :sha, null: false

      field :ref, Ref, description: "Identifies the Ref of the deployment, if the deployment was created by ref.", null: true

      def ref
        @object.async_repository.then do |repository|
          repository.async_network.then do
            repository.refs.find(@object.ref)
          end
        end
      end

      field :ref_name, String, description: "The ref name of the deployment, if the deployment was created by ref.", null: true, visibility: :internal

      def ref_name
        @object.ref.force_encoding("utf-8")
      end

      field :statuses, Connections.define(Objects::DeploymentStatus), description: "A list of statuses associated with the deployment.", null: true, connection: true

      def statuses
        @object.statuses.scoped
      end

      field :latest_status, DeploymentStatus, "The latest status of this deployment.", null: true,
        method: :async_latest_status

      field :state, Enums::DeploymentState, "The current state of the deployment.", null: true, method: :async_state

      field :deployment_dashboard_environment_channel, String, "The websocket channel for this deployment's environment on the deployment dashboard.", visibility: :internal, null: false, method: :dashboard_channel

      field :check_run, Objects::CheckRun, description: "Identifies the check run associated with the deployment. This is only set internally by GitHub Actions.", method: :async_check_run, null: true, visibility: :internal
    end
  end
end
