# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class JobStatus < Platform::Objects::Base
      description "The status of a background job."

      def self.async_api_can_access?(permission, object)
        repo_db_id = Platform::Helpers::NodeIdentification.from_global_id(object.parent_global_relay_id)[1].to_i
        Platform::Loaders::ActiveRecord.load(::Repository, repo_db_id, security_violation_behaviour: :nil).then do |repo|
          T.must(repo).async_organization.then do |org|
            permission.access_allowed?(:v4_get_repo, repo: repo, current_org: org, resource: repo, from_invitation: false, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def self.async_viewer_can_see?(permission, object)
        object.user_id == permission.viewer.id
      end

      visibility :internal

      field :job_id, ID, description: "The ID of the job.", null: true
      field :updated_at, Scalars::DateTime, description: "The time the job status was last updated.", null: false
      field :job_status_id, ID, description: "The ID of the job status object in the KV store.", null: false
      # not all jobs report percent complete
      field :percentage, Integer, description: "The percentage of the job that is complete.", null: true

      field :state, Enums::JobStates, description: "The state of the job.", null: false
      field :execution_errors, [Platform::Objects::JobError], description: "The errors of the job which occured during run time.", null: false

      # object is a JobStatusSubscription
      def job_status_id
        object.id
      end

      def percentage
        object.respond_to?(:percentage) ? object.percentage : nil
      end
    end
  end
end
