# frozen_string_literal: true

require "rails_helper"

RSpec.describe SynchronizeAccountState do
  subject(:action) do
    described_class.new(account: account, event_source: "test")
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:installation_repos_url) do
    github_url + "installation/repositories?per_page=100"
  end
  let(:github_repos) { fixture("github_responses/installation_repos.json") }
  let(:github_installation) { fixture("github_responses/installation.json") }
  let(:account) do
    FactoryBot.create(
      :account, :active,
      installation_id: 25222,
      github_login: "old_name",
      github_id: 27347476,
    )
  end
  let!(:repo) do
    FactoryBot.create(
      :repo, :active,
      account: account,
      github_id: 88632334,
      name: "old_repo_name",
    )
  end

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    allow(MetricsClient).to receive(:increment)
  end

  context "when the installation is active" do
    before do
      stub_request(:get, "#{github_url}user/#{account.github_id}/installation").
        to_return(status: 200, body: github_installation, headers: json_header)
      stub_request(:get, "#{github_url}app/installations/25222").
        to_return(status: 200, body: "{}", headers: json_header)
      stub_request(:get, installation_repos_url).
        to_return(status: 200, body: github_repos, headers: json_header)
    end

    it "doesn't change the account's installation ID" do
      expect { action.run }.not_to change(account, :current_installation_id)
    end

    it "records the attempt" do
      expect(MetricsClient).to receive(:increment).with("action.synchronize_account_state")

      action.run
    end

    context "when the installation has changed" do
      let(:account) do
        FactoryBot.create(
          :account, :active,
          installation_id: 1001,
          github_login: "old_name",
          github_id: 27347476,
        )
      end

      before do
        stub_request(:get, github_url + "app/installations/25222").
          to_return(
            status: 200,
            body: github_installation,
            headers: json_header,
          )
      end

      it "updates the account's installation ID" do
        expect { action.run }.
          to change(account, :current_installation_id).
          to(25222)
      end

      it "records the attempt" do
        expect(MetricsClient).to receive(:increment).with("action.synchronize_account_state")

        action.run
      end
    end
  end

  context "when the installation has been disabled" do
    before do
      stub_request(:get, "#{github_url}user/#{account.github_id}/installation").
        to_return(status: 404)
    end

    it "deactivates the account" do
      expect { action.run }.
        to change { account.reload.current_state }.
        to("inactive")
    end

    it "instruments the deactivation with an event source" do
      expect(MetricsClient).to receive(:increment).
        with("account_transition.inactive",
             tags: { event_source: "test", repos: anything })
      action.run
    end

    it "records the attempt" do
      expect(MetricsClient).to receive(:increment).with("action.synchronize_account_state")

      action.run
    end

    context "but GitHub still returns it" do
      before do
        stub_request(
          :get,
          "https://#{github_url}user/#{account.github_id}/installation",
        ).to_return(
          status: 200,
          body: github_installation,
          headers: json_header,
        )
        stub_request(:get, "#{github_url}app/installations/25222").
          to_return(status: 404)
      end

      it "deactivates the account" do
        expect { action.run }.
          to change { account.reload.current_state }.
          to("inactive")
      end

      it "instruments the deactivation with an event source" do
        expect(MetricsClient).to receive(:increment).
          with("account_transition.inactive",
               tags: { event_source: "test", repos: anything })
        action.run
      end
    end

    context "and the account is already inactive" do
      before do
        account.transition_to!(
          :inactive,
          installation_id: account.current_installation_id,
        )
        stub_request(:get, "#{github_url}app/installations/").
          to_return(status: 404)
      end

      it "no-ops" do
        expect { action.run }.
          not_to change { account.last_transition(force_reload: true) }
      end

      it "does not instrument the deactivation" do
        expect(MetricsClient).not_to receive(:increment).
          with("account_transition.inactive",
               tags: { event_source: "test" })
        action.run
      end
    end
  end

  context "when the account is using the global app" do
    let(:account) do
      FactoryBot.create(
        :account, :active,
        installation_id: Account::GLOBAL_APP_INSTALLATION_ID,
        github_login: "old_name",
        github_id: 27347476,
      )
    end

    it "no-ops" do
      expect { action.run }.
        not_to change { account.last_transition(force_reload: true) }
    end

    it "records the attempt" do
      expect(MetricsClient).to receive(:increment).with("action.synchronize_account_state")

      action.run
    end
  end
end
