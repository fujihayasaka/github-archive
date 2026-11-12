# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotifyGitHubOfFailureJob, type: :job do
  include ActiveJob::TestHelper

  let(:error_hash) do
    { "error-type" => error_type, "error-detail" => error_detail }
  end

  let(:update_job) do
    FactoryBot.create(:update_job, :processing, :security_update)
  end

  let(:error_type) { "dependency_file_not_evaluatable" }
  let(:error_detail) { nil }

  context "::send_errors_for" do
    subject(:job_creator) { described_class.send_errors_for(update_job) }

    before do
      allow(described_class).to receive(:perform_later)
    end

    context "when the update_job is a version update with an error" do
      let(:update_job) do
        FactoryBot.create(:update_job, :processing, :version_update)
      end

      before do
        FactoryBot.create(:update_job_error, update_job: update_job)
      end

      it "enqueues no jobs and returns false" do
        expect(job_creator).to be_falsy
        expect(described_class).not_to have_received(:perform_later)
      end
    end

    context "when the update_job has no errors" do
      it "enqueues no jobs and returns false" do
        expect(job_creator).to be_falsy
        expect(described_class).not_to have_received(:perform_later)
      end
    end

    context "when the update_job has an error" do
      let!(:existing_error) do
        FactoryBot.create(:update_job_error, update_job: update_job)
      end

      it "enqueues a job for the error and returns true" do
        expect(job_creator).to be_truthy
        expect(described_class).to have_received(:perform_later).
          with(
            update_job: update_job,
            error_hash: existing_error.error_hash
          ).once
      end
    end

    context "when the update_job has two errors of the same type" do
      let(:error_type) { "dependency_file_not_evaluatable" }
      let(:error_detail) do
        { "message" => "Gemfile.lock was malformed" }
      end

      let(:expected_error_hash) do
        {
          "error-type" => error_type,
          "error-detail" => error_detail,
        }
      end

      before do
        FactoryBot.create(:update_job_error, update_job: update_job,
                                             error_type: error_type,
                                             error_details: error_detail)

        alternative_details = { "message" => "Error not used" }
        FactoryBot.create(:update_job_error, update_job: update_job,
                                             error_type: error_type,
                                             error_details: alternative_details)
      end

      it "enqueues a single job for the first error and returns true" do
        expect(job_creator).to be_truthy
        expect(described_class).to have_received(:perform_later).
          with(
            update_job: update_job,
            error_hash: expected_error_hash
          ).once
      end
    end
  end

  context "with an update job issue" do
    subject(:job) do
      described_class.new(update_job: update_job, error_hash: error_hash)
    end

    let(:error_type) { "dependency_file_not_evaluatable" }

    let(:update_job) { FactoryBot.create(:update_job) }
    let(:dummy_issue_creator) do
      instance_double(MarkGitHubJobErrored, run: nil)
    end

    it "delegates to the MarkGitHubJobErrored action" do
      expect(MarkGitHubJobErrored).
        to receive(:new).
        with(update_job: update_job, error_hash: error_hash).
        and_return(dummy_issue_creator)
      expect(dummy_issue_creator).to receive(:run)

      job.perform_now
    end

    context "that shouldn't be persisted" do
      let(:error_type) { "unknown_error" }

      it "still delegates to the MarkGitHubJobErrored action" do
        expect(MarkGitHubJobErrored).
          to receive(:new).
          with(update_job: update_job, error_hash: error_hash).
          and_return(dummy_issue_creator)
        expect(dummy_issue_creator).to receive(:run)

        job.perform_now
      end
    end
  end

  context "when the github job is already marked as errored" do
    subject(:job) do
      described_class.new(update_job: update_job, error_hash: error_hash)
    end

    it "does not retry the job" do
      expect(MarkGitHubJobErrored).to receive(:new).
        with(update_job: update_job, error_hash: error_hash).
        and_raise(MarkGitHubJobErrored::StateError)

      expect(job.perform_now).to be_truthy
    end
  end

  context "when the repo is no longer accessible to the installation" do
    subject(:job) do
      described_class.new(update_job: update_job, error_hash: error_hash)
    end

    it "does not retry the job" do
      expect(MarkGitHubJobErrored).to receive(:new).
        with(update_job: update_job, error_hash: error_hash).
        and_raise(GitHubGraphQL::UnauthorizedError)

      expect(job.perform_now).to be_truthy
    end
  end

  context "when the app is not installed" do
    subject(:job) do
      described_class.new(update_job: update_job, error_hash: error_hash)
    end

    it "retries the job when a resync is successful" do
      resync = instance_double(SynchronizeRepoState, run: nil)
      allow(SynchronizeRepoState).to receive(:new).
        and_return(resync)
      allow(resync).to receive(:run).
        and_return(OpenStruct.new(success?: true))

      expect(MarkGitHubJobErrored).to receive(:new).
        with(update_job: update_job, error_hash: error_hash).
        and_raise(MarkGitHubJobErrored::GitHubAppError)

      expect(job.perform_now).to be_truthy
    end

    it "does not retry the job when the resync fails" do
      resync = instance_double(SynchronizeRepoState, run: nil)
      allow(SynchronizeRepoState).to receive(:new).
        and_return(resync)
      allow(resync).to receive(:run).
        and_return(OpenStruct.new(success?: false))

      expect(MarkGitHubJobErrored).to receive(:new).
        with(update_job: update_job, error_hash: error_hash).
        and_raise(MarkGitHubJobErrored::GitHubAppError)

      expect(job.perform_now).to be_falsey
    end
  end

  context "when the graphql query raises an unexpected error" do
    subject(:job) do
      described_class.new(update_job: update_job, error_hash: error_hash)
    end

    it "retries the job" do
      expect(MarkGitHubJobErrored).to receive(:new).
        with(update_job: update_job, error_hash: error_hash).
        and_raise(MarkGitHubJobErrored::GraphQLQueryError)

      expect { job.perform_now }.to have_enqueued_job(described_class)
    end
  end
end
