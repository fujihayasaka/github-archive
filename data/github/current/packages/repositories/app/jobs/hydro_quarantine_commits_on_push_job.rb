# typed: true
# frozen_string_literal: true

class HydroQuarantineCommitsOnPushJob < Repositories::PushHydroMessageJob

  queue_as :hydro_quarantine_commits_on_push

  # overriding config from base class for additional attempt(s)
  retry_on SpokesAPI::ResourceExhausted, delay: :polynomially_longer, max_retries: 9

  applies_to_empty_refs!

  COMMIT_BATCH_SIZE = 1000
  ENCODED_QUARANTINE_CURSOR_HEADER = "quarantine_cursor_encoded"

  def perform
    return if Repositories::HydroPushJobFlags.new(@enabled_flags).enabled?("git_commits_via_push_job")
    if message[:quarantine_push_state].present? && message[:ref_batch_number] == 1 # for pushes with lots of ref updates, we'll batch them into multiple hydro events. We only need to process one event for a given push.
      push_state = Base64.decode64(message[:quarantine_push_state])

      has_next_page = T.let(true, T::Boolean)
      commits_count = 0
      next_cursor = if headers[ENCODED_QUARANTINE_CURSOR_HEADER].present?
        GitHub::Spokes::Proto::Types::V1::Cursor.new(cursor: Base64.decode64(headers[ENCODED_QUARANTINE_CURSOR_HEADER]))
      else
        nil
      end

      until !has_next_page
        begin
          commits_response = repository.spokes_api.list_quarantine_commits(push_state: push_state, cursor: next_cursor)

          commits_count += commits_response.commits.size
          has_next_page = commits_response.next_cursor.present?
          next_cursor = commits_response.next_cursor
          publish_commits_event(commits_response.commits)
        rescue
          # Keep track of the last cursor we processed for retry.
          # The cursor returned from spokes is not guaranteed to be utf8 encodable, so we base64 encode it since the job system expects utf8 strings for headers.
          cursor = next_cursor&.cursor
          if cursor.present?
            headers[ENCODED_QUARANTINE_CURSOR_HEADER] = Base64.strict_encode64(cursor)
          end

          raise
        end
      end

      GitHub.dogstats.distribution("quarantine_commits_on_push_job.quarantine_commits_distribution", commits_count)
      GitHub.logger.info("High commit count quarantine processed", "gh.push.quarantine.commits.count": commits_count) if commits_count > 100_000

      repository.spokes_api.remove_quarantine(push_state:)
    end

  rescue SpokesAPI::NotFound => e
    GitHub.dogstats.increment("quarantine_commits_on_push_job.quarantine_not_found")

    GitHub.logger.error(
      "Failed to list quarantine commits",
      :exception => e,
      "gh.push_state" => message[:quarantine_push_state],
    )
  end

  private

  def publish_commits_event(commits)
    # Jobs consuming this event do not need to wait for MySQL replication on all clusters.
    # Set replication state to {} explicitly to prevent it from waiting for replication on every cluster by default.
    DatabaseSelector::LastOperations.with_static_replication_state({}) do
      commits.each_slice(COMMIT_BATCH_SIZE) do |commits_batch|
        commit_shas = commits_batch.map { |commit| commit.oid&.id }
        GitHub.aqueduct_fallback_hydro_publisher.publish(
          {
            repository_id: repository.id,
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            created_at: pushed_at,
            commit_shas: commit_shas,
            user_login: pusher.display_login,
            enabled_flags: message[:enabled_flags]
          },
          schema: "github.repositories.v1.CommitsCreated",
          partition_key: repository.id
        )
      end
    end
  end
end
