# frozen_string_literal: true

require "excon"
require "github_helpers"

class UpdatePullRequestBody
  def initialize(pull_request:, updated_body: nil, updated_title: nil)
    @pull_request = pull_request
    @updated_body = updated_body
    @updated_title = updated_title

    return unless updated_body.nil? && updated_title.nil?

    raise ArgumentError, "must provide an updated_body or updated_title"
  end

  def run
    unless pull_request.repo.account.active?
      MetricsClient.increment("dependabot_api.update_pull_request_body.error",
                              tags: metric_tags(reason: "inactive_account"))
      return false
    end

    update_pull_request
  rescue *SynchronizeRepoState::HANDLED_ERRORS => e
    handle_sync_error(e)
    false
  end

  private

  attr_reader :pull_request, :updated_body, :updated_title

  def update_pull_request
    installation_github_client.update_pull_request(
      pull_request.repo.github_id,
      pull_request.github_number,
      attributes_to_update,
    )
    true
  rescue Octokit::Forbidden => e
    MetricsClient.increment("dependabot_api.update_pull_request_body.error",
                            tags: metric_tags(reason: "octokit_error"))
    Dependabot::Logger.warn(
      msg: "Octokit Forbidden error rescued",
      error: e.message,
      "code.namespace": "UpdatePullRequestBody",
      **pull_request.telemetry_attributes,
    )
    raise unless e.message.include?("issue is locked")

    false
  end

  def attributes_to_update
    {
      body: updated_body,
      title: updated_title,
    }.compact
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.new(
        account: pull_request.repo.account,
      )
  end

  def metric_tags(reason:)
    { grouped_update: pull_request.grouped_update, reason: reason }
  end

  def handle_sync_error(error)
    MetricsClient.increment("dependabot_api.update_pull_request_body.error",
                            tags: metric_tags(reason: "synchronize_repo_state"))
    Dependabot::Logger.warn(
      msg: "SynchronizeRepoState error rescued",
      error: error.message,
      klass: error.class,
      "code.namespace": "UpdatePullRequestBody",
      **pull_request.telemetry_attributes,
    )
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "action.update_pull_request_body",
    ).run
  end
end
