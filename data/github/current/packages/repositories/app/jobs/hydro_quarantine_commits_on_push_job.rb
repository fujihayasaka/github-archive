# typed: true
# frozen_string_literal: true

class HydroQuarantineCommitsOnPushJob < Repositories::PushHydroMessageJob

  queue_as :hydro_quarantine_commits_on_push

  applies_to_empty_refs!

  COMMIT_BATCH_SIZE = 1000

  def perform
    if message[:quarantine_push_state].present? && message[:ref_batch_number] == 1 # for pushes with lots of ref updates, we'll batch them into multiple hydro events. We only need to process one event for a given push.
      push_state = Base64.decode64(message[:quarantine_push_state])

      has_next_page = T.let(true, T::Boolean)
      next_cursor = T.let(nil, T.untyped)
      commits_count = 0

      until !has_next_page
        commits_response = repository.spokes_api.list_quarantine_commits(push_state: push_state, cursor: next_cursor)
        commits_count += commits_response.commits.size
        has_next_page = commits_response.next_cursor.present?
        next_cursor = commits_response.next_cursor
        publish_commits_event(commits_response.commits)
      end

      GitHub.dogstats.histogram("quarantine_commits_on_push_job.quarantine_commits", commits_count)

      repository.spokes_api.remove_quarantine(push_state:)
    end
  end

  private

  def publish_commits_event(commits)
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
