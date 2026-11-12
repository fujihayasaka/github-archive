# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateAutofixAnnotationJob, type: :job do
  include ActiveJob::TestHelper

  let(:twirp_autofix_client) do
    instance_double(
      GitHub::Twirp::Autofix,
      create_suggested_fix_annotation: nil
    )
  end

  let(:autofix_suggestion_job) { create(:autofix_suggestion_job) }

  before do
    allow(MetricsClient).to receive(:increment)
    allow(Dependabot::Application).to receive(:autofix_client).and_return(twirp_autofix_client)

    allow(autofix_suggestion_job).to receive(:complete_github_check_run)
    allow(AutofixSuggestionJob).to receive(:find).and_wrap_original do |m, *args|
      next autofix_suggestion_job if args[0] == autofix_suggestion_job.id

      m.call(*args)
    end
  end

  it "sends a twirp request to dotcom" do
    expect(twirp_autofix_client).to receive(:create_suggested_fix_annotation).with(autofix_suggestion_job)

    described_class.perform_now(autofix_suggestion_job_id: autofix_suggestion_job.id)
  end

  it "observes the create annotation stage" do
    # in order to set an expectation on the test object we need to
    # also stub the DB lookup to return this exact object
    allow(AutofixSuggestionJob).to receive(:find).
      with(autofix_suggestion_job.id).
      and_return(autofix_suggestion_job)
    expect(autofix_suggestion_job).to receive(:observe_stage).
      with(stage: AutofixSuggestionJob::Stages::CREATE_ANNOTATION)

    described_class.perform_now(autofix_suggestion_job_id: autofix_suggestion_job.id)
  end

  it "records a stage success" do
    allow(twirp_autofix_client).to receive(:create_suggested_fix_annotation).with(autofix_suggestion_job)
    expect(AutofixSuggestionJob::Stages).not_to receive(:record_error).with(
      hash_including(stage: AutofixSuggestionJob::Stages::CREATE_ANNOTATION)
    )
    expect(AutofixSuggestionJob::Stages).to receive(:record_success).with(
      hash_including(stage: AutofixSuggestionJob::Stages::CREATE_ANNOTATION)
    )

    described_class.perform_now(autofix_suggestion_job_id: autofix_suggestion_job.id)
  end

  it "marks the job's github check run as successful" do
    described_class.perform_now(autofix_suggestion_job_id: autofix_suggestion_job.id)
    expect(autofix_suggestion_job).to have_received(:complete_github_check_run).with(
      conclusion: GitHub::CheckRun::Conclusion::SUCCESS
    )
  end

  it "marks the job's github check run as failed if creating the annotation fails" do
    allow(twirp_autofix_client).to receive(:create_suggested_fix_annotation).
      and_raise(RuntimeError.new("test"))
    expect do
      described_class.perform_now(autofix_suggestion_job_id: autofix_suggestion_job.id)
    end.to raise_error("test")
    expect(autofix_suggestion_job).to have_received(:complete_github_check_run).with(
      conclusion: GitHub::CheckRun::Conclusion::FAILURE
    )
  end

  it "raises an error if the autofix job cannot be found" do
    expect(twirp_autofix_client).not_to receive(:create_suggested_fix_annotation)
    expect(AutofixSuggestionJob::Stages).to receive(:record_error).with(
      hash_including(stage: AutofixSuggestionJob::Stages::CREATE_ANNOTATION)
    )
    expect(AutofixSuggestionJob::Stages).not_to receive(:record_success)

    expect { described_class.perform_now(autofix_suggestion_job_id: autofix_suggestion_job.id + 1000) }.
      to raise_error(CreateAutofixAnnotationJob::MissingAutofixSuggestionJobError)
  end
end
