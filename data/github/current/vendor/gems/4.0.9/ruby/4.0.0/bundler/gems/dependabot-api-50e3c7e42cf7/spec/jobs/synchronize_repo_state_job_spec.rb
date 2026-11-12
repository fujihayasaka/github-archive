# frozen_string_literal: true

require "rails_helper"

RSpec.describe SynchronizeRepoStateJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(repo: repo, event_source: "test") }

  let(:repo) do
    FactoryBot.create(:repo, :active)
  end

  it "delegates to SynchronizeRepoState action" do
    result = SynchronizeRepoState::SynchronizeRepoStateResult.success
    dummy_repo_synchronizer = double(run: result)
    expect(SynchronizeRepoState).
      to receive(:new).with(repo: repo, event_source: "test").
      and_return(dummy_repo_synchronizer)
    expect(dummy_repo_synchronizer).to receive(:run)
    job.perform_now
  end

  context "retry callback" do
    subject(:perform_retry) { job.perform_now }

    let(:exception) { StandardError.new }

    before do
      # #perform normally sets this, but we need that to raise
      job.instance_variable_set("@repo", repo)
      allow(job).to receive(:perform).and_raise(exception) # rubocop:disable RSpec/SubjectStub

      expect(described_class.backoff_strategy).to receive(:should_retry?).
        with(1, exception).
        and_return(true)
    end

    context "with a regular error" do
      it "does not delete the accounts github access token" do
        expect(GitHubHelpers).not_to receive(:delete_cached_access_token_for)

        perform_retry
      end
    end

    context "with Octokit::Unauthorized error" do
      let(:exception) { Octokit::Unauthorized.new }

      it "deletes the cached access token for the account" do
        expect(GitHubHelpers).to receive(:delete_cached_access_token_for).with(
          account: repo.account
        )

        perform_retry
      end
    end
  end

  describe "log_job_state" do
    let(:dummy_repo_synchronizer) { double }

    before do
      allow(SynchronizeRepoState).
        to receive(:new).with(repo: repo, event_source: "test").
        and_return(dummy_repo_synchronizer)
    end

    context "when synchronization is successful" do
      before do
        allow(dummy_repo_synchronizer).to receive(:run).
          and_return(SynchronizeRepoState::SynchronizeRepoStateResult.success)
      end

      it "logs the success message" do
        expect(Dependabot::Logger).to receive(:info).with(
          msg: "SynchronizeRepoStateJob completed successfully",
          "code.namespace": "SynchronizeRepoStateJob",
          "gh.repo.id": repo.github_id
        )
        job.perform_now
      end
    end

    context "when synchronization encounters an error" do
      let(:error_reason) { "some_error_reason" }

      before do
        allow(dummy_repo_synchronizer).to receive(:run).
          and_return(SynchronizeRepoState::SynchronizeRepoStateResult.error(reason: error_reason))
      end

      it "logs the error message with reason" do
        expect(Dependabot::Logger).to receive(:error).with(
          msg: "SynchronizeRepoStateJob encountered an error",
          "code.namespace": "SynchronizeRepoStateJob",
          reason: error_reason,
          "gh.repo.id": repo.github_id
        )
        job.perform_now
      end
    end
  end
end
