# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemediateAccountAndRepoActivation do
  include ActiveSupport::Testing::TimeHelpers

  subject(:action) do
    described_class.new(
      github_repo_id: 1,
      github_account_id: 2,
      event_source: "test",
    )
  end

  let(:github_repo_id) { 1 }
  let(:github_account_id) { 2 }
  let(:installation_id) { "33" }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:installation_url) { "#{github_url}repositories/#{github_repo_id}/installation" }
  let(:global_access_token_url) { "#{github_url}app/global/access_tokens" }

  let(:repo_url) { "#{github_url}repositories/#{github_repo_id}" }
  let(:github_installation) do
    fixture("github_responses/installation.json").
      gsub("25222", installation_id).
      gsub("1144873", github_account_id.to_s)
  end
  let(:repo_details) do
    fixture("github_responses/repo.json").
      gsub("27347476", github_account_id.to_s)
  end
  let(:dependabot_repository_settings_client) do
    instance_double(
      GitHub::Twirp::DependabotRepositorySettings,
      get_repository_settings: OpenStruct.new(automated_security_updates_enabled: true),
    )
  end

  describe "without an existing account" do
    before do
      stub_request(:get, installation_url).
        to_return(status: 200, body: github_installation, headers: json_header)
      allow(GitHubHelpers).to receive(:installation_access_token_for).
        and_return("token")
      stub_request(:get, repo_url).
        to_return(status: 200, body: repo_details, headers: json_header)
      allow(Dependabot::Application).
        to receive(:dependabot_repository_settings_client).
        and_return(dependabot_repository_settings_client)
    end

    it "creates the account", :cloud, :enterprise do
      expect { action.run }.
        to change(Account, :count).by(1)
    end

    it "creates the repo", :cloud, :enterprise do
      expect { action.run }.
        to change(Repo, :count).by(1)
    end

    it "is necessary" do
      expect(action.necessary?).to eq(true)
    end
  end

  describe "without an existing account with global app onboarding" do
    before do
      stub_monolith_feature(
        :dependabot_global_app_onboarding,
        actor: FeatureFlags::Actor::User.new(github_account_id),
      )

      stub_request(:post, global_access_token_url).
        with(body: { target_id: github_account_id }.to_json).
        to_return(
          status: 200,
          body: erb_fixture("github_responses/global_access_token.json"),
          headers: json_header,
        )
      stub_request(:get, "#{github_url}user/#{github_account_id}").
        to_return(
          status: 200,
          body: fixture("github_responses/user_by_id.json").gsub("30846345", github_account_id.to_s),
          headers: json_header,
        )
      stub_request(:get, repo_url).
        to_return(status: 200, body: repo_details, headers: json_header)
      allow(Dependabot::Application).
        to receive(:dependabot_repository_settings_client).
        and_return(dependabot_repository_settings_client)
    end

    it "creates the account", :cloud do
      expect { action.run }.
        to change(Account, :count).by(1)
    end

    it "creates the repo", :cloud do
      expect { action.run }.
        to change(Repo, :count).by(1)
    end

    it "is necessary" do
      expect(action.necessary?).to eq(true)
    end
  end

  describe "given an existing inactive account" do
    let!(:account) do
      FactoryBot.create(
        :account, :inactive, :user,
        github_id: github_account_id,
      )
    end

    before do
      stub_request(:get, installation_url).
        to_return(status: 200, body: github_installation, headers: json_header)
      allow(GitHubHelpers).to receive(:installation_access_token_for).
        and_return("token")
      stub_request(:get, repo_url).
        to_return(status: 200, body: repo_details, headers: json_header)
      allow(Dependabot::Application).
        to receive(:dependabot_repository_settings_client).
        and_return(dependabot_repository_settings_client)
    end

    it "activates the account", :cloud, :enterprise do
      expect { action.run }.
        to change { account.current_state(force_reload: true) }.
        from("inactive").to("active")
    end

    it "creates the repo" do
      expect { action.run }.
        to change(Repo, :count).by(1)
    end

    it "is necessary" do
      expect(action.necessary?).to eq(true)
    end
  end

  describe "given an active account but not the repo" do
    before do
      allow(GitHubHelpers).to receive(:installation_access_token_for).
        and_return("token")
      stub_request(:get, repo_url).
        to_return(status: 200, body: repo_details, headers: json_header)
      allow(Dependabot::Application).
        to receive(:dependabot_repository_settings_client).
        and_return(dependabot_repository_settings_client)

      FactoryBot.create(
        :account, :active, :user,
        github_id: github_account_id,
        installation_id: installation_id,
      )
    end

    it "doesn't create any account transitions" do
      expect { action.run }.not_to change(AccountTransition, :count)
    end

    it "creates the repo" do
      expect { action.run }.
        to change(Repo, :count).by(1)
    end

    it "is necessary" do
      expect(action.necessary?).to eq(true)
    end
  end

  describe "given an active account and repo" do
    before do
      allow(GitHubHelpers).to receive(:installation_access_token_for).
        and_return("token")
      stub_request(:get, repo_url).
        to_return(status: 200, body: repo_details, headers: json_header)
      allow(Dependabot::Application).
        to receive(:dependabot_repository_settings_client).
        and_return(dependabot_repository_settings_client)

      account = FactoryBot.create(
        :account, :active, :user,
        github_id: github_account_id,
        installation_id: installation_id,
      )
      FactoryBot.create(
        :repo,
        account: account,
        github_id: github_repo_id,
      )
    end

    it "doesn't create any account transitions" do
      expect { action.run }.not_to change(AccountTransition, :count)
    end

    it "doesn't create the repo" do
      expect { action.run }.not_to change(Repo, :count)
    end

    it "isn't necessary" do
      expect(action.necessary?).to eq(false)
    end
  end

  describe "when the repo doesn't have an installation" do
    before do
      stub_request(:get, installation_url).
        to_return(status: 404)
    end

    it "raises an error", :cloud, :enterprise do
      expect { action.run }.to raise_error(RemediateAccountAndRepoActivation::RepoNotAccessible)
    end
  end

  describe "when the repo is unavailable for legal reasons" do
    before do
      stub_request(:get, installation_url).
        to_return(status: 200, body: github_installation, headers: json_header)
      allow(GitHubHelpers).to receive(:installation_access_token_for).
        and_return("token")
      stub_request(:get, repo_url).
        to_return(
          status: 451,
          body: fixture("github_responses/forbidden_legal_issue.json"),
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "raises an error" do
      expect { action.run }.to raise_error(RemediateAccountAndRepoActivation::RepoNotAccessible)
    end
  end
end
