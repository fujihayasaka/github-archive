# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Gpt4EcosystemPackagePredictionJobTest < ActiveJob::TestCase
  include JobTestHelper

  def setup
    @advisory_review_id = 1
    @feed_entry_id = 1
    @rate_limit_error = CopilotAPI::Client::RateLimitError.new(retry_after: 1.0)
  end

  test "retry_rate_limit_error retries the job when max retries have not been reached" do
    job = Gpt4EcosystemPackagePredictionJob.new
    job.expects(:executions_for).with(@rate_limit_error).returns(AdvisoryDB::Config::Capi.max_retries - 1)
    job.expects(:retry_job)

    job.retry_rate_limit_error(@rate_limit_error)
  end

  test "retry_rate_limit_error raises the exception when max retries have been reached" do
    job = Gpt4EcosystemPackagePredictionJob.new
    job.expects(:executions_for).with(@rate_limit_error).returns(AdvisoryDB::Config::Capi.max_retries)

    assert_raises CopilotAPI::Client::RateLimitError do
      job.retry_rate_limit_error(@rate_limit_error)
    end
  end

  test "job retries when network error occurs" do
    assert_retry_on_error(CopilotAPI::Client::NetworkError, Gpt4EcosystemPackagePredictionJob, kwargs: { advisory_review_id: @advisory_review_id, feed_entry_id: @feed_entry_id })
  end

  test "perform creates a new AiPrediction and makes a prediction" do
    ai_model = "gpt-4o-2024-05-13"
    advisory_review = create(:advisory_review, summary: "this is a summary", description: "this is a description")
    ai_prediction = AiPrediction.new(
      advisory_review_id: advisory_review.id,
      feed_entry_id: advisory_review.feed_entries.first.id,
      review_state_at_prediction: "open",
      ai_model: ai_model,
    )

    AiPrediction.expects(:new).with(
      advisory_review_id: advisory_review.id,
      feed_entry_id: advisory_review.feed_entries.first.id,
      review_state_at_prediction: "open",
      ai_model: ai_model,
    ).returns(ai_prediction)

    ai_prediction.expects(:messages).returns([])
    CopilotAPI::Client.expects(:make_prediction)
      .with(model: ai_model, messages: [])
      .returns(FakeResponse.new({
        choices:
        [
          {
            finish_reason: "stop",
            index: 0,
            message: {
              content: "As the provided security advisory does not contain any specific information about the ecosystem or the package name, it''s impossible to accurately determine these details. However, for the sake of providing an answer, I''ll make an arbitrary selection.\n\nEcosystem: npm\nPackage name: seco-leveldown",
              role: "assistant",
            },
          },
        ],
        created: 1702593786,
        id: "chatcmpl-8Voi232Q3cvSt94oSLgLANWMr6xYJ",
        usage: {
          completion_tokens: 59,
          prompt_tokens: 381,
          total_tokens: 440,
        },
      }))

    Gpt4EcosystemPackagePredictionJob.perform_now(advisory_review_id: advisory_review.id, feed_entry_id: advisory_review.feed_entries.first.id)
  end

  test "perform saves description, summary, prompt and raw prediction output with gpt-4o" do
    advisory_review = create(:advisory_review, summary: "this is a summary", description: "this is a description")

    VCR.use_cassette("make_prediction_save_attributes_4o") do
      Gpt4EcosystemPackagePredictionJob.perform_now(advisory_review_id: advisory_review.id, feed_entry_id: @feed_entry_id)
      ai_prediction = AiPrediction.find_by(advisory_review_id: advisory_review.id)
      assert ai_prediction.summary, "this is a summary"
      assert ai_prediction.description, "this is a description"
      assert_includes ai_prediction.prompt, ai_prediction.summary
      assert_includes ai_prediction.prompt, ai_prediction.description
      refute_nil ai_prediction.raw_prediction_output
    end
  end

  class FakeResponse
    attr_accessor :body

    def initialize(body)
      @body = body
    end
  end
end
