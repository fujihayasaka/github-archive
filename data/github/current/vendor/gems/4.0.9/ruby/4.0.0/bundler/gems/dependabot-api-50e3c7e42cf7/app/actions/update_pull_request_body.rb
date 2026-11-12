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
    return false unless pull_request.repo.account.active?

    update_pull_request
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "action.update_pull_request_body",
    ).run

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
end
