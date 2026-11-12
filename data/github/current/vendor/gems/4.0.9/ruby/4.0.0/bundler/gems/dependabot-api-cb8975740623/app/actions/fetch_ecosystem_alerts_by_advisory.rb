# frozen_string_literal: true

require "github_helpers"

class FetchEcosystemAlertsByAdvisory
  attr_reader :repo, :advisory

  def initialize(repo:, advisory:)
    @repo = repo
    @advisory = advisory
  end

  def run
    return [] if advisory.nil?

    @run ||= ecosystem_alerts(repo, advisory)
  end

  private

  def ecosystem_alerts(repo, advisory)
    client = GitHubHelpers::ClientWithRetries.new(account: repo.account)

    client.get(
      "repositories/#{repo.github_id}/dependabot/alerts",
      query: { state: "open", ecosystem: advisory.ecosystem, per_page: 100 }
    )
  end
end
