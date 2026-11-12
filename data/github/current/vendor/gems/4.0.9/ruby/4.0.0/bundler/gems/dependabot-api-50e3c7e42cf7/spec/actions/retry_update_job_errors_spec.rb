# frozen_string_literal: true

require "rails_helper"

RSpec.describe RetryUpdateJobErrors do
  include ActiveSupport::Testing::TimeHelpers

  subject(:retry_errors) { described_class.new(start_time: start_time, end_time: end_time, error_type: error_type) }

  let(:runner_error) do
    FactoryBot.create(:update_job_error, error_type: "runner_error", created_at: "2021-06-01 00:01")
  end
  let(:dependency_file_not_evaluatable_error) do
    FactoryBot.create(:update_job_error, error_type:
                          "dependency_file_not_evaluatable",
                                         created_at: "2021-06-01 00:01")
  end
  let(:old_runner_error) do
    FactoryBot.create(:update_job_error, error_type: "runner_error", created_at: "2021-05-21 00:01")
  end

  let(:start_time) { DateTime.parse("2021-06-01 00:00") }
  let(:end_time) { DateTime.parse("2021-06-01 01:00") }
  let(:error_type) { "runner_error" }

  before do
    travel_to Time.parse("2021-06-01 00:00 +0000").utc

    [runner_error, dependency_file_not_evaluatable_error, old_runner_error].each do |err|
      err.update_job.transition_to!(:enqueued)
      err.update_job.transition_to!(:processing)
      err.update_job.transition_to!(:processed_with_errors, errors: { err.error_type => err.error_details })
    end
  end

  it "retries update jobs that have an update_job_error associated with it" do
    expect { retry_errors.run }.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
      with(runner_error.update_job)
  end

  it "does not retry jobs for other error types than specified" do
    expect { retry_errors.run }.not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
      with(dependency_file_not_evaluatable_error.update_job)
  end

  it "does not retry jobs for errors outside the specified time range" do
    expect { retry_errors.run }.not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
      with(old_runner_error.update_job)
  end
end
