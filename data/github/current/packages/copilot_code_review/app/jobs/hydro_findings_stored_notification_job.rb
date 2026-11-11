# typed: strict
# frozen_string_literal: true

class HydroFindingsStoredNotificationJob < HydroMessageJob
  queue_as :hydro_findings_stored_notification

  retry_on_dirty_exit

  TAB_COUNT_EVENT_NAME = "tab_counts_updated"
  FINDINGS_UPDATED_EVENT_NAME = "findings_updated"

  sig { void }
  def perform
    pull_request_id = message[:pull_request_id]
    repo_id = message[:repo_id]
    head_sha = message[:head_sha]
    findings_count = message.fetch(:severe_findings_count) { message[:findings_count] }

    unless pull_request_id.is_a?(Integer) && pull_request_id > 0
      log("missing pull_request_id")
      return
    end

    count = findings_count.is_a?(Integer) ? findings_count : 0
    PullRequests::Copilot::FindingsCountCache.new(pull_request_id).store(count)
    notify_pull_request_updates(pull_request_id, repo_id)

    log("cached findings count #{count} for PR #{pull_request_id} at #{head_sha}")
  rescue StandardError => err
    log("error: #{err.message}")
    raise err
  end

  private

  sig { params(pull_request_id: Integer, repo_id: T.untyped).void }
  def notify_pull_request_updates(pull_request_id, repo_id)
    unless repo_id.is_a?(Integer) && repo_id > 0
      log("missing repo_id")
      return
    end

    pull_request = PullRequest.find_by(id: pull_request_id)
    unless pull_request
      log("missing pull request #{pull_request_id}")
      return
    end

    channel = GitHub::WebSocket::Channels.pull_request(pull_request)
    GitHub::WebSocket.notify_pull_request_channel(
      pull_request,
      channel,
      {
        timestamp: Time.now.to_i,
        wait: pull_request.default_live_updates_wait,
        reason: "pull request ##{pull_request.id} findings count updated",
        event_updates: { "#{TAB_COUNT_EVENT_NAME}": true, "#{FINDINGS_UPDATED_EVENT_NAME}": true },
      },
    )
  end

  sig { params(msg: String).void }
  def log(msg)
    context = {
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => GitHub.context[:request_id],
    }
    GitHub.logger.info("hydro_findings_stored_notification_job: #{msg}", context)
  end
end
