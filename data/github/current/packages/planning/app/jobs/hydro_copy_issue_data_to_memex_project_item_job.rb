# typed: strict
# frozen_string_literal: true

class HydroCopyIssueDataToMemexProjectItemJob < HydroMessageJob
  include GitHub::Memoizer
  queue_as :hydro_copy_issue_data_to_memex_project_item

  METRIC_PREFIX = "gh.projects.hydro_copy_issue_data_to_memex_project_item_job"

  THROTTLING_ERRORS = [
    Freno::Error,
    Freno::Throttler::Error,
    Freno::Throttler::CircuitOpen,
    Freno::Throttler::WaitedTooLong
  ]

  UNAVAILABILITY_ERRORS = Resiliency::Response::UnavailableExceptions

  BACKOFF_STRATEGY = T.let(
    { max_retries: 5, delay: :polynomially_longer }.freeze,
    T::Hash[Symbol, T.any(Integer, Symbol)]
  )

  T.unsafe(self).retry_on(*THROTTLING_ERRORS, **BACKOFF_STRATEGY) { |job, error| job.failed!(error) }
  T.unsafe(self).retry_on(*UNAVAILABILITY_ERRORS, **BACKOFF_STRATEGY) { |job, error| job.failed!(error) }
  retry_on_dirty_exit { |job, error| job.failed!(error) }

  sig { void }
  def perform
    return unless message_valid?
    return unless referenced_issue_present?
    ref_issue = T.must(referenced_issue)

    MemexProjectItem.where(repository_id:, content_id:, content_type:, issue_id: ref_issue.id).find_each do |item|
      with_write do
        MemexProjectItem.throttle do
          item.update(
            issue_closed_at: ref_issue.closed_at,
            state: ref_issue.state,
            state_reason: ref_issue.state_reason
          )
        end
      end
    end

    GitHub.dogstats.increment(
      "#{METRIC_PREFIX}.success",
      tags: ["content_type:#{T.must(content_type).underscore.dasherize}"]
    )
  end

  sig { returns(T::Boolean) }
  private def message_valid?
    return true if repository_id && content_id && content_type
    GitHub.dogstats.increment("#{METRIC_PREFIX}.skipped", tags: ["reason:message-invalid"])
    GitHub.logger.info(
      "Invalid Hydro message",
      "code.namespace" => self.class.name,
      "code.functione" => "message_valid?",
      "gh.projects.hydro_copy_issue_data_to_memex_project_item_job.repository_id" => repository_id || "nil",
      "gh.projects.hydro_copy_issue_data_to_memex_project_item_job.content_id" => content_id || "nil",
      "gh.projects.hydro_copy_issue_data_to_memex_project_item_job.content_type" => content_type || "nil",
      "messaging.kafka.source.topic" => topic,
      "messaging.kafka.source.partition" => partition,
      "messaging.kafka.message.schema" => schema,
      "messaging.kafka.message.offset" => offset,
      "messaging.kafka.message.timestamp" => timestamp,
    )
    false
  end

  sig { returns(T::Boolean) }
  private def referenced_issue_present?
    return true if referenced_issue
    GitHub.dogstats.increment("#{METRIC_PREFIX}.skipped", tags: ["reason:missing-issue"])
    false
  end

  sig { returns(T.nilable(Issues::IIssue)) }
  memoize private def referenced_issue
    if pull_request_id
      PullRequest.find_by(id: pull_request_id)&.issue
    elsif issue_number && repository_id
      Issues.domain.by_number(T.must(issue_number), repo_id: T.must(repository_id))
    end
  end

  sig { returns(T.nilable(Integer)) }
  private def repository_id
    message.dig(:repository, :id)
  end

  sig { returns(T.nilable(Integer)) }
  private def content_id
    pull_request_id || issue_id
  end

  sig { returns(T.nilable(String)) }
  private def content_type
    if pull_request_id
      "PullRequest"
    elsif issue_id
      "Issue"
    end
  end

  sig { returns(T.nilable(Integer)) }
  private def pull_request_id
    message.dig(:pull_request, :id)
  end

  sig { returns(T.nilable(Integer)) }
  private def issue_id
    message.dig(:issue, :id)
  end

  sig { returns(T.nilable(Integer)) }
  private def issue_number
    message.dig(:issue, :number)
  end

  sig do
    params(
      # Surprisingly, `Aqueduct::Worker::JobKilled` does not inherit from `StandardError`.
      error: T.any(Aqueduct::Worker::JobKilled, StandardError)
    ).void
  end
  def failed!(error)
    GitHub.dogstats.increment(
      "#{METRIC_PREFIX}.failed",
      tags: ["error:#{error.class.name&.underscore}"]
    )
    Failbot.report!(error, "code.namespace": self.class.name)
  end
end
