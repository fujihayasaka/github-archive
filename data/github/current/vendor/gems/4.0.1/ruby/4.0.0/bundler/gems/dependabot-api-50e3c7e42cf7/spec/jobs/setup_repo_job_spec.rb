# frozen_string_literal: true

require "rails_helper"

RSpec.describe SetupRepoJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(account: account, github_id: 88632334, sha: sha) }

  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:sha) { nil }
  let(:account) do
    FactoryBot.create(
      :account, :active, :dependabot,
      installation_id: 1001,
    )
  end
  let(:dependabot_repository_settings_client) do
    instance_double(
      GitHub::Twirp::DependabotRepositorySettings,
      get_repository_settings: OpenStruct.new(automated_security_updates_enabled: true),
    )
  end

  before do
    # Clear out cached access tokens
    Rails.cache.clear

    allow(Dependabot::Application).
      to receive(:dependabot_repository_settings_client).
      and_return(dependabot_repository_settings_client)

    stub_request(:post, "#{github_url}app/installations/1001/access_tokens").
      with(body: anything).
      to_return(
        status: 200,
        body: erb_fixture("github_responses/installation_access_token.json"),
        headers: { "Content-Type" => "application/json" },
      )
  end

  context "when the account is inactive" do
    before do
      account.transition_to!(
        :inactive,
        installation_id: 1001,
      )
    end

    it "does not create the repository" do
      expect { job.perform_now }.not_to change(Repo, :count)
    end
  end

  context "when the repository is available in the GitHub API" do
    let(:repo_fixture) { fixture("github_responses/repo.json") }

    before do
      stub_request(:get, "#{github_url}repositories/88632334").
        to_return(
          status: 200,
          body: repo_fixture,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "creates a new repo" do
      expect { job.perform_now }.to change(Repo, :count).by(1)
    end

    it "instruments repository setup" do
      expect(MetricsClient).to receive(:increment).with("setup_repository", tags: { fork: false })

      job.perform_now
    end

    context "with a forked repository" do
      let(:repo_fixture) { fixture("github_responses/repo_fork.json") }

      it "instruments repository setup" do
        expect(MetricsClient).to receive(:increment).with("setup_repository", tags: { fork: true })

        job.perform_now
      end
    end

    it "creates a repo belonging to the account" do
      job.perform_now
      new_repo = account.repos.last
      expect(new_repo.name).to eql("bump-test")
      expect(new_repo.security_updates_enabled).to be(true)
    end

    it "enqueues a ci check" do
      expect { job.perform_now }.
        to have_enqueued_job(CheckRepoHasCiJob)
    end

    it "enqueues a config file sync job" do
      expect { job.perform_now }.
        to have_enqueued_job(ResyncRepoConfigFileJob).
        with(
          account: account,
          repo_name: "bump-test",
          repo_github_id: 88632334,
          skip_jobs: false,
        )
    end

    it "does not enqueue a config file validation check" do
      expect { job.perform_now }.
        not_to have_enqueued_job(ValidateConfigFileJob)
    end

    context "when given a SHA" do
      let(:sha) { "fake-sha-goes-here" }

      it "also enqueues a config file validation check" do
        expect { job.perform_now }.
          to have_enqueued_job(ValidateConfigFileJob).
          with(
            account: account,
            repo_github_id: 88632334,
            sha: sha,
          )
      end
    end
  end

  context "when the repository is available in the GitHub API, but already exists in Dependabot" do
    let!(:repo) do
      FactoryBot.create(:repo,
                        account: account,
                        name: "old-name",
                        github_id: 88632334,
                        security_updates_enabled: nil)
    end

    before do
      stub_request(:get, "#{github_url}repositories/88632334").
        to_return(
          status: 200,
          body: fixture("github_responses/repo.json"),
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "does not create a new Repo object" do
      expect { job.perform_now }.not_to change(Repo, :count)
    end

    it "updates the existing repo" do
      expect { job.perform_now }.
        to change { repo.reload.name }.from("old-name").to("bump-test").
        and change { repo.reload.security_updates_enabled }.to(true)
    end

    it "does not enqueue a ci check" do
      expect { job.perform_now }.
        not_to have_enqueued_job(CheckRepoHasCiJob)
    end

    it "enqueues a config file sync job" do
      expect { job.perform_now }.
        to have_enqueued_job(ResyncRepoConfigFileJob).
        with(
          account: account,
          repo_name: "bump-test",
          repo_github_id: 88632334,
          skip_jobs: false,
        )
    end
  end

  context "when the repository is forbidden via the GitHub API for the integration" do
    before do
      stub_request(:get, "#{github_url}repositories/88632334").
        to_return(
          status: 403,
          body: fixture("github_responses/forbidden_unavailable_to_integration.json"),
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "does not create a new Repo object" do
      expect { job.perform_now }.not_to change(Repo, :count)
    end

    it "retries the job" do
      expect { job.perform_now }.
        to have_enqueued_job(described_class).
        with(account: account, github_id: 88632334, sha: sha)
    end
  end

  context "when the repository is always forbidden via the GitHub API for the integration" do
    before do
      allow(Failbot).to receive(:report)
      stub_request(:get, "#{github_url}repositories/88632334").
        to_return(
          status: 403,
          body: fixture("github_responses/forbidden_unavailable_to_integration.json"),
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "raises" do
      perform_enqueued_jobs do
        expect do
          job.perform_now
        end.to raise_error(Dependabot::ResourceUnavailableToInstallation)
      end
    end
  end

  context "when the repository is unauthorized via the GitHub API" do
    before do
      allow(Failbot).to receive(:report)
      stub_request(:get, "#{github_url}repositories/88632334").
        to_return(
          status: 401,
          body: { error: "Bad credentials" }.to_json,
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "does not create a new Repo object" do
      expect { job.perform_now }.not_to change(Repo, :count)
    end

    it "retries the job" do
      expect { job.perform_now }.
        to have_enqueued_job(described_class).
        with(account: account, github_id: 88632334, sha: sha)
    end
  end

  context "when the repository is always unauthorized via the GitHub API" do
    before do
      allow(Failbot).to receive(:report)
      stub_request(:get, "#{github_url}repositories/88632334").
        to_return(
          status: 401,
          body: { error: "Bad credentials" }.to_json,
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "raises" do
      perform_enqueued_jobs do
        expect do
          job.perform_now
        end.to raise_error(Octokit::Unauthorized)
      end
    end
  end

  context "when the repository is not found via the GitHub API" do
    before do
      allow(Failbot).to receive(:report)
      stub_request(:get, "#{github_url}repositories/88632334").
        to_return(
          status: 404,
          body: { error: "Not found" }.to_json,
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "does not create a new Repo object" do
      expect { job.perform_now }.not_to change(Repo, :count)
    end

    it "retries the job" do
      expect { job.perform_now }.
        to have_enqueued_job(described_class).
        with(account: account, github_id: 88632334, sha: sha)
    end
  end

  context "when the repository is always not found via the GitHub API" do
    before do
      allow(Dependabot::Logger).to receive(:info)
      stub_request(:get, "#{github_url}repositories/88632334").
        to_return(
          status: 404,
          body: { error: "Not found" }.to_json,
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "logs the final exception" do
      perform_enqueued_jobs do
        job.perform_now

        expect(Dependabot::Logger).to have_received(:info).
          with(
            { msg: "repo not found", "code.namespace": "SetupRepoJob", "gh.owner.id": 27347476, "gh.repo.id": 88632334 }
          )
      end
    end
  end

  context "when the repository is unavailable via the GitHub API" do
    before do
      allow(Failbot).to receive(:report)
      stub_request(:get, "#{github_url}repositories/88632334").
        to_return(
          status: 403,
          body: { error: "repository access blocked" }.to_json,
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "does not create a new Repo object" do
      expect { job.perform_now }.not_to change(Repo, :count)
    end

    it "retries the job" do
      expect { job.perform_now }.
        to have_enqueued_job(described_class).
        with(account: account, github_id: 88632334, sha: sha)
    end
  end

  context "when the repository is always not available via the GitHub API" do
    let(:expected_error_message) do
      "GET #{github_url}repositories/88632334: 403 - Error: repository access blocked"
    end

    before do
      allow(Dependabot::Logger).to receive(:info)
      stub_request(:get, "#{github_url}repositories/88632334").
        to_return(
          status: 403,
          body: { error: "repository access blocked" }.to_json,
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "logs the final exception" do
      perform_enqueued_jobs do
        job.perform_now

        expect(Dependabot::Logger).to have_received(:info).
          with(
            { "exception.message": expected_error_message, "code.namespace": "SetupRepoJob", "gh.owner.id": 27347476,
              "gh.repo.id": 88632334, }
          )
      end
    end
  end

  context "when the repository is unavailable because of legal reasons" do
    before do
      stub_request(:get, "#{github_url}repositories/88632334").
        to_return(
          status: 451,
          body: fixture("github_responses/forbidden_legal_issue.json"),
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "does not create a new Repo object" do
      expect { job.perform_now }.not_to change(Repo, :count)
    end
  end

  context "when the repository is very young" do
    let(:repo_fixture) do
      json = fixture("github_responses/repo.json")
      data = JSON.parse!(json)
      data["created_at"] = 30.minutes.ago
      data
    end

    let(:repo_json) { repo_fixture.to_json }

    before do
      stub_monolith_feature(
        :dependabot_skip_jobs_on_new_repos,
        actor: FeatureFlags::Actor::Repository.new(repo_fixture["id"]),
        enabled: true
      )
      stub_request(:get, "#{github_url}repositories/#{repo_fixture['id']}").
        to_return(
          status: 200,
          body: repo_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "does not kick off jobs" do
      expect { job.perform_now }.
        to have_enqueued_job(ResyncRepoConfigFileJob).
        with(
          account: account,
          repo_name: "bump-test",
          repo_github_id: repo_fixture["id"],
          skip_jobs: true,
        )
    end
  end
end
