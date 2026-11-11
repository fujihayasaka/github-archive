# frozen_string_literal: true

require "rails_helper"

RSpec.describe SetMergeCommitPreference do
  subject(:action) { described_class.new(repo: repo) }

  let(:repo) { FactoryBot.create(:repo) }
  let(:commit_messages) do
    fixture("github_responses/graphql_commit_messages_squashed.json")
  end

  let(:github_graphql_endpoint) { Dependabot::Application.target_github_graphql_endpoint }

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for).
      and_return("token")
    stub_request(:post, github_graphql_endpoint).
      to_return(
        status: 200,
        body: commit_messages,
        headers: { "Content-Type" => "application/json" },
      )
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

  context "with a repo for an inactive account" do
    let(:account) { FactoryBot.create(:account, :inactive) }
    let(:repo) { FactoryBot.create(:repo, account: account) }

    it "does not query GitHub" do
      action.run
      assert_not_requested(:post, github_graphql_endpoint)
    end

    it "does not update the repo" do
      expect { action.run }.not_to change { repo }
    end
  end

  context "with a repo which has since been removed" do
    let(:commit_messages) do
      fixture("github_responses/graphql_repo_not_found.json")
    end

    it "does not update the repo" do
      expect { action.run }.not_to change { repo }
    end
  end

  context "when GitHub 500s" do
    before do
      stub_request(:post, github_graphql_endpoint).
        to_return(
          status: 500,
          body: "502 Bad Gateway",
          headers: { "Content-Type" => "application/json" },
        )
    end

    it "raises a helpful error" do
      expect { action.run }.
        to raise_error(SetMergeCommitPreference::ServerError)
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

    it "enqueues a resync for the repo" do
      result = SynchronizeRepoState::SynchronizeRepoStateResult.error(
        reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
      )
      dummy_repo_synchronizer = double(run: result)
      expect(SynchronizeRepoState).
        to receive(:new).with(
          repo: repo,
          event_source: "action.set_merge_commit_preference"
        ).and_return(dummy_repo_synchronizer)
      expect(dummy_repo_synchronizer).to receive(:run)
      action.run
    end
  end

  context "happy path" do
    context "with over 50 percent of merges using squash and merge" do
      let(:commit_messages) do
        fixture("github_responses/graphql_commit_messages_squashed.json")
      end

      it "marks the account as not using merge commits" do
        expect { action.run }.
          to change { repo.account.create_merge_commits }.
          from(true).to(false)
      end
    end

    context "with over 50 percent of merges using a merge commit" do
      let(:commit_messages) do
        fixture("github_responses/graphql_commit_messages_merge_commits.json")
      end

      before { repo.account.create_merge_commits = false }

      it "marks the account as using merge commits" do
        expect { action.run }.
          to change { repo.account.create_merge_commits }.
          from(false).to(true)
      end
    end
  end
end
