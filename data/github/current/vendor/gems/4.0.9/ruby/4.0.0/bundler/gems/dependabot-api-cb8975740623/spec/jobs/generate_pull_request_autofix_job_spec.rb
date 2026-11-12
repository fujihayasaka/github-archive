# frozen_string_literal: true

require "rails_helper"

RSpec.describe GeneratePullRequestAutofixJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(autofix_job: autofix_job)
  end

  let(:autofix_job) { FactoryBot.create(:autofix_suggestion_job) }

  let(:dummy_generator) do
    instance_double(GeneratePullRequestAutofix, run: nil)
  end

  before do
    allow(GeneratePullRequestAutofix).
      to receive(:new).
      with(autofix_job: autofix_job).
      and_return(dummy_generator)

    allow(AutofixSuggestionJob).to receive(:find).and_return(autofix_job)
    allow(autofix_job).to receive(:complete_github_check_run)
  end

  it "delegates to the GeneratePullRequestAutoFix action" do
    expect(dummy_generator).to receive(:run)
    job.perform_now
  end

  GeneratePullRequestAutofix::FETCH_JOB_LOG_RETRY_ERRORS.each do |err_class|
    it "retries #{err_class.name} errors" do
      allow(dummy_generator).to receive(:run).and_raise(err_class.new(nil))
      expect { job.perform_now }.to enqueue_job(described_class)
    end

    it "does not raise #{err_class.name} errors after exhausting retries" do
      allow(dummy_generator).to receive(:run).and_raise(err_class.new(nil))
      expect { perform_enqueued_jobs { job.perform_now } }.not_to raise_error
    end
  end

  it "marks the job's check run as failed if the job fails" do
    allow(dummy_generator).to receive(:run).and_raise(RuntimeError.new("err"))
    expect(autofix_job).to receive(:complete_github_check_run).with(
      conclusion: GitHub::CheckRun::Conclusion::FAILURE
    )

    expect { job.perform_now }.to raise_error("err")
  end
end
