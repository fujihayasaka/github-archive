# typed: true
# frozen_string_literal: true

class QuarantineCommitsJob < Repositories::PushApplicationJob
  include GitHub::Memoizer

  queue_as :quarantine_commits

  # We handle retries for SpokesAPI::ResourceExhausted manually so we can enqueue a new job with an attempts argument.
  # We raise this exception after SPOKES_RESOURCE_EXHAUSTED_ATTEMPTS attempts.
  class SpokesRetriesExhausted < StandardError
    # We don't want the underlying SpokesAPI::ResourceExhausted to result in a retry.
    def cause; end
  end
  SPOKES_RESOURCE_EXHAUSTED_ATTEMPTS = 10 # To get 9 _retries_ via ActiveJob, we need 10 _attempts_ here.

  COMMIT_BATCH_SIZE = 1000

  sig do
    params(
      repository_id: Integer,
      push_id: Integer,
      encoded_push_state: String,
      attempt: Integer,
      encoded_cursor: T.nilable(String)
    ).void
  end
  def perform(repository_id:, push_id:, encoded_push_state:, attempt: 1, encoded_cursor: nil)
    push = Push.find(push_id)
    push_state = Base64.decode64(encoded_push_state)
    delete_quarantine = T.let(false, T::Boolean)

    # A cheap check to see if this entire push has already been fully processed. Handles the case where a user
    # is contually pushing ref updates that make the same set of commits unreachable and then reachable.
    if AuthenticCommit.exists?(network_id: repository.network_id, oid: push.after)
      GitHub.dogstats.increment("quarantine_commits_job.quarantine_push_already_processed")
      GitHub.logger.info(
        "All commits in this quarantine push were already processed",
        @log_context
      )
      delete_quarantine = true
    else
      # If spokes throttled us in the middle of a commit batch, resume from the last cursor.
      cursor = if encoded_cursor.present?
        GitHub::Spokes::Proto::Types::V1::Cursor.new(cursor: Base64.decode64(encoded_cursor))
      else
        nil
      end
      delete_quarantine = process_quarantine_commits(push_id, push_state, attempt, cursor)
    end

    repository.spokes_api.remove_quarantine(push_state:) if delete_quarantine

  rescue SpokesAPI::NotFound => e
    GitHub.dogstats.increment("quarantine_commits_job.quarantine_not_found")
    GitHub.logger.error(
      "Failed to list quarantine commits",
      logging_context.merge!(exception: e)
    )
  end

  protected

  sig { override.returns(Integer) }
  def push_id
    get_named_job_argument(:push_id)
  end

  sig { override.returns(Integer) }
  def repository_id
    get_named_job_argument(:repository_id)
  end

  private

  sig do
    params(
      push_id: Integer,
      push_state: String,
      attempt: Integer,
      cursor: T.nilable(GitHub::Spokes::Proto::Types::V1::Cursor)
    ).returns(T::Boolean)
  end
  def process_quarantine_commits(push_id, push_state, attempt, cursor = nil)
    has_next_page = T.let(true, T::Boolean)
    commits_count = 0
    next_cursor = T.let(cursor, T.nilable(GitHub::Spokes::Proto::Types::V1::Cursor))
    quarantine_fully_processed = T.let(false, T::Boolean)

    until !has_next_page
      begin
        commits_response = repository.spokes_api.list_quarantine_commits(push_state: push_state, cursor: next_cursor)

        commits_count += commits_response.commits.size
        has_next_page = commits_response.next_cursor.present?
        next_cursor = commits_response.next_cursor
        process_commits(push_id, commits_response.commits.to_a)
        quarantine_fully_processed = !has_next_page # no next page and we processed the last one successfully
      rescue SpokesAPI::ResourceExhausted
        has_next_page = false

        # Keep track of the last cursor we processed for retry.
        # The cursor returned from spokes is not guaranteed to be utf8 encodable so we base64 encode it.
        if attempt < SPOKES_RESOURCE_EXHAUSTED_ATTEMPTS
          retry_cursor = next_cursor&.cursor
          QuarantineCommitsJob.set(wait: polynomially_longer_delay_with_jitter(attempt)).perform_later(
            repository_id: repository_id,
            push_id: push_id,
            encoded_push_state: Base64.encode64(push_state),
            attempt: attempt + 1,
            encoded_cursor: retry_cursor ? Base64.encode64(retry_cursor) : nil
          )
          GitHub.logger.info("gh.repo.quarantine_commits_job.requeued", logging_context)
        else
          # We've exhausted our retries. Raise custom error with nil cause to fail without retrying.
          raise SpokesRetriesExhausted
        end
      end
    end

    GitHub.dogstats.histogram("quarantine_commits_job.quarantine_commits", commits_count)
    quarantine_fully_processed
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def logging_context
    super.merge({
      "gh.push_state": get_named_job_argument(:encoded_push_state)
    })
  end

  sig do
    params(
      push_id: Integer,
      commits: T::Array[GitHub::Spokes::Proto::Commits::V1::CommitItem]
    ).void
  end
  def process_commits(push_id, commits)
    commits.each_slice(COMMIT_BATCH_SIZE) do |commits_batch|
      commit_shas = commits_batch.map { |commit| commit.oid&.id }.compact
      AuthenticCommitsJob.perform_later(repository_id: repository.id, push_id:, commit_shas:)
    end
  end

  def polynomially_longer_delay_with_jitter(attempts)
    # Polynomial backoff with a base delay of 2 seconds and a polynomial factor of 4
    # This is the same as retry_on :polynomially_longer.
    jitter_default = 0.15
    delay = attempts**4
    delay_jitter = Kernel.rand * delay * jitter_default
    delay + delay_jitter + 2
  end
end
