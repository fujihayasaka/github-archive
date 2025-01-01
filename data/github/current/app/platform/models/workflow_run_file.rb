# typed: strict
# frozen_string_literal: true

# This class represents an executed workflow file against a repository.  The workflow file might not
# actually reside in the same repo since it could be a required workflow from another repo in the same org but
# we do allow some superficial access to this workflow file information as long as a user has direct access
# to the repo that executed the workflow.  If the user cannot access the owning repo then they can only
# see the immediate workflow contents.
module Platform
  module Models
    class WorkflowRunFile
      include GitHub::Relay::GlobalIdentification
      include UrlHelper
      extend T::Sig

      # This will return an instance of this class if it meets the criteria for being able to handle exposing a file:
      # - the workflow run is not null
      # - the workflow run has a workflow file path
      # - the workflow run is not dynamic
      sig { params(workflow_run: T.nilable(::Actions::WorkflowRun)).returns(T.nilable(Platform::Models::WorkflowRunFile)) }
      def self.wrap(workflow_run)
        if workflow_run && workflow_run.workflow_file_path? && !workflow_run.dynamic_workflow?
          new(workflow_run)
        else # this else block could be omitted, but let's keep it and be explicit in our intentions here.
          nil
        end
      end

      sig { returns(::Actions::WorkflowRun) }
      attr_reader :workflow_run

      # Law of Demeter: try to ensure the surface area of this object is enough for direct consumers.
      # Instead of workflow_run_file.workflow_run.async_check_suite, provide: workflow_run_file.async_check_suite
      # The methods: #async_check_suite, #created_at, and #id are all used for authorization and ID generation.
      delegate :async_check_suite, :created_at, :id, to: :workflow_run

      sig { params(workflow_run: ::Actions::WorkflowRun).void }
      def initialize(workflow_run)
        raise Platform::Errors::Internal, "workflow_run has no file" unless workflow_run.workflow_file_path?
        raise Platform::Errors::Internal, "workflow_run is dynamic"  if workflow_run.dynamic_workflow?

        @workflow_run = workflow_run
      end

      sig { returns(String) }
      def platform_type_name
        "WorkflowRunFile"
      end

      # Name with display owner to help determine if this is a cross-repo workflow.
      sig { returns(Promise[String]) }
      def async_repository_name
        async_owning_repository.then do |owning_repo|
          # There is nothing we can do here if we cant find the repo which owns the workflow so return a blank string.
          next "" unless owning_repo

          owning_repo.name_with_display_owner
        end
      end

      # This may or may not be user-accessible but dotcom currently allows users who cannot access it to at least
      # see the URL.  Since the workflow was cross-repo required by an admin, this might be useful for other users
      # to help understand what is occurring on the immediate repository that the workflow is being run on.  We
      # expose this in dotcom but if the user clicks it then are met with a 404.
      sig { returns(Promise[String]) }
      def async_repository_file_url
        async_owning_repository.then do |owning_repo|
          # There is nothing we can do here either if we cant find the repo which owns the workflow so return a
          # blank string.
          next "" unless owning_repo

          path = blob_path(workflow_run.workflow_file_path, checkout_sha, owning_repo)

          "#{GitHub.url}#{path}"
        end
      end

      # The same URL that is user-accessible via dotcom.
      sig { returns(Promise[String]) }
      def async_url
        Promise.resolve("#{workflow_run.permalink}/workflow")
      end

      # The repository-relative path pointing to the workflow file.
      sig { returns(String) }
      def path
        workflow_run.workflow_file_path
      end

      # Look ahead to see if the user would be able to read the link provided by #repository_file_url.
      # Note that the Workflow Run UI currently exposes this to user independent of their underlying repo
      # read access so this method is a companion to determine if that link should be clickable.
      sig { params(user: User).returns(Promise[T::Boolean]) }
      def async_can_read_repository?(user)
        async_owning_repository.then do |owning_repo|
          # Nothing we can do if we cannot find the owning repository.
          next false unless owning_repo

          owning_repo.async_visible_and_readable_by?(user)
        end
      end

      sig { params(user: User).returns(Promise[T::Boolean]) }
      def async_can_push_repository?(user)
        async_owning_repository.then do |owning_repo|
          # Nothing we can do if we cannot find the owning repository.
          next false unless owning_repo

          owning_repo.async_pushable_by?(user)
        end
      end

      private

      # This will allow us to access the underlying repository that holds the workflow file.
      # We will _only_ access the imposer repo to surface very shallow information that matches the current
      # dotcom experience but we will not give the user any more than what is provided through this class.
      #
      # Alot of methods here are dependent on this method and its resolution so lets memoize it to ensure it only
      # needs to be executed/loaded once.
      sig { returns(Promise[T.nilable(::Repository)]) }
      def async_owning_repository
        if workflow_run.required_workflow_run?
          # WARNING: Always be careful when side-stepping the normal security checks.  We are only allowing this
          # to gather already exposed information via the workflow run file page, such as:
          # https://github.com/foo-org/bar-actions/actions/runs/1337/workflow
          Platform::Loaders::ActiveRecord.load(
            ::Repository,
            workflow_run.imposer_repository_id,
            security_violation_behaviour: :allow
          )
        else
          # The workflow resides in the repo the workflow run was executed against.
          workflow_run.async_repository
        end
      end

      sig { returns(T.nilable(String)) }
      def checkout_sha
        workflow_run.required_workflow_run? ? workflow_run.workflow_file_checkout_sha : workflow_run.head_sha
      end
    end
  end
end
