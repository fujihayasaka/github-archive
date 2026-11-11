# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandlePullRequestCommentJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(
      action: "HandleWebhook::IssueComment::HandleRebaseRequest",
      requester_id: requester_id,
      args: [],
      keyword_args: { pull_request: pull_request,
                      requester: requester,
                      comment_id: comment_id,
                      comment_type: comment_type, },
    )
  end

  let(:requester_id) { 123 }
  let(:requester) { "jurre" }
  let(:pull_request) { FactoryBot.create(:pull_request) }
  let(:comment_id) { "123" }
  let(:comment_type) { "issue_comment" }

  let(:dummy_handler) do
    instance_double(HandleWebhook::IssueComment::HandleRebaseRequest, run: nil)
  end

  it "delegates to the HandleRebaseRequest action" do
    expect(HandleWebhook::IssueComment::HandleRebaseRequest).
      to receive(:new).
      with(pull_request: pull_request, requester: requester, comment_id: comment_id, comment_type: comment_type).
      and_return(dummy_handler)
    expect(dummy_handler).to receive(:run)

    job.perform_now
  end

  it "records a trace" do
    allow(HandleWebhook::IssueComment::HandleRebaseRequest).
      to receive(:new).
      with(pull_request: pull_request, requester: requester, comment_id: comment_id, comment_type: comment_type).
      and_return(dummy_handler)

    allow(job.tracer).to receive(:in_span).and_call_original
    job.perform_now
    expect(job.tracer).to have_received(:in_span).with(
      "HandlePullRequestCommentJob#perform",
      attributes: {
        "gh.dependabot_api.pull_request_event.action_name" => "HandleWebhook::IssueComment::HandleRebaseRequest",
        "gh.actor.id" => 123,
        "gh.comment.id" => "123",
      }
    )
  end

  it "uses valid telemetry attributes" do
    allow(HandleWebhook::IssueComment::HandleRebaseRequest).
      to receive(:new).
      with(pull_request: pull_request, requester: requester, comment_id: comment_id, comment_type: comment_type).
      and_return(dummy_handler)

    allow(job.tracer).to receive(:in_span).and_call_original
    job.perform_now
    expect(job.tracer).to have_received(:in_span) do |_name, opts|
      expect { Dependabot::Telemetry.validate_tracer_attributes!(opts[:attributes]) }.not_to raise_error
    end
  end

  it "retries transient twirp errors" do
    expect(HandleWebhook::IssueComment::HandleRebaseRequest).
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
    expect(HandleWebhook::IssueComment::HandleRebaseRequest).
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
