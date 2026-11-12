# frozen_string_literal: true

require "rails_helper"

RSpec.describe FetchEcosystemAlertsByAdvisory do
  describe "#run" do
    it "fetches alerts for an advisory from the monolith" do
      repo = build_stubbed(:repo)
      advisory = instance_double("HydroHandlers::GitHub::SecurityVulnerability", ecosystem: "bundler")
      action = described_class.new(repo: repo, advisory: advisory)

      client_double = instance_double("Octokit::Client")
      allow(GitHubHelpers::ClientWithRetries).to receive(:new).and_return(client_double)

      expect(client_double).
        to receive(:get).
        with("/repositories/#{repo.github_id}/dependabot/alerts",
             query: { ecosystem: advisory.ecosystem, state: "open", per_page: 100 })
      action.run
    end

    it "returns an empty array if there is no advisory" do
      repo = build_stubbed(:repo)
      action = described_class.new(repo: repo, advisory: nil)

      expect(action.run).to eq([])
    end
  end
end
