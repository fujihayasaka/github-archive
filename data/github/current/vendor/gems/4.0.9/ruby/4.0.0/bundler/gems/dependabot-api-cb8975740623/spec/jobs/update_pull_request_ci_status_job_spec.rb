# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdatePullRequestCiStatusJob, type: :job do
  include ActiveJob::TestHelper
  include LockingJobHelpers

  subject(:job) do
    described_class.new(
      pull_request_id: pull_request.id,
      refs_to_check: ["headcommitsha"],
    )
  end

  let(:pull_request) { FactoryBot.create(:pull_request) }

  let(:dummy_status_updater) do
    instance_double(UpdatePullRequestCiStatus, run: nil)
  end

  after do
    clear_job_locks(described_class)
  end

  it "delegates to the UpdatePullRequestCiStatus action" do
    expect(UpdatePullRequestCiStatus).
      to receive(:new).
      with(pull_request: pull_request, refs_to_check: ["headcommitsha"]).
      and_return(dummy_status_updater)
    expect(dummy_status_updater).to receive(:run)

    job.perform_now
  end

  it "can handle being given a PullRequest" do
    job = described_class.new(pull_request: pull_request, refs_to_check: ["headcommitsha"])

    expect(UpdatePullRequestCiStatus).
      to receive(:new).
      with(pull_request: pull_request, refs_to_check: ["headcommitsha"]).
      and_return(dummy_status_updater)
    expect(dummy_status_updater).to receive(:run)

    job.perform_now
  end

  it "can handle being given a PullRequest ID" do
    job = described_class.new(pull_request_id: pull_request.id, refs_to_check: ["headcommitsha"])

    expect(UpdatePullRequestCiStatus).
      to receive(:new).
      with(pull_request: pull_request, refs_to_check: ["headcommitsha"]).
      and_return(dummy_status_updater)
    expect(dummy_status_updater).to receive(:run)

    job.perform_now
  end

  it "retries transient twirp errors" do
    job = described_class.new(pull_request: pull_request, refs_to_check: ["headcommitsha"])

    expect(UpdatePullRequestCiStatus).
      to receive(:new).
      and_raise(
        GitHub::Twirp::DependabotPullRequests::TransientTwirpError.new(
          "test",
          Twirp::Error.internal("error"),
        )
      )
    expect { job.perform_now }.to have_enqueued_job(described_class)
  end

  it "retries transient twirp api response errors" do
    job = described_class.new(pull_request: pull_request, refs_to_check: ["headcommitsha"])

    expect(UpdatePullRequestCiStatus).
      to receive(:new).
      and_raise(
        GitHub::Twirp::DependabotPullRequests::TransientServiceError.new(
          "test",
          MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
            type: MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_UNEXPECTED_ERROR,
            message: "error"
          )
        )
      )
    expect { job.perform_now }.to have_enqueued_job(described_class)
  end

  it "only allows a single job to be enqueued at a time for a given pull request and set of refs" do
    expect do
      described_class.perform_later(pull_request_id: pull_request.id, refs_to_check: ["headcommitsha"])
      described_class.perform_later(pull_request_id: pull_request.id, refs_to_check: ["headcommitsha"])
    end.to change(enqueued_jobs, :size).by(1)

    expect do
      described_class.perform_later(pull_request_id: pull_request.id, refs_to_check: ["headcommitsha1"])
      described_class.perform_later(pull_request_id: pull_request.id, refs_to_check: ["headcommitsha2"])
    end.to change(enqueued_jobs, :size).by(2)
  end
end
