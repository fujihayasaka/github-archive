# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResyncUnpausedRepoJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(repo: repo) }

  let(:installation_id) { 1001 }
  let(:account) do
    FactoryBot.create(
      :account, :active, :dependabot,
      installation_id: installation_id,
    )
  end
  let(:repo) do
    FactoryBot.create(
      :repo, :active, :bump_test,
      account: account,
      github_id: 4, # corresponds to monalisa/smile in gh/gh localdev
    )
  end
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{repo.github_id}" }
  let(:install_access_token_url) do
    "#{github_url}app/installations/#{installation_id}/access_tokens"
  end
  let(:install_access_token) do
    erb_fixture("github_responses/installation_access_token.json")
  end
  let(:dependabot_repository_settings_client) do
    instance_double(
      GitHub::Twirp::DependabotRepositorySettings,
      get_repository_settings: OpenStruct.new(automated_security_updates_enabled: true)
    )
  end

  before do
    # Clear out cached access tokens
    Rails.cache.clear

    stub_request(:post, install_access_token_url).
      with(body: anything).
      to_return(
        status: 200,
        body: install_access_token,
        headers: json_header,
      )

    allow(Dependabot::Application).
      to receive(:dependabot_repository_settings_client).
      and_return(dependabot_repository_settings_client)
  end

  context "when resyncing the repo state is successful" do
    before do
      stub_request(:get, repo_url).
        to_return(
          status: 200,
          body: fixture("github_responses/repo.json"),
          headers: json_header
        )
    end

    it "enqueues CheckRepoHasCiJob" do
      expect { job.perform_now }.to have_enqueued_job(CheckRepoHasCiJob)
    end
  end

  context "when resyncing the repo state fails" do
    before do
      stub_request(:get, repo_url).
        to_return(
          status: 451,
          body: fixture("github_responses/forbidden_legal_issue.json"),
        )
    end

    it "does not enqueue any follow up CI jobs" do
      expect { job.perform_now }.not_to have_enqueued_job
    end
  end
end
