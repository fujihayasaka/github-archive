# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemediateAccountAndRepoActivationJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(github_account_id: github_account_id, github_repo_id: github_repo_id, sha: sha,
                        event_source: event_source)
  end

  let(:github_account_id) { 42 }
  let(:github_repo_id) { 33 }
  let(:event_source) { "test" }
  let(:sha) { nil }

  context "when remediation is no longer needed" do
    before do
      remediation_action = RemediateAccountAndRepoActivation.new(
        github_repo_id: github_repo_id,
        github_account_id: github_account_id,
        event_source: "test",
      )
      allow(RemediateAccountAndRepoActivation).to receive(:new).
        with(github_repo_id: github_repo_id,
             github_account_id: github_account_id,
             event_source: "test",).
        and_return(remediation_action)
      allow(remediation_action).to receive(:necessary?).
        and_return(false)
    end

    it "does not enqueue a repo config sync job" do
      expect { job.perform_now }.
        not_to have_enqueued_job(ResyncRepoConfigFileJob)
    end

    it "does not enqueue config file validation check run" do
      expect { job.perform_now }.
        not_to have_enqueued_job(ValidateConfigFileJob)
    end
  end

  context "when remediation is needed" do
    let(:account) do
      FactoryBot.create(
        :account, :active, :dependabot,
      )
    end
    let(:repo) do
      FactoryBot.create(:repo,
                        account: account,
                        name: "bump-test",
                        github_id: github_repo_id,
                        security_updates_enabled: nil)
    end

    before do
      remediation_action = instance_double(RemediateAccountAndRepoActivation)
      allow(RemediateAccountAndRepoActivation).to receive(:new).
        with(github_repo_id: github_repo_id,
             github_account_id: github_account_id,
             event_source: "test",).
        and_return(remediation_action)
      allow(remediation_action).to receive(:necessary?).
        and_return(true)
      allow(remediation_action).to receive(:run).
        and_return(repo)
    end

    it "enqueues a config file sync job" do
      expect { job.perform_now }.
        to have_enqueued_job(ResyncRepoConfigFileJob).
        with(
          account: account,
          repo_name: "bump-test",
          repo_github_id: github_repo_id,
          skip_jobs: false,
          event_source: "test",
        )
    end

    context "when given a SHA" do
      let(:sha) { "fake-sha-goes-here" }

      it "also enqueues a config file validation check" do
        expect { job.perform_now }.
          to have_enqueued_job(ValidateConfigFileJob).
          with(
            account: account,
            repo_github_id: github_repo_id,
            sha: sha,
          )
      end
    end
  end
end
