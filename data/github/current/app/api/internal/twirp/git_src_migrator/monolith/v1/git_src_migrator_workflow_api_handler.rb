# typed: true
# frozen_string_literal: true

require "monolith-twirp-git_src_migrator-monolith"

module Api::Internal::Twirp::GitSrcMigrator
  module Monolith
    module V1
      # Handles actions workflows for the git-src-migrator app.
      class GitSrcMigratorWorkflowAPIHandler < Api::Internal::Twirp::Handler
        include Api::Internal::Twirp::Octoshift::Imports::V1::Helpers::ContentCreation
        include Api::Internal::Twirp::Octoshift::Imports::V1::Helpers::ModelDelay
        include Api::Internal::Twirp::Octoshift::Imports::V1::Helpers::ErrorHandler


        handles_service MonolithTwirp::GitSrcMigrator::Monolith::V1::GitSrcMigratorWorkflowAPIService
        allow_access_for :client, allowed_clients: ["git_src_migrator"]

        # From https://github.com/github/github/blob/master/packages/checks/app/models/check_run.rb#L72-L79
        CHECK_RUN_STATUSES = {
          "completed" => :STATUS_COMPLETED,
          "in_progress" => :STATUS_IN_PROGRESS,
          "pending" => :STATUS_PENDING,
          "queued" => :STATUS_QUEUED,
          "requested" => :STATUS_REQUESTED,
          "waiting" => :STATUS_WAITING
        }.freeze

        # From https://github.com/github/github/blob/master/packages/checks/app/models/check_suite.rb#L107
        CHECK_SUITE_CONCLUSIONS = {
          nil => :CONCLUSION_NIL,
          "neutral" => :CONCLUSION_NEUTRAL,
          "success" => :CONCLUSION_SUCCESS,
          "failure" => :CONCLUSION_FAILURE,
          "cancelled" => :CONCLUSION_CANCELLED,
          "action_required" => :CONCLUSION_ACTION_REQUIRED,
          "timed_out" => :CONCLUSION_TIMED_OUT,
          "skipped" => :CONCLUSION_SKIPPED,
          "stale" => :CONCLUSION_STALE,
          "startup_failure" => :CONCLUSION_STARTUP_FAILURE
        }.freeze

        WARNING_LEVELS = {
          "warning" => :WARNING_LEVEL_WARNING,
          "failure" => :WARNING_LEVEL_FAILURE,
          "notice" => :WARNING_LEVEL_NOTICE,
        }.freeze

        # Public: Implementation of the GitSrcMigratorWorkflowAPI Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::GitSrcMigrator::Monolith::V1::RunDynamicWorkflowRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::GitSrcMigrator::Monolith::V1::RunDynamicWorkflowResponse, or a Twirp::Error.
        def run_dynamic_workflow(req, env)
          if req.workflow.empty?
            return Twirp::Error.invalid_argument("Must be non-empty", argument: "workflow")
          end

          if req.owner_id.zero?
            return Twirp::Error.invalid_argument("Must be positive integer", argument: "owner_id")
          end

          if req.user_id.zero?
            return Twirp::Error.invalid_argument("Must be positive integer", argument: "user_id")
          end

          if req.repository_name.empty?
            return Twirp::Error.invalid_argument("Must be non-empty", argument: "repository_name")
          end

          if req.workflow_name.empty?
            return Twirp::Error.invalid_argument("Must be non-empty", argument: "workflow_name")
          end

          if req.workflow_slug.empty?
            return Twirp::Error.invalid_argument("Must be non-empty", argument: "workflow_slug")
          end

          workflow_owner = replica(User).find_by(id: req.owner_id)
          unless workflow_owner
            return Twirp::Error.not_found("Owner not found.", argument: "owner_id", value: req.owner_id.to_s)
          end

          workflow_creator = replica(User).find_by(id: req.user_id)
          unless workflow_creator
            return Twirp::Error.not_found("User not found.", argument: "user_id", value: req.user_id.to_s)
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            repo_attributes = {
              visibility: Repository::PRIVATE_VISIBILITY,
              name: req.repository_name,
              import: Import.create!({ creator: workflow_creator })
            }

            result = rate_limited_mode(Repository, throttle: false) do
              Repository.handle_creation(
                workflow_creator,
                workflow_owner.login,
                repo_attributes
              )
            end

            unless result.success?
              error = result.repository.errors.full_messages.join(", ").presence || result.error_message
              return Twirp::Error.canceled(error)
            end

            actions_repository = result.repository

            # ensure actions is enabled
            actions_repository.enable_actions(actor: workflow_owner)

            # Ensure there is an initial commit
            Codespaces::InitializeRepository.call(repository: actions_repository, actor: actions_repository.created_by)

            inputs = req.inputs.to_h do |input|
              [input.name.to_sym, input.value]
            end

            # Add secrets to repository
            req.secrets.each do |workflow_secret|
              create_secret(
                owner: actions_repository,
                actor: workflow_creator,
                name: workflow_secret.name,
                secret: workflow_secret.secret
              )
            end

            result = actions_repository.run_dynamic_workflow(
              actor: actions_repository.owner,
              workflow: req.workflow, # workflow yaml to run
              inputs: inputs,
              ref: "main",
              workflow_name: req.workflow_name, # name to display in the workflow run list
              slug: req.workflow_slug, # identifier used in the url to group workflow runs
              integration_name: "git-src-migrator",
              entry_point: :git_src_migrator_run_dynamic_workflow
            )

            unless result && result.call_succeeded?
              message = result && result.options.has_key?(:message) ? result.options[:message] : "Unknown error occurred."
              return Twirp::Error.unavailable("Unable to launch dynamic workflow run. #{message}")
            end

            {
              workflow_run_id: result.value.workflow_run_id,
              workflow_repository_id: actions_repository.id,
              workflow_repository_url: actions_repository.repository_url(actions_repository)
            }
          end
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Public: Implementation of the GitSrcMigratorWorkflowAPI Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::GitSrcMigrator::Monolith::V1::GetWorkflowStatusRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::GitSrcMigrator::Monolith::V1::GetWorkflowStatusResponse, or a Twirp::Error.
        def get_workflow_status(req, env)
          if req.workflow_run_id.zero?
            return Twirp::Error.invalid_argument("Must be positive integer", argument: "workflow_run_id")
          end

          if req.actions_repository_id.zero?
            return Twirp::Error.invalid_argument("Must be positive integer", argument: "actions_repository_id")
          end

          actions_repository = Repository.find_by(id: req.actions_repository_id)
          unless actions_repository
            return Twirp::Error.not_found("Actions repository not found.", argument: "actions_repository_id", value: req.actions_repository_id.to_s)
          end

          workflow_run = Actions::WorkflowRun.includes(:check_suite).find_by(id: req.workflow_run_id, repository_id: actions_repository.id)
          unless workflow_run
            return Twirp::Error.not_found("Workflow run not found.", argument: "workflow_run_id", value: req.workflow_run_id.to_s)
          end

          workflow_execution = workflow_run.latest_workflow_run_execution
          workflow_run_hash = build_workflow_run_status_hash(workflow_execution)

          annotations_hashes = build_annotations_hashes(workflow_execution)
          workflow_run_hash[:annotations] = annotations_hashes if annotations_hashes.present?

          jobs = workflow_run.latest_jobs
          jobs_hashes = build_jobs_hashes(jobs)
          workflow_run_hash[:jobs] = jobs_hashes

          workflow_run_hash
        end

        # Public: Implementation of ReRunJob Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::GitSrcMigrator::Monolith::V1::ReRunJobRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::GitSrcMigrator::Monolith::V1::ReRunJobResponse, or a Twirp::Error.
        def re_run_job(req, env)
          if req.job_id.zero?
            return Twirp::Error.invalid_argument("Must be positive integer", argument: "job_id")
          end

          check_run = CheckRun.find_by(id: req.job_id)
          unless check_run
            return Twirp::Error.not_found("Check run not found", argument: "job_id", value: req.job_id.to_s)
          end

          repository = check_run.repository
          unless repository
            return Twirp::Error.not_found("Actions repository associated with the job id #{req.job_id} not found")
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            begin
              check_run.actions_rerequest(actor: repository.owner)
              {}
            rescue CheckSuite::ActionsDependency::ExpiredWorkflowRunError
              Twirp::Error.permission_denied("Unable to re-run this job because the workflow run was created over a month ago")
            rescue CheckSuite::AlreadyRerunningError
              Twirp::Error.permission_denied("The workflow run containing this job is already running")
            rescue CheckSuite::DisabledWorkflowError
              Twirp::Error.permission_denied("Unable to re-run this job, disabled workflow")
            rescue CheckSuite::ActionsDependency::PreviousJobAttemptError
              Twirp::Error.permission_denied("Only jobs from the current attempt can be re-run")
            rescue CheckSuite::NotRerequestableError
              Twirp::Error.permission_denied("Jobs in this workflow run cannot be re-run")
            end
          end
        end

        private

        def build_workflow_run_status_hash(workflow_execution)
          {
            workflow_execution_id: workflow_execution.id,
            status: CHECK_RUN_STATUSES[workflow_execution.status],
            conclusion: CHECK_SUITE_CONCLUSIONS[workflow_execution.conclusion],
            workflow_completed_at: Google::Protobuf::Timestamp.new(seconds: workflow_execution.completed_at.to_i)
          }
        end

        def build_jobs_hashes(jobs)
          jobs.map do |job|
            {
              job_id: job.id,
              job_name: job.display_name,
              status: CHECK_RUN_STATUSES[job.status],
              conclusion: CHECK_SUITE_CONCLUSIONS[job.conclusion],
              job_started_at: Google::Protobuf::Timestamp.new(seconds: job.started_at.to_i),
              job_completed_at: Google::Protobuf::Timestamp.new(seconds: job.completed_at.to_i)
            }
          end
        end

        def build_annotations_hashes(workflow_execution)
          annotations = workflow_execution.workflow_job_runs.pluck(:check_run_id).map do |check_run_id|
            check_run = CheckRun.find_by(id: check_run_id)
            return unless check_run
            check_run.annotations.map do |annotation|
              {
                job_name: check_run.display_name,
                message: annotation.message,
                warning_level: WARNING_LEVELS[annotation.warning_level]
              }
            end
          end

          annotations.flatten!
        end

        def create_secret(owner:, actor:, name:, secret:)
          public_key_id, encoded_public_key = Secrets.github_public_key(owner: owner, key_name: Platform::EncryptionKeys::CUSTOM_TASKS)

          # Encrypt the secret as the client would, per https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#create-or-update-a-repository-secret
          public_key = RbNaCl::PublicKey.new(Base64.decode64(encoded_public_key))
          box = RbNaCl::Boxes::Sealed.from_public_key(public_key)
          encrypted_secret = box.encrypt(secret)
          value = Secrets.embed(public_key_id, encrypted_secret)

          # format/encode value
          encoded_value = Base64.strict_encode64(value)

          Secrets.store(
            app: GitHub.launch_github_app,
            owner: owner,
            actor: actor,
            name: name,
            value: encoded_value,
          )
        end
      end
    end
  end
end
