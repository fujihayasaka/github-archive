# frozen_string_literal: true

require "rails_helper"

RSpec.describe CheckRepoHasCiJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(repo: repo) }

  let(:repo) { create(:repo) }
  let(:dummy_tester) { instance_double(CheckRepoHasCi, run: nil) }

  before do
    allow(CheckRepoHasCi).
      to receive(:new).
      with(repo: repo).
      and_return(dummy_tester)
  end

  it "delegates to CheckRepoHasCi" do
    expect(dummy_tester).to receive(:run)
    job.perform_now
  end

  it "includes repository telemetry attributes in the exception context" do
    expect(dummy_tester).to receive(:run).and_raise("test error")
    expect(Dependabot::Exceptions).to(
      receive(:with_failbot_context).
      with(array_including(Dependabot::Sentry.tag_indexed_telemetry_attributes(repo.telemetry_attributes)))
    )

    expect { job.perform_now }.to raise_error("test error")
  end

  it "retries on GraphQL rate limiting" do
    expect(dummy_tester).to receive(:run).and_raise(GitHubGraphQL::RateLimited)
    expect { job.perform_now }.to have_enqueued_job(described_class).with(repo: repo)
  end
end
