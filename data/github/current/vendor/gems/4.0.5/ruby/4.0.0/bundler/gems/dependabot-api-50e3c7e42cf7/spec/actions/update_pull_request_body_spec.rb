# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdatePullRequestBody do
  subject(:action) do
    described_class.new(
      pull_request: pull_request,
      updated_body: updated_body,
    )
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{pull_request.repo.github_id}/" }
  let(:pr_url) { repo_url + "pulls/#{pull_request.github_number}" }

  let(:pull_request) { FactoryBot.create(:pull_request, github_number: 21) }
  let(:updated_body) { "New description!" }
  let(:repo_synchronizer_result) do
    SynchronizeRepoState::SynchronizeRepoStateResult.error(
      reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
    )
  end
  let(:dummy_repo_synchronizer) { double(run: repo_synchronizer_result) }

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    allow(SynchronizeRepoState).
      to receive(:new).with(repo: pull_request.repo,
                            event_source: "action.update_pull_request_body").
      and_return(dummy_repo_synchronizer)
  end

  it "updates the description on GitHub and returns true" do
    stub_request(:patch, pr_url)

    expect(action.run).to eq(true)
    expect(WebMock).
      to have_requested(:patch, pr_url).
      with(body: { body: updated_body }.to_json)
  end

  context "with an updated title" do
    subject(:action) do
      described_class.new(
        pull_request: pull_request,
        updated_title: "New title",
      )
    end

    it "updates the title on GitHub and returns true" do
      stub_request(:patch, pr_url)

      expect(action.run).to eq(true)
      expect(WebMock).
        to have_requested(:patch, pr_url).
        with(body: { title: "New title" }.to_json)
    end
  end

  context "with neither an updated title nor body" do
    subject(:action) { described_class.new(pull_request: pull_request) }

    it "raises an argument error" do
      stub_request(:patch, pr_url)

      expect { action.run }.to raise_error(ArgumentError)
    end
  end

  context "but the old PR is locked" do
    let(:locked) { fixture("github_responses/forbidden_locked.json") }

    before do
      stub_request(:patch, pr_url).
        to_return(status: 403, body: locked, headers: json_header)
    end

    it "returns false" do
      expect(action.run).to eq(false)
      expect(WebMock).
        to have_requested(:patch, pr_url).
        with(body: { body: updated_body }.to_json)
    end
  end

  context "but the installation no longer has access to the repository's pull requests" do
    let(:forbidden) { fixture("github_responses/forbidden_unavailable_to_integration.json") }

    before do
      pull_request.repo.update!(private: false)
      stub_request(:patch, pr_url).
        to_return(status: 403, body: forbidden, headers: json_header)
    end

    it "resyncs the repo state" do
      expect(dummy_repo_synchronizer).to receive(:run)

      action.run
    end
  end

  context "but the repository is now read-only" do
    let(:forbidden) { fixture("github_responses/forbidden_archived.json") }

    before do
      pull_request.repo.update!(private: false)
      stub_request(:patch, pr_url).
        to_return(status: 403, body: forbidden, headers: json_header)
    end

    it "resyncs the repo state" do
      expect(dummy_repo_synchronizer).to receive(:run)

      action.run
    end
  end
end
