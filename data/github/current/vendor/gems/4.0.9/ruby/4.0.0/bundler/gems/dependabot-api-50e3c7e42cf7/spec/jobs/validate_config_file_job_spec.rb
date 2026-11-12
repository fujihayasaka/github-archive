# frozen_string_literal: true

require "rails_helper"

RSpec.describe ValidateConfigFileJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(
      repo_github_id: repo_github_id,
      sha: sha,
      account: account
    )
  end

  let(:sha) { "ce587453ced02b1526dfb4cb910479d431683101" }
  let(:repo_github_id) { 88632334 }
  let(:account) { FactoryBot.create(:account, :dependabot, :active) }

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
  end

  context "validating the config file" do
    let!(:repo) do
      FactoryBot.create(
        :repo,
        :active,
        github_id: repo_github_id,
        account: account
      )
    end

    it "validates the config file" do
      dummy_validator = double(run: nil)
      expect(ValidateConfigFile).to receive(:new).with(repo: repo, sha: sha).
        and_return(dummy_validator)
      expect(dummy_validator).to receive(:run)
      job.perform_now
    end

    context "when the account is inactive" do
      before { repo.touch }

      before do
        account.transition_to!(
          :inactive, installation_id: account.current_installation_id
        )
      end

      it "doesn't attempt to validate the config file" do
        expect(ValidateConfigFile).not_to receive(:new)
        expect { job.perform_now }.not_to change(Repo, :count)
      end
    end
  end

  context "validating the config file when there is no repo in our database" do
    it "raises an exception" do
      expect { job.perform_now }.to raise_error(ActiveRecord::RecordNotFound, /Couldn't find Repo/)
    end
  end

  context "validating the config file when the repo belongs to a different account" do
    let!(:repo) do
      FactoryBot.create(
        :repo,
        :active,
        github_id: repo_github_id,
        account: FactoryBot.create(:account)
      )
    end

    it "raises an exception" do
      expect { job.perform_now }.to raise_error(ActiveRecord::RecordNotFound, /Couldn't find Repo/)
    end
  end

  context "retry callback" do
    subject(:perform_retry) { job.perform_now }

    let(:exception) { StandardError.new }

    before do
      # #perform normally sets this, but we need that to raise
      job.instance_variable_set("@account", account)
      allow(job).to receive(:perform).and_raise(exception) # rubocop:disable RSpec/SubjectStub
    end

    context "with a regular error" do
      it "does not delete the accounts github access token" do
        expect(GitHubHelpers).not_to receive(:delete_cached_access_token_for)

        expect(described_class.backoff_strategy).to receive(:should_retry?).
          with(1, exception).
          and_return(true)

        perform_retry
      end
    end

    context "with Octokit::Unauthorized error" do
      let(:exception) { Octokit::Unauthorized.new }

      it "deletes the cached access token for the account" do
        expect(described_class.backoff_strategy).to receive(:should_retry?).
          with(1, exception).
          and_return(true)

        expect(GitHubHelpers).to receive(:delete_cached_access_token_for).with(
          account: account
        )

        perform_retry
      end
    end
  end
end
