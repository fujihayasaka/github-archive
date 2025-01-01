# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class BulkGenerateDiffSummaryJob < ApplicationJob
      extend T::Sig
      include GitHub::Memoizer

      retry_on_dirty_exit

      queue_as :copilot_pull_requests

      PULL_REQUESTS_PER_JOB = 5

      sig { params(job_status_id: String, pull_request_ids: T::Array[Integer], pull_requests_per_job: Integer).void }
      def perform(job_status_id:, pull_request_ids:, pull_requests_per_job: PULL_REQUESTS_PER_JOB)
        @job_status = ::Copilot::CompletionJobStatus.find!(job_status_id)

        pr_ids_for_this_job = pull_request_ids[0..pull_requests_per_job - 1]
        pr_ids_for_next_job = pull_request_ids[pull_requests_per_job..-1]

        @completed_pull_request_summaries = []
        @failed_pull_request_summaries = []
        @pull_requests_in_progress = @job_status.repository.pull_requests.where(id: pr_ids_for_this_job).to_a

        @job_status.context.merge!(
          total_pull_requests_count: @pull_requests_in_progress.size,
          pull_requests_completed: [],
          pull_requests_failed: [],
          pull_requests_in_progress: @pull_requests_in_progress.map do |pull|
            { permalink: pull.permalink, title: pull.title, labels: pull.labels.map(&:name) }
          end
        )

        @job_status.started!

        while @pull_requests_in_progress.any?
          begin
            pull = @pull_requests_in_progress.shift
            child_job_status = ::Copilot::CompletionJobStatus.create(
              repository: repository,
              actor: actor,
              context: {
                base_revision: pull.base_sha,
                head_revision: pull.head_sha,
                head_repo_id: repository.id
              }
            )
            GenerateDiffSummaryJob.perform_now(job_status_id: child_job_status.id, store_prompts_and_completions: true)

            completed_job_status = ::Copilot::CompletionJobStatus.find!(child_job_status.id)
            if completed_job_status.success?
              summary_completed(pull:, all_prompts_and_completions: completed_job_status.context[:all_prompts_and_completions])
            else
              # Right now GenerateDiffSummaryJob re-raises on failures but this case makes sure we track them
              # correctly if that changes in the future and they no longer raise.
              summary_failed(pull:, error_message: completed_job_status.error_message)
            end
          rescue StandardError => e # rubocop:todo Lint/GenericRescue
            summary_failed(pull:, error_message: e.message)
          end
        end

        if pr_ids_for_next_job.present?
          next_job_status = ::Copilot::CompletionJobStatus.create(repository: repository, actor: actor)
          @job_status.context.merge!(next_job_status_id: next_job_status.id)
          PullRequests::Copilot::BulkGenerateDiffSummaryJob.perform_later(
            job_status_id: next_job_status.id,
            pull_request_ids: pr_ids_for_next_job,
            pull_requests_per_job:
          )
        end

        @job_status.success!
      end

      sig do
        params(
          repository: Repository,
          actor: User,
          pull_request_ids: T::Array[Integer],
          pull_requests_per_job: Integer
        ).returns(T.nilable(JobStatus))
      end
      def self.enqueue(repository:, actor:, pull_request_ids:, pull_requests_per_job: PULL_REQUESTS_PER_JOB)
        return unless PullRequests::Copilot.copilot_for_prs_enabled?(::Copilot::User.new(actor))

        job_status = ::Copilot::CompletionJobStatus.create(repository: repository, actor: actor)
        perform_later(job_status_id: job_status.id, pull_request_ids:, pull_requests_per_job:)
        job_status
      end

      private

      sig { returns Repository }
      memoize def repository
        @job_status.repository
      end

      sig { returns User }
      memoize def actor
        @job_status.actor
      end

      sig { params(pull: PullRequest, all_prompts_and_completions: T::Array[T::Hash[Symbol, String]]).void }
      def summary_completed(pull:, all_prompts_and_completions:)
        @completed_pull_request_summaries << {
          permalink: pull.permalink,
          title: pull.title,
          labels: pull.labels.map(&:name),
          all_prompts_and_completions:
        }

        @job_status.context.merge!(
          pull_requests_completed: @completed_pull_request_summaries,
          pull_requests_in_progress: @pull_requests_in_progress.map do |pull|
            { permalink: pull.permalink, title: pull.title, labels: pull.labels.map(&:name) }
          end
        )

        @job_status.save
      end

      sig { params(pull: PullRequest, error_message: T.nilable(String)).void }
      def summary_failed(pull:, error_message:)
        @failed_pull_request_summaries << {
          permalink: pull.permalink,
          title: pull.title,
          labels: pull.labels.map(&:name),
          error_message:,
        }

        @job_status.context.merge!(
          pull_requests_failed: @failed_pull_request_summaries,
          pull_requests_in_progress: @pull_requests_in_progress.map do |pull|
            { permalink: pull.permalink, title: pull.title, labels: pull.labels.map(&:name) }
          end
        )

        @job_status.save
      end
    end
  end
end
