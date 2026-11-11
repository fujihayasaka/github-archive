# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateDeployment < Platform::Mutations::Base
      description "Creates a new deployment event."

      minimum_accepted_scopes ["repo_deployment"]

      # Required arguments
      argument :repository_id, ID, "The node ID of the repository.", required: true, loads: Objects::Repository
      argument :ref_id, ID, "The node ID of the ref to be deployed.", required: true, loads: Objects::Ref

      # Non-required arguments
      argument :auto_merge, Boolean, "Attempt to automatically merge the default branch into the requested ref, defaults to true.", required: false, default_value: true
      argument :required_contexts, [String], "The status contexts to verify against commit status checks. To bypass required contexts, pass an empty array. Defaults to all unique contexts.", required: false
      argument :description, String, "Short description of the deployment.", required: false, default_value: ""
      argument :environment, String, "Name for the target deployment environment.", required: false, default_value: "production"
      argument :task, String, "Specifies a task to execute.", required: false, default_value: "deploy"
      argument :payload, String, "JSON payload with extra information about the deployment.", required: false, default_value: "{}"

      error_fields

      field :deployment, Objects::Deployment, "The new deployment.", null: true
      field :auto_merged, Boolean, "True if the default branch has been auto-merged into the deployment ref.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed? :write_deployment,
            resource: repository,
            current_repo: repository,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
        end
      end

      def resolve(ref:, repository:, execution_errors:, **inputs)

        context[:permission].authorize_content(:deployment, :create, repository: repository)

        deployment = repository.deployments.build

        deployment.creator           = context[:viewer]
        deployment.ref               = ref.ref
        deployment.sha               = ref.sha
        deployment.auto_merge        = inputs[:auto_merge]
        deployment.required_contexts = inputs[:required_contexts]
        deployment.description       = inputs[:description]
        deployment.environment       = inputs[:environment]
        deployment.task              = inputs[:task]
        deployment.payload           = inputs[:payload]

        if context[:permission].integration_user_request?
          deployment.performed_via_integration = context[:integration]
        end

        if deployment.auto_merge?
          message = "Auto-merged #{repository.default_branch} into #{deployment.ref} on deployment."
          options = {
            reflog_data: reflog_data("auto-merge deployment api", repository),
            commit_message: message,
          }

          if deployment.merge_for(context[:viewer], options)
            {
              deployment: nil,
              auto_merged: true,
              errors: [],
            }
          else
            message = "Conflict merging #{repository.default_branch} into #{deployment.ref}."

            Platform::UserErrors.append_legacy_mutation_error_messages_to_context([message], execution_errors)

            {
              deployment: nil,
              auto_merged: false,
              errors: [{
                message: message,
                short_message: message,
                attribute: "auto_merge",
              }],
            }
          end
        elsif deployment.failed_commit_statuses?
          message = "Commit status checks failed for #{ref}."

          Platform::UserErrors.append_legacy_mutation_error_messages_to_context([message], execution_errors)

          {
            deployment: nil,
            auto_merged: false,
            errors: [{
              message: message,
              short_message: message,
              attribute: "required_contexts",
            }],
          }
        else
          if deployment.save
            {
              deployment: deployment,
              auto_merged: false,
              errors: [],
            }
          else
            Platform::UserErrors.append_legacy_mutation_model_errors_to_context(deployment, execution_errors)
            errors = deployment.errors.map do |error|
              {
                message: "#{error.attribute} #{error.message}",
                short_message: "#{error.attribute} #{error.message}",
                attribute: error.attribute,
              }
            end
            {
              deployment: nil,
              auto_merged: false,
              errors: errors,
            }
          end
        end
      end

      def reflog_data(via, repository)
        # disabling linters since reflog isn't visible to customers
        {
          repo_name: repository.name_with_owner, # rubocop:disable GitHub/DoNotAllowNameWithOwner
          repo_public: repository.public?,
          user_login: context[:viewer].login, # rubocop:disable GitHub/DoNotAllowLogin
          user_agent: context[:user_agent],
          from: GitHub.context[:from],
          via: via,
        }
      end
    end
  end
end
