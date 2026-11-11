# frozen_string_literal: true

require "rails_helper"

RSpec.describe CheckRepoHasCi do
  subject(:action) { described_class.new(repo: repo) }

  let(:repo) { FactoryBot.create(:repo) }
  let(:commit_statuses) do
    fixture("github_responses/graphql_commit_ci_status_rollups.json")
  end

  let(:github_graphql_endpoint) { Dependabot::Application.target_github_graphql_endpoint }
  let(:repo_sync_result) do
    SynchronizeRepoState::SynchronizeRepoStateResult.error(
      reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
    )
  end
  let(:dummy_repo_sync) { double(run: repo_sync_result) }

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for).
      and_return("token")
    stub_request(:post, github_graphql_endpoint).
      to_return(
        status: 200,
        body: commit_statuses,
        headers: { "Content-Type" => "application/json" },
      )
    allow(SynchronizeRepoState).
      to receive(:new).with(repo: repo, event_source: anything).
      and_return(dummy_repo_sync)
  end

  context "with bad credentials" do
    before do
      stub_request(:post, github_graphql_endpoint).
        to_return(
          status: 401,
          body: fixture("github_responses/graphql_bad_credentials.json"),
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "raises a helpful error" do
      expect { action.run }.to raise_error(/401/)
    end
  end

  context "when rate limited" do
    before do
      stub_request(:post, github_graphql_endpoint).
        to_return(
          status: 403,
          body: fixture("github_responses/graphql_rate_limited.json"),
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "raises a helpful error" do
      expect { action.run }.to raise_error(GitHubGraphQL::RateLimited)
    end
  end

  context "with a repo for an inactive account" do
    let(:account) { FactoryBot.create(:account, :inactive) }
    let(:repo) { FactoryBot.create(:repo, account: account) }

    it "does not query GitHub" do
      action.run
      assert_not_requested(:post, github_graphql_endpoint)
    end

    it "makes no changes to the repo" do
      expect { action.run }.not_to change { repo }
    end
  end

  context "with a repo which has since been removed" do
    let(:commit_statuses) do
      fixture("github_responses/graphql_repo_not_found.json")
    end
    let(:repo) { FactoryBot.create(:repo, :active) }

    it "resync's the repo" do
      expect(dummy_repo_sync).to receive(:run) do
        repo.update_configs.each { |uc| uc.transition_to(:deleted) }
      end
      action.run
    end

    context "for an account that doesn't resync" do
      it "does not raise an error" do
        expect(dummy_repo_sync).to receive(:run)

        expect { action.run }.not_to raise_error
      end
    end
  end

  context "with a repo which doesn't have any commits" do
    let(:commit_statuses) { fixture("github_responses/graphql_null_repo.json") }
    let(:repo) { FactoryBot.create(:repo, :active) }

    it "no-ops" do
      expect { action.run }.not_to change(repo, :has_ci)
    end
  end

  context "for an access token that can't be fetched" do
    before do
      allow(GitHubHelpers).
        to receive(:installation_access_token_for).
        and_call_original

      access_token_url =
        "https://internal-api.service.iad.github.net/app/installations/"\
        "#{repo.account.current_installation_id}/access_tokens"
      stub_request(:post, access_token_url).to_return(status: 404)
    end

    it "resyncs the repo" do
      expect(dummy_repo_sync).to receive(:run) do
        repo.account.transition_to!(
          :inactive,
          installation_id: repo.account.current_installation_id,
        )
      end
      action.run
    end
  end

  context "happy path" do
    context "with statuses or check runs" do
      let(:repo) { FactoryBot.create(:repo, has_ci: false) }
      let(:commit_statuses) do
        fixture("github_responses/graphql_commit_ci_status_rollups.json")
      end

      it "marks the repo as having ci" do
        expect { action.run }.
          to change(repo, :has_ci).
          from(false).to(true)
      end
    end

    context "with no CI" do
      let(:repo) { FactoryBot.create(:repo, has_ci: true) }
      let(:commit_statuses) do
        fixture("github_responses/graphql_commit_ci_status_rollups_no_ci.json")
      end

      it "marks the repo as not having ci" do
        expect { action.run }.
          to change(repo, :has_ci).
          from(true).to(false)
      end
    end
  end
end
