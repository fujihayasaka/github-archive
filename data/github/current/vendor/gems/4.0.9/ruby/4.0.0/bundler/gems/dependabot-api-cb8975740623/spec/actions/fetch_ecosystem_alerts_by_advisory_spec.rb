# frozen_string_literal: true

require "rails_helper"

RSpec.describe FetchEcosystemAlertsByAdvisory do
  describe "#run" do
    let(:repo) { build_stubbed(:repo) }
    let(:advisory) { instance_double("HydroHandlers::GitHub::SecurityVulnerability", ecosystem: "bundler") }
    let(:alerts_response) do
      [{ "number" => 1, "security_vulnerability" => { "package" => { "name" => "rack" } } }]
    end

    before do
      allow(GitHubHelpers).to receive(:access_token_for).and_return("fake-token")
    end

    it "requests alerts at the correct API path when the endpoint has a path prefix" do
      ghes_api_endpoint = "http://localhost:1337/api/v3/"
      allow(Dependabot::Application).to receive(:target_github_internal_api_endpoint).and_return(ghes_api_endpoint)

      stub = stub_request(:get, "http://localhost:1337/api/v3/repositories/#{repo.github_id}/dependabot/alerts").
             with(query: { ecosystem: "bundler", state: "open", per_page: "100" }).
             to_return(status: 200, body: alerts_response.to_json, headers: { "Content-Type" => "application/json" })

      described_class.new(repo: repo, advisory: advisory).run

      expect(stub).to have_been_requested
    end

    it "returns the parsed alert data" do
      api_endpoint = Dependabot::Application.target_github_internal_api_endpoint
      stub_request(:get, "#{api_endpoint}repositories/#{repo.github_id}/dependabot/alerts").
        with(query: { ecosystem: "bundler", state: "open", per_page: "100" }).
        to_return(status: 200, body: alerts_response.to_json, headers: { "Content-Type" => "application/json" })

      result = described_class.new(repo: repo, advisory: advisory).run

      expect(result).to be_a(Array)
      expect(result.first.number).to eq(1)
    end

    it "returns an empty array if there is no advisory" do
      action = described_class.new(repo: repo, advisory: nil)

      expect(action.run).to eq([])
    end
  end
end
