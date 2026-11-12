# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResyncRepoConfigFileJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(
      account: account,
      repo_name: repo_name,
      repo_github_id: repo_github_id,
      event_source: event_source,
    )
  end

  let(:account) { FactoryBot.create(:account) }
  let(:repo_name) { "dependabot-test" }
  let(:repo_github_id) { 88632334 }
  let(:event_source) { "test" }
  let(:repo) { create(:repo, account: account, name: repo_name, github_id: repo_github_id) }

  let(:dummy_config_file_processor) do
    instance_double(ProcessConfigFile, run: nil)
  end

  before do
    allow(Stafftools::ResyncRepoJob).to receive(:perform_later)
    repo.enable_feature(:resync_repo_on_duplicate_directories)
  end

  it "delegates to the ProcessConfigFile action" do
    expect(ProcessConfigFile).
      to receive(:new).
      with(
        account: account,
        repo_name: repo_name,
        repo_github_id: repo_github_id,
        quiet: false,
        event_source: event_source,
      ).
      and_return(dummy_config_file_processor)

    expect(dummy_config_file_processor).to receive(:run)

    job.perform_now

    expect(Stafftools::ResyncRepoJob).not_to have_received(:perform_later)
  end

  context "when there is an error that prevents completion" do
    before do
      allow(Dependabot::Logger).to receive(:info)
      allow(ProcessConfigFile).to receive(:new).and_raise(RuntimeError, "totally broken.")
    end

    it "raises the error" do
      expect { job.perform_now }.to raise_error(RuntimeError, "totally broken.")

      expect(Dependabot::Logger).to have_received(:info).with(
        msg: "unable to synchronize config file.",
        "code.namespace": "ResyncRepoConfigFileJob",
        "exception.type": "RuntimeError",
        "exception.message": "totally broken.",
        "gh.repo.id": repo_github_id,
        "gh.dependabot_api.event.source": event_source,
      )
      expect(Stafftools::ResyncRepoJob).not_to have_received(:perform_later)
    end
  end

  context "when there is a duplicate directory error" do
    before do
      allow(Dependabot::Logger).to receive(:info)
    end

    it "starts a resync repo job" do
      expect(ProcessConfigFile).
        to receive(:new).
        with(
          account: account,
          repo_name: repo_name,
          repo_github_id: repo_github_id,
          quiet: false,
          event_source: event_source,
        ).
        and_return(dummy_config_file_processor)

      invalid_update_config = build(:update_config, :active, repo: repo, directory: "/.")
      invalid_update_config.errors.add(:directory, "has already been taken")
      expect(dummy_config_file_processor).to receive(:run).and_raise(ActiveRecord::RecordInvalid, invalid_update_config)

      job.perform_now

      expect(Stafftools::ResyncRepoJob).to have_received(:perform_later)
    end
  end

  # Retryable exceptions:
  [
    # Faraday::ConnectionFailed.new,
    # Faraday::TimeoutError.new,
    # Faraday::SSLError.new,
    # Octokit::BadGateway.new(status: 502, body: nil, response_headers: {}),
    # Octokit::InternalServerError.new(status: 500, body: nil, response_headers: {}),
    # Octokit::ServerError.new(status: 522, body: nil, response_headers: {}),
    # Octokit::AbuseDetected.new(status: 403, body: "abuse", response_headers: {}),
    # Octokit::TooManyRequests.new(status: 403, body: "rate limit exceeded", response_headers: {}),
    # Errors handled from default_retries_for_idempotent_jobs
    *Dependabot::Exceptions::RECOVERABLE_DATABASE_EXCEPTION_CLASSES.map(&:new),
  ].each do |exception|
    context "when #{exception.class.name} is raised" do
      before do
        allow(Dependabot::Logger).to receive(:info)
        allow(ProcessConfigFile).to receive(:new).and_raise(exception)
      end

      it "retries" do
        expect { job.perform_now }.
          to have_enqueued_job(described_class).
          on_queue("default")
      end

      it "does not raise the error" do
        expect { job.perform_now }.not_to raise_error

        expect(Dependabot::Logger).not_to have_received(:info)
      end

      it "raises the error once retries are exhausted" do
        perform_enqueued_jobs do
          expect { job.perform_now }.to raise_error(exception)

          expect(Dependabot::Logger).to have_received(:info).with(
            msg: "unable to synchronize config file.",
            "code.namespace": "ResyncRepoConfigFileJob",
            "exception.type": exception.class.name,
            "exception.message": exception.message,
            "gh.repo.id": repo_github_id,
            "gh.dependabot_api.event.source": event_source,
          )
        end
      end
    end
  end
end
