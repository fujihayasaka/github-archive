# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    # This file is deliberately not named WorkflowFile because it has very specific context: It surfaces what
    # a user can see about a workflow file that was executed as part of a workflow run. It is an important
    # difference because the user might *not* actually have read access to the repository which owns the workflow.
    # This could be the case for cross-repo required workflows. There is still some information a user could see even
    # if they do not have read access to the repository which holds the workflow file. That is what this object
    # is meant for.
    class WorkflowRunFile < Platform::Objects::Base
      extend T::Sig

      implements Interfaces::UniformResourceLocatable

      description "An executed workflow file for a workflow run."

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:wfrf, :id],
      ], as: "WFRF", ready_date: "1970-01-01" do |workflow_run_file|
        # `created_at` is delegated to the workflow run which further delegates to the underlying check suite:
        workflow_run_file.async_check_suite.then do
          {
            prefix: :wfrf,
            id: workflow_run_file.id,
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      sig do
        params(
          permission: Authorization::Permission,
          workflow_run_file: Models::WorkflowRunFile
        ).returns(Promise[T::Boolean])
      end
      def self.async_api_can_access?(permission, workflow_run_file)
        # In this context we are only checking against the repository that the workflow run was executed against.
        workflow_run_file.async_check_suite.then do |check_suite|
          permission.async_repo_and_org_owner(check_suite).then do |repo, org|
            permission.access_allowed?(
              :read_actions,
              resource: repo,
              current_repo: repo,
              current_org: org,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      sig do
        params(
          permission: Authorization::Permission,
          workflow_run_file: Models::WorkflowRunFile
        ).returns(Promise[T::Boolean])
      end
      def self.async_viewer_can_see?(permission, workflow_run_file)
        # In this context we are only checking against the repository that the workflow run was executed against.
        workflow_run_file.async_check_suite.then do |check_suite|
          permission.load_repo_and_owner(check_suite).then do |repo|
            repo.resources.actions.async_readable_by?(permission.viewer)
          end
        end
      end

      # Support new prefixed ID's, such as: WFRF_a1b2b3
      sig { params(parsed_id: Platform::Helpers::GlobalId::Next).returns(Promise[T.nilable(Models::WorkflowRunFile)]) }
      def self.load_from_next_global_id(parsed_id)
        load_from_global_id(parsed_id.id)
      end

      # Resolves an instance based on global ID.  Supports string for legacy global IDs and integer for
      # next global IDs.
      sig { params(id: T.any(Integer, String)).returns(Promise[T.nilable(Models::WorkflowRunFile)]) }
      def self.load_from_global_id(id)
        Platform::Loaders::ActiveRecord.load(::Actions::WorkflowRun, id.to_i).then do |workflow_run|
          Models::WorkflowRunFile.wrap(workflow_run)
        end
      end

      # Resolves an instance based on URL
      sig { params(params: T::Hash[Symbol, String]).returns(Promise[T.nilable(Models::WorkflowRunFile)]) }
      def self.load_from_params(params)
        Objects::Repository.load_from_params(params).then do |repository|
          # Nothing we can do if we can't find the repository in the URL
          next unless repository

          workflow_run = Actions::WorkflowRun.find_by(repository: repository, id: params[:workflow_run_id])

          Models::WorkflowRunFile.wrap(workflow_run)
        end
      end

      # The indirectly accessible web-page where a user could see a workflow (even if it is cross-repo)
      # such as: https://github.com/[repo_owner]/[repo_name]/actions/runs/[workflow_run_database_id]/workflow
      url_fields description: "The HTTP URL for this workflow run file"

      # The parent workflow run for which this workflow file belongs to.  There should never
      # be a case of a null workflow run.  If that is the case then this object should not be accessible.
      field :run,
        Objects::WorkflowRun,
        "The parent workflow run execution for this file.",
        null: false,
        method: :workflow_run

      # The URL pointing directly to where the actual workflow file resides within the owning repository.
      # The could return a blank string if the owning repository cannot be found.
      field :repository_name,
        Scalars::URI,
        description: "The repository name and owner which stores the workflow file.",
        null: false,
        method: :async_repository_name

      # The URL pointing directly to where the actual workflow file resides within the owning repository.
      # The could return a blank string if the owning repository cannot be found.
      field :repository_file_url,
        Scalars::URI,
        description: "The direct link to the file in the repository which stores the workflow file.",
        null: false,
        method: :async_repository_file_url

      # The relative path without the repo owner with name (exactly as stored as WorkflowRun#workflow_file_path).
      # This can never be null as it must be present for a WorkflowRunFile object to exist.
      field :path, String, description: "The path of the workflow file relative to its repository.", null: false

      # This is for the #repository_file_url which is the direct link to the file in the repository which stores it.
      field :viewer_can_read_repository,
        Boolean,
        description: "If the viewer has permissions to read the repository which stores the workflow.",
        null: false

      sig { returns(Promise[T::Boolean]) }
      def viewer_can_read_repository
        object.async_can_read_repository?(context[:viewer])
      end

      # This is for the #repository_file_url which is the direct link to the file in the repository which stores it.
      field :viewer_can_push_repository,
        Boolean,
        description: "If the viewer has permissions to push to the repository which stores the workflow.",
        null: false

      sig { returns(Promise[T::Boolean]) }
      def viewer_can_push_repository
        object.async_can_push_repository?(context[:viewer])
      end
    end
  end
end
