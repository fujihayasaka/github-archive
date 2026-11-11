# frozen_string_literal: true

require "rails_helper"

RSpec.describe RepositoryPushHandler do
  describe "#run" do
    subject(:run_handler) { handler.run }

    let(:handler) do
      described_class.new(ref, before_sha, after_sha, repository_payload, owner_payload, changed_files)
    end

    let(:ref) { "refs/heads/main" }
    let(:before_sha) { "before_sha" }
    let(:after_sha) { "after_sha" }
    let(:repository_payload) do
      {
        id: 12345,
        name: "new-name",
        default_branch: "main",
        visibility: "PUBLIC",
        primary_language_name: "Ruby",
      }
    end
    let(:owner_payload) { { id: 67890 } }
    let(:changed_files) { [] }
    let(:account) { create(:account, github_id: 67890) }

    let!(:repo) do
      create(:repo, github_id: 12345, name: "old-name", default_branch: "main", account: account)
    end

    it "updates the repository attributes correctly" do
      run_handler

      repo.reload
      expect(repo.name).to eq("new-name")
      expect(repo.default_branch).to eq("main")
      expect(repo.private).to be(false)
      expect(repo.primary_language).to eq("ruby")
    end

    it "reads the repository from the replica" do
      allow(ActiveRecord::Base).to receive(:connected_to).and_call_original
      run_handler
      expect(ActiveRecord::Base).to have_received(:connected_to).with(role: :reading).at_least(:once)
    end

    it "writes to the primary database with a row lock" do
      allow(ActiveRecord::Base).to receive(:connected_to).and_call_original

      # Spy on Repo.transaction to ensure we are wrapping the update
      expect(Repo).to receive(:transaction).and_call_original

      # Mock the locking mechanism to ensure it's being used
      lock_scope = instance_double(ActiveRecord::Relation)
      locked_repo = instance_double(Repo, id: repo.id)

      allow(Repo).to receive(:lock).and_return(lock_scope)
      allow(lock_scope).to receive(:find).with(repo.id).and_return(locked_repo)

      expect(locked_repo).to receive(:update!).with(
        name: "new-name",
        default_branch: "main",
        private: false,
        primary_language: "ruby"
      )

      run_handler

      expect(ActiveRecord::Base).to have_received(:connected_to).with(role: :writing).at_least(:once)
    end

    context "when pushing to a Dependabot branch" do
      let(:ref) { "refs/heads/dependabot/npm_and_yarn/lodash-4.17.21" }
      let!(:pull_request) do
        create(:pull_request, repo: repo, head_commit_sha: before_sha)
      end

      it "updates the pull request head commit" do
        allow(ActiveRecord::Base).to receive(:connected_to).and_call_original
        expect { run_handler }.to change { pull_request.reload.head_commit_sha }.from(before_sha).to(after_sha)
        expect(ActiveRecord::Base).to have_received(:connected_to).with(role: :writing).at_least(:once)
      end

      it "enqueues a job to update CI status" do
        expect(UpdatePullRequestCiStatusJob).to receive(:perform_later).with(
          pull_request_id: pull_request.id,
          refs_to_check: [after_sha],
        )
        run_handler
      end
    end
  end
end
