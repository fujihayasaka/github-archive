# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CheckRun < Platform::Objects::Base
      description "A check run."

      implements_node templates: [[:rcr, :repo_id, :check_run_id]], as: "CR", ready_date: Platform::Helpers::GlobalId::COHORT_2 do |check_run|
        {
          prefix: :rcr,
          repo_id: check_run.repository_id,
          check_run_id: check_run.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, check_run)
        permission.async_repo_and_org_owner(check_run).then do |repo, org|
          permission.access_allowed?(:read_check_run, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_check_suite.then do |check_suite|
          permission.typed_can_see?("CheckSuite", check_suite)
        end
      end

      scopeless_tokens_as_minimum

      implements Interfaces::UniformResourceLocatable
      implements Interfaces::RequirableByPullRequest

      url_fields(description: "The HTTP URL for this check run.") { |url| url.async_path_uri }

      database_id_field

      # This is testing out adding a new field which serializes the database ID as a string and communicates it
      # to GraphQL clients as a BigInt.  This should allow clients to deserialize this to something like an Int64
      # instead of something like an Int32.  This is marked as mobile_only just to proof out this concept
      # end-to-end in one use-case for our controllable mobile clients (GitHub iOS and Android).  Once this
      # proves it works for us we can then figure out a more orthogonal way to update all objects that use
      # database_id_field to also expose this new field as well.
      full_database_id_field mobile_only: true

      field :started_at, Scalars::DateTime, description: "Identifies the date and time when the check run was started.", null: true

      field :completed_at, Scalars::DateTime, description: "Identifies the date and time when the check run was completed.", null: true

      # Can sometimes return -1s so keeping this mobile_only for now.
      field :duration, Integer, description: "The time it took to run the check (in seconds).", null: false, mobile_only: true

      field :status, Enums::CheckStatusState, description: "The current status of the check run.", null: false

      field :conclusion, Enums::CheckConclusionState, description: "The conclusion of the check run.", null: true

      field :title, String, description: "A string representing the check run", null: true

      field :summary, String, description: "A string representing the check run's summary", null: true

      def summary
        @object.async_check_suite.then do |check_suite|
          check_suite.async_repository.then do |_repository|
            @object.async_summary.then do |summary|
              summary&.dup&.force_encoding("UTF-8")
            end
          end
        end
      end

      field :text, String, description: "A string representing the check run's text", null: true

      def text
        @object.async_text.then do |text|
          text&.dup&.force_encoding("UTF-8")
        end
      end

      field :details_url, Scalars::URI, description: "The URL from which to find full details of the check run on the integrator's site.", null: true

      def details_url
        Promise.all([
          @object.async_repository,
          @object.async_workflow_job_run,
          @object.async_check_suite,
        ]).then do |_repo, _workflow_job_run, check_suite|
          check_suite.async_github_app.then do |_app|
            @object.details_url
          end
        end
      end

      field :external_id, String, description: "A reference for the check run on the integrator's system.", null: true

      field :creator, Objects::Bot, description: "The GitHub App bot associated with the check run.", null: true, visibility: :internal

      def creator
        @object.async_check_suite.then do |check_suite|
          check_suite.async_github_app.then do |app|
            if app
              app.async_bot
            end
          end
        end
      end

      field :repository, Objects::Repository, "The repository associated with this check run.", method: :async_repository, null: false

      field :name, String, description: "The name of the check for this check run.", null: false

      def name
        @object.visible_name.dup&.force_encoding("UTF-8")
      end

      field :display_name, String, description: "Optional name that will be shown in the UI overwriting the name field.", null: true, visibility: :internal

      field :contextual_name, String, description: "Check run name as shown in the merge box and dropdowns that show the list of contexts (statuses and check runs) which includes the event and check suite names if available.", null: false, visibility: :internal

      field :check_suite, Objects::CheckSuite, description: "The check suite that this run is a part of.", method: :async_check_suite, null: false

      field :permalink, Scalars::URI, description: "The permalink to the check run summary.", null: false

      def permalink
        # TODO: Created dedicated async permalink method to avoid needing to preload any extra data.
        Promise.all([
          @object.async_repository,
          @object.async_workflow_job_run
        ]).then do |_|
          Addressable::URI.parse(@object.permalink(include_host: true))
        end
      end

      field :annotations, Connections.define(Objects::CheckAnnotation), description: "The check run's annotations", null: true, connection: true, numeric_pagination_enabled: true

      def annotations(**arguments)
        @object.annotations.scoped
      end

      field :steps, Connections.define(Objects::CheckStep), description: "The check run's steps", null: true, connection: true do
        argument :number, Int, "Step number", required: false
      end

      def steps(**arguments)
        @object.async_passthrough_steps?.then do |passthrough|
          next @object.get_steps(arguments[:number]) unless passthrough

          @object.async_steps_from_backend.then do |steps|
            if arguments[:number]
              steps = steps.select { |step| step.number == arguments[:number] }
            end

            # (In a rare case) we may optionally fall back to a relation
            if steps.is_a? ActiveRecord::Relation
              steps
            else
              ArrayWrapper.new(steps)
            end
          end
        end
      end

      field :streaming_log, Objects::StreamingLog, description: "Streaming log information for this check-run.", null: true

      def streaming_log
        return nil if object.streaming_log_url.nil?
        { url: object.streaming_log_url }
      end

      field :completed_log, Objects::CompletedLog, "The completed logs for this check run.", null: true

      def completed_log
        return nil if object.completed_log_url.nil?
        { url: object.completed_log_url, lines: object.completed_log_lines }
      end

      field :number, Int, "The topological order of the check run within the check suite.", mobile_only: true, null: true

      field :deployment, Objects::Deployment, description: "The corresponding deployment for this job, if any", method: :async_deployment, null: true

      field :pending_deployment_request, Objects::DeploymentRequest, description: "Information about a pending deployment, if any, in this check run", null: true

      def pending_deployment_request
        return nil unless @object.status == "waiting"

        viewer = @context[:viewer]
        return nil unless viewer.is_a? ::User

        Loaders::DeploymentRequestsByCheckRun.load(viewer, @object.id)
      end

      def is_required(**arguments)
        @object.async_check_suite.then do |check_suite|
          check_suite.async_workflow_run.then do
            # invoke RequirableByPullRequest.is_required with passed args
            super
          end
        end
      end
    end
  end
end
