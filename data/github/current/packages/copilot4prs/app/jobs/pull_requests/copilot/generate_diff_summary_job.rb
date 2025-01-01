# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class GenerateDiffSummaryJob < ApplicationJob
      include ActiveJob::InitiallyEnqueuedAt

      class UnauthorizedComparisonError < StandardError; end

      queue_as :copilot_pull_requests

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      class FailedToBuildComparisonError < StandardError; end

      RETRYABLE_ERRORS = [
        Aqueduct::Worker::JobKilled,
        *Resiliency::Response::UnavailableExceptions,
      ].freeze

      EXPECTED_PIPELINE_ERRORS = [
        CopilotAPI::RAIError,
        FailedToBuildComparisonError,
        UnauthorizedComparisonError,
      ].freeze

      sig { returns(Time) }
      attr_accessor :job_started_at

      sig { params(job_status_id: String, store_prompts_and_completions: T::Boolean).void }
      def perform(job_status_id:, store_prompts_and_completions: false)
        self.job_started_at = Time.now.utc
        job_status = ::Copilot::CompletionJobStatus.find!(job_status_id)

        # TODO: Don't use track since we want `error_message` to be human readible
        track_job_status(job_status) do
          # Lookup context values and assign ivars
          extract_context!(job_status)
          Failbot.push(
            "gh.repo.id": @repository.id,
            "gh.actor.id": @actor.id
          )

          unless @comparison.viewable_by?(@actor)
            raise UnauthorizedComparisonError, "#{@actor} does not have permission for the requested comparison"
          end

          # Record resolved OIDs in the job status
          base_oid, head_oid = Promise.all([
            @comparison.async_base_oid,
            @comparison.async_head_oid
          ]).sync
          job_status.context.merge!(base_oid:, head_oid:)
          job_status.save

          # Generate diff summary completion
          pipeline = PullRequests::Copilot::Prompt::SummaryPipeline.new(comparison: @comparison,
            repository: @repository, custom_prompt: @custom_prompt)

          @token ||= ""
          completion = pipeline.perform(@actor, token: ::Copilot::DecryptedToken.from(@token))
          if store_prompts_and_completions
            job_status.context.merge!(all_prompts_and_completions: pipeline.all_prompts_and_completions)
          end

          # Record results in the job status
          job_timing_ms = ms_since(job_started_at)
          overall_timing_ms = ms_since(initially_enqueued_at)
          track_metrics(status: "success", start_time: job_started_at)
          job_status.context.merge!(completion:, job_timing_ms:, overall_timing_ms:)
        end

        true
      end

      # token - decrypted and decoded copilot-api authentication token
      sig do
        params(
          repository: Repository,
          actor: User,
          base_revision: String,
          head_revision: String,
          head_repo_id: T.any(String, Integer),
          token: String,
          custom_prompt: T.nilable(String)
        ).returns(T.nilable(::Copilot::CompletionJobStatus))
      end
      def self.enqueue(repository:, actor:, base_revision:, head_revision:, head_repo_id:, token:, custom_prompt: nil)
        return unless PullRequests::Copilot.copilot_for_prs_enabled?(::Copilot::Public::User.new(actor))

        job_status = ::Copilot::CompletionJobStatus.create(
          repository: repository,
          actor: actor,
          context: {
            base_revision:,
            head_revision:,
            head_repo_id:,
            token:,
            custom_prompt:
          }
        )
        perform_later(job_status_id: job_status.id)

        job_status
      end

      private

      sig { params(job_status: ::Copilot::CompletionJobStatus).void }
      def extract_context!(job_status)
        context = job_status.context || {}
        base_revision, head_revision, head_repo_id, token, custom_prompt = context.values_at(
          :base_revision, :head_revision, :head_repo_id, :token, :custom_prompt
        )

        @repository = job_status.repository
        @actor = job_status.actor
        @token = token
        @custom_prompt = custom_prompt

        hydro_payload(actor: @actor, repository: @repository, base_revision: base_revision,
          head_revision: head_revision)

        unless head_repo_id.nil? || head_repo_id == @repository&.id
          head_repo = Repositories::Public.find_active!(head_repo_id)
        end
        @comparison = GitHub::Comparison.build(base_repo: @repository, head_repo: head_repo,
          base_revision: base_revision, head_revision: head_revision)
        @comparison.set_diff_options(ignore_whitespace: true)
      end

      sig do
        params(
          actor: T.nilable(User),
          repository: T.nilable(Repository),
          base_revision: T.nilable(String),
          head_revision: T.nilable(String)
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def hydro_payload(actor: nil, repository: nil, base_revision: nil, head_revision: nil)
        copilot_user = actor.nil? ? nil : ::Copilot::User.new(actor)
        organization_id = 0
        business_id = 0

        if repository&.owner&.organization?
          owner = T.must(repository).owner
          organization = T.must(owner)
          organization_id = organization.id
          business_id = organization.business&.id || 0
        end
        @hydro_payload ||= {
          analytics_tracking_id: actor&.analytics_tracking_id,
          repository_id: repository&.id,
          head_revision: head_revision,
          base_revision: base_revision,
          organization_id: organization_id,
          business_id: business_id,
        }
      end

      sig { params(time: Time).returns(Float) }
      def ms_since(time)
        (Time.now.to_f - time.to_f) * 1_000
      end

      sig { params(job_status: ::Copilot::CompletionJobStatus, block: T.proc.void).void }
      def track_job_status(job_status, &block)
        job_status.started!
        yield
        job_status.success!
      rescue *RETRYABLE_ERRORS
        # leave job_status in "started" state.
        raise
      rescue *EXPECTED_PIPELINE_ERRORS => error
        track_metrics(status: "error", start_time: job_started_at, error_class: error.class.name)
        job_status_error!(job_status:, error:)
        raise
      rescue PullRequests::Copilot::Prompt::SummaryPipeline::NoMeaningfulFilesError, CopilotAPI::RequestError => error
        track_metrics(status: "error", start_time: job_started_at, error_class: error.class.name)
        job_status_error!(job_status:, error:)
      rescue => error # rubocop:todo Lint/RescueException
        track_metrics(status: "error", start_time: job_started_at, error_class: error.class.name)
        job_status_error!(job_status:, error:, message: "Something went wrong. Please try again.")
        raise
      end

      sig { params(status: String, start_time: Time, error_class: T.nilable(String)).void }
      def track_metrics(status:, start_time:, error_class: nil)
        tags = ["status:#{status}"]
        tags << "error:#{error_class}" if error_class
        GitHub.dogstats.timing_since("copilot.prompt.generate_diff_summary_job", start_time, tags: tags)
        GlobalInstrumenter.instrument("copilot.prompt.pull_request_summaries",
          hydro_payload.merge({ status: status }))
      end

      sig { params(job_status: ::Copilot::CompletionJobStatus, error: Exception, message: T.nilable(String)).void }
      def job_status_error!(job_status:, error:, message: nil)
        message ||= error.message
        job_status.error!(message)

        GitHub.logger.error(
          "Failed to generate diff summary",
          exception: error,
          "gh.actor.id": @actor.id,
          "gh.repo.id": @repository.id,
          "gh.copilot.context": job_status.context
        )
      end
    end
  end
end
