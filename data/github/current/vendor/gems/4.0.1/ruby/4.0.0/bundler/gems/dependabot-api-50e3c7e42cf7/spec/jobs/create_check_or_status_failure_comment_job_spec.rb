# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateCheckOrStatusFailureCommentJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(pull_request: pull_request) }

  let(:pull_request) { FactoryBot.create(:pull_request) }

  let(:dummy_comment_creator) do
    instance_double(CreateCheckOrStatusFailureComment, run: nil)
  end

  it "delegates to the CreateCheckOrStatusFailureComment action" do
    expect(CreateCheckOrStatusFailureComment).
      to receive(:new).
      with(pull_request: pull_request).
      and_return(dummy_comment_creator)
    expect(dummy_comment_creator).to receive(:run)

    job.perform_now
  end

  it "retries transient twirp errors" do
    expect(CreateCheckOrStatusFailureComment).
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
    expect(CreateCheckOrStatusFailureComment).
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
end
