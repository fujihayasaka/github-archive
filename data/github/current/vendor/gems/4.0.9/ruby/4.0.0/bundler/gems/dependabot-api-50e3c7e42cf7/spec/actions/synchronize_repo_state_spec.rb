# frozen_string_literal: true

require "rails_helper"

RSpec.describe SynchronizeRepoState do
  subject(:job) { described_class.new(repo: repo).run }

  let(:installation_id) { 1001 }
  let(:account) do
    FactoryBot.create(
      :account, :active, :dependabot,
      installation_id: installation_id,
      github_login: "old_name",
    )
  end
  let(:repo) do
    FactoryBot.create(
      :repo, :active, :bump_test,
      account: account,
      name: "old_repo_name",
      security_updates_enabled: nil
    )
  end
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_repo) { fixture("github_responses/repo.json") }
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
      get_repository_settings: OpenStruct.new(automated_security_updates_enabled: true),
    )
  end

  before do
    # Clear out cached access tokens
    Rails.cache.clear

    allow(Dependabot::Logger).to receive(:info)
    allow(Dependabot::Application).
      to receive(:dependabot_repository_settings_client).
      and_return(dependabot_repository_settings_client)

    stub_request(:get, repo_url).
      to_return(status: 200, body: github_repo, headers: json_header)
    stub_request(:post, install_access_token_url).
      with(body: anything).
      to_return(
        status: 200,
        body: install_access_token,
        headers: json_header,
      )
  end

  shared_examples "deactivates the repo" do |reason|
    it "deactivates the repo and logs the repo id" do
      expect(repo.reload.active?).to eq(true)
      subject
      expect(repo.reload.active?).to eq(false)

      expect(Dependabot::Logger).to have_received(:info).with(
        msg: "deactivate repo",
        "code.namespace": "SynchronizeRepoState",
        reason: reason,
        "exception.message": anything,
        "gh.repo.id": repo.github_id,
      )
    end
  end

  shared_examples "leaves the repo active" do
    it "makes no changes to the repository state" do
      expect { subject }.not_to change { repo.reload.active? }.from(true)
    end
  end

  shared_examples "returns a account_out_of_sync error" do
    it "returns a account_out_of_sync error" do
      result = subject
      expect(result.success?).to be(false)
      expect(result.error?).to be(true)
      expect(result.reason).to eq(described_class::ACCOUNT_OUT_OF_SYNC)
    end
  end

  shared_examples "returns a unavailable_for_legal_reasons error" do
    it "returns a unavailable_for_legal_reasons error" do
      result = subject
      expect(result.success?).to be(false)
      expect(result.error?).to be(true)
      expect(result.reason).
        to eq(described_class::UNAVAILABLE_FOR_LEGAL_REASONS)
    end
  end

  shared_examples "returns a billing_issue error" do
    it "returns a billing_issue error" do
      result = subject
      expect(result.success?).to be(false)
      expect(result.error?).to be(true)
      expect(result.reason).to eq(described_class::BILLING_ISSUE)
    end
  end

  shared_examples "returns a trade_control error" do
    it "returns a trade_control error" do
      result = subject
      expect(result.success?).to be(false)
      expect(result.error?).to be(true)
      expect(result.reason).to eq(described_class::TRADE_CONTROL)
    end
  end

  shared_examples "returns a missing_installation error" do
    it "returns missing_installation error" do
      result = subject
      expect(result.success?).to be(false)
      expect(result.error?).to be(true)
      expect(result.reason).to eq(described_class::MISSING_INSTALLATION)
    end
  end

  shared_examples "returns a installation_lacks_write_access error" do
    it "returns installation_lacks_write_access error" do
      result = subject
      expect(result.success?).to be(false)
      expect(result.error?).to be(true)
      expect(result.reason).to eq(described_class::INSTALLATION_LACKS_WRITE_ACCESS)
    end
  end

  it "updates the account with the latest GitHub details" do
    expect { subject }.
      to change { account.reload.github_login }.
      to("dependabot")
  end

  context "when running in Proxima", :proxima do
    let(:github_repo) do
      fixture("github_responses/repo.json").
        gsub("dependabot", "suffixless-dependabot_github")
    end

    it "doesn't update the `github_login` with a shortcode suffix in Proxima" do
      expect { subject }.
        to change { account.reload.github_login }.
        to("suffixless-dependabot")
    end
  end

  it "updates the repo with the latest GitHub details" do
    expect { subject }.
      to change { repo.reload.name }.to("bump-test").
      and change { repo.reload.security_updates_enabled }.to(true)
  end

  it "returns a successful result" do
    result = subject
    expect(result.success?).to be(true)
    expect(result.error?).to be(false)
  end

  context "with an inactive account" do
    before do
      account.transition_to!(
        :inactive,
        installation_id: account.current_installation_id,
      )
    end

    it "doesn't synchronize the account" do
      expect(SynchronizeAccountState).not_to receive(:new)
      subject
    end
  end

  context "when the repo can't be found on GitHub" do
    let(:installation_repos_url) do
      github_url + "installation/repositories?per_page=100"
    end
    let(:github_repos) do
      fixture("github_responses/installation_repos.json").gsub("88632334", "88")
    end
    let(:github_installation) do
      fixture("github_responses/installation.json").
        gsub("25222", installation_id.to_s)
    end

    before do
      stub_request(:get, repo_url).to_return(status: 404)
      stub_request(:get, installation_repos_url).
        to_return(status: 200, body: github_repos, headers: json_header)
      stub_request(:get, "#{github_url}organizations/#{account.github_id}/installation").
        to_return(status: 200, body: github_installation, headers: json_header)
      stub_request(
        :get,
        "#{github_url}app/installations/#{installation_id}",
      ).to_return(status: 200, body: "{}", headers: json_header)
    end

    it "returns a repo temporarily unavailable error" do
      result = subject
      expect(result.success?).to be(false)
      expect(result.error?).to be(true)
      expect(result.reason).to eq(described_class::REPO_TEMPORARILY_UNAVAILABLE)
    end

    it "does not deactivate the repo" do
      expect { subject }.not_to change { repo.reload.active? }
    end

    context "because the installation has been disabled" do
      before do
        stub_request(
          :get,
          "#{github_url}organizations/#{account.github_id}/installation",
        ).to_return(status: 404)
      end

      it "deactivates the account" do
        expect { subject }.
          to change { account.reload.current_state }.
          to("inactive")
      end

      context "with an inactive account" do
        before do
          account.transition_to!(
            :inactive,
            installation_id: installation_id,
          )
          stub_request(:get, "#{github_url}app/installations/").
            to_return(status: 404)
        end

        it "doesn't synchronize account state" do
          expect { subject }.
            not_to change { repo.reload.active? }.from(true)
        end
      end
    end

    context "because of a legal issue" do
      before do
        stub_request(:get, repo_url).
          to_return(
            status: 451,
            body: fixture("github_responses/forbidden_legal_issue.json"),
          )
      end

      include_examples "deactivates the repo", "unavailable_for_legal_reasons"
      include_examples "returns a unavailable_for_legal_reasons error"
    end

    context "because of trade restrictions on the repo" do
      before do
        stub_request(:get, repo_url).
          to_return(
            status: 403,
            body: fixture("github_responses/forbidden_trade_restriction.json"),
          )
      end

      include_examples "deactivates the repo", "trade_control"
      include_examples "returns a trade_control error"
    end

    context "because of trade restrictions on the owner" do
      before do
        stub_request(:get, repo_url).
          to_return(
            status: 403,
            body: fixture(
              "github_responses/forbidden_trade_restriction_verbose.json"
            ),
          )
      end

      include_examples "deactivates the repo", "trade_control"
      include_examples "returns a trade_control error"
    end

    context "because of a billing issue" do
      before do
        stub_request(:get, repo_url).
          to_return(
            status: 403,
            body: fixture("github_responses/forbidden_billing_issue.json"),
          )
      end

      include_examples "leaves the repo active"
      include_examples "returns a billing_issue error"
    end

    context "because the installation no longer has access to the repository" do
      before do
        stub_request(:get, repo_url).
          to_return(
            status: 403,
            body: fixture("github_responses/forbidden_unavailable_to_integration.json"),
          )
      end

      include_examples "leaves the repo active"
      include_examples "returns a installation_lacks_write_access error"
    end

    context "because the account has been flagged as spammy" do
      before do
        stub_request(:get, repo_url).to_return(status: 404)
        allow(Dependabot::Application.dependabot_repository_settings_client).
          to receive(:get_repository_settings).
          and_raise(GitHub::Twirp::DependabotRepositorySettings::NotFound, "is spammy")
      end

      it "deactivates the account" do
        expect { subject }.
          to change { repo.account.reload.active? }.from(true).to(false)
      end
    end

    context "when dependabot isn't installed on the repository" do
      before do
        stub_request(:post, install_access_token_url).
          to_return(
            status: 422,
            body: fixture("github_responses/repo_installation_missing.json"),
          )
      end

      it { expect(subject).to be_intermittent_failure }

      include_examples "leaves the repo active"
      include_examples "returns a missing_installation error"
    end

    context "when no repository was provided" do
      before do
        stub_request(:post, install_access_token_url).
          to_return(
            status: 422,
            body: fixture("github_responses/no_repository_provided.json"),
          )
      end

      it { expect(subject).to be_intermittent_failure }

      include_examples "leaves the repo active"
      include_examples "returns a missing_installation error"
    end

    context "when the user installation is missing (unexpected error)" do
      before do
        stub_request(:post, install_access_token_url).
          to_return(
            status: 422,
            body: fixture("github_responses/user_installation_missing.json"),
          )
      end

      it "raises error" do
        expect { subject }.to raise_error(Octokit::UnprocessableEntity)
      end
    end

    context "when the user scope is wrong (unexpected error)" do
      before do
        stub_request(:post, install_access_token_url).
          to_return(
            status: 403,
            body: fixture("github_responses/forbidden_user_scope.json"),
          )
      end

      it "raises error" do
        expect { subject }.to raise_error(Octokit::Forbidden)
      end
    end
  end

  context "when the repo has been transferred" do
    let(:installation_repos_url) do
      github_url + "installation/repositories?per_page=100"
    end
    let(:github_repos) do
      fixture("github_responses/installation_repos.json").gsub("88632334", "88")
    end
    let(:github_installation) do
      fixture("github_responses/installation.json").
        gsub("25222", installation_id.to_s)
    end

    before { account.update!(github_id: 1234) }

    before do
      stub_request(:get, installation_repos_url).
        to_return(status: 200, body: github_repos, headers: json_header)
      stub_request(:get, "#{github_url}organizations/#{account.github_id}/installation").
        to_return(status: 200, body: github_installation, headers: json_header)
      stub_request(
        :get,
        "#{github_url}app/installations/#{installation_id}",
      ).to_return(status: 200, body: "{}", headers: json_header)
    end

    it "resyncs the repo account" do
      expect { subject }.
        to have_enqueued_job(TransferRepoAccountJob).
        with(repo: repo, new_account: nil)
    end

    it "does not deactivate the repo" do
      expect { subject }.
        not_to change { account.repos.active.count }
    end

    include_examples "returns a account_out_of_sync error"
  end

  context "when the repo has been archived" do
    let(:installation_repos_url) do
      github_url + "installation/repositories?per_page=100"
    end
    let(:github_repos) do
      fixture("github_responses/installation_repos_2.json").
        gsub("87123", "88632334")
    end
    let(:github_repo) do
      fixture("github_responses/repo.json").
        gsub('"archived": false', '"archived": true')
    end
    let(:github_installation) do
      fixture("github_responses/installation.json").
        gsub("25222", installation_id.to_s)
    end

    before do
      stub_request(:get, installation_repos_url).
        to_return(status: 200, body: github_repos, headers: json_header)
      stub_request(:get, "#{github_url}organizations/#{account.github_id}/installation").
        to_return(status: 200, body: github_installation, headers: json_header)
      stub_request(
        :get,
        "#{github_url}app/installations/#{installation_id}",
      ).to_return(status: 200, body: "{}", headers: json_header)
    end

    include_examples "deactivates the repo", "account_out_of_sync"
    include_examples "returns a account_out_of_sync error"
  end

  context "when the repo has been deleted" do
    before do
      # getting the access token raises with 422
      stub_request(:post, install_access_token_url).
        with(body: anything).
        to_return(status: 422, body: '"repo is deleted"', headers: json_header)

      # the Twirp call returns not_found
      allow(Dependabot::Application).
        to receive(:dependabot_repository_settings_client).
        and_raise(GitHub::Twirp::DependabotRepositorySettings::NotFound)
    end

    include_examples "deactivates the repo", "repo_deleted"
  end

  context "when Dependabot is not installed and the repo is a fork" do
    before do
      # getting the access token raises with 422 because Dependabot is not installed
      stub_request(:post, install_access_token_url).
        with(body: anything).
        to_return(status: 422, body: '"dependabot not installed"', headers: json_header)
    end

    # the Twirp call says Dependabot is not enabled
    let(:dependabot_repository_settings_client) do
      instance_double(
        GitHub::Twirp::DependabotRepositorySettings,
        get_repository_settings: OpenStruct.new(dependabot_installed: false),
      )
    end

    # the repo is a fork
    let(:repo) do
      FactoryBot.create(
        :repo, :active, :bump_test,
        account: account,
        name: "old_repo_name",
        security_updates_enabled: nil,
        fork: true
      )
    end

    include_examples "deactivates the repo", "dependabot_not_installed"
  end

  context "when the integration doesn't have access to the resource and the repo is a fork" do
    before do
      # getting the access token raises with 403 and a specific error text
      stub_request(:post, install_access_token_url).
        with(body: anything).
        to_return(status: 403, body: "Resource not accessible by integration")
    end

    # the Twirp call says Dependabot is not enabled
    let(:dependabot_repository_settings_client) do
      instance_double(
        GitHub::Twirp::DependabotRepositorySettings,
        get_repository_settings: OpenStruct.new(dependabot_installed: false),
      )
    end

    # the repo is a fork
    let(:repo) do
      FactoryBot.create(
        :repo, :active, :bump_test,
        account: account,
        name: "old_repo_name",
        security_updates_enabled: nil,
        fork: true
      )
    end

    include_examples "deactivates the repo", "dependabot_not_installed"

    it "logs the resource unavailable log" do
      allow(Dependabot::Logger).to receive(:info)

      subject

      expect(Dependabot::Logger).to have_received(:info).with(
        hash_including(msg: "Resource unavailable to installation")
      )
    end
  end
end
