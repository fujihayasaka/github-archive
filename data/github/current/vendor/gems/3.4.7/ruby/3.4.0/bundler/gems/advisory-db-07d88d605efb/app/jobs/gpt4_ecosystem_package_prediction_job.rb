# frozen_string_literal: true

# This job processes GPT4 Prediction via CAPI (copilot API)
class Gpt4EcosystemPackagePredictionJob < ApplicationJob
  queue_as :high
  rescue_from(CopilotAPI::Client::RateLimitError, with: :retry_rate_limit_error)
  retry_on(CopilotAPI::Client::NetworkError, queue: :high, wait: :polynomially_longer, attempts: 2)

  def perform(advisory_review_id:, feed_entry_id:)
    return if AiPrediction.find_by(advisory_review_id: advisory_review_id)

    ai_model = "gpt-4o-2024-05-13"
    ai_prediction = AiPrediction.new(
      advisory_review_id: advisory_review_id,
      feed_entry_id: feed_entry_id,
      review_state_at_prediction: "open",
      ai_model: ai_model,
    )

    raw_res = CopilotAPI::Client.make_prediction(model: ai_prediction.ai_model, messages: ai_prediction.messages)

    # e.g. predicted_string = "Ecosystem: NuGet\nPackage name: Microsoft.NETCore.App"
    # rubocop:disable Style/SafeNavigationChainLength
    predicted_string = raw_res.body&.[]("choices")&.[](0)&.[]("message")&.[]("content")
    raw_predicted_ecosystems, raw_predicted_package_names = predicted_string&.split("\n")
    raw_predicted_ecosystems = raw_predicted_ecosystems&.split&.last&.strip
    raw_predicted_package_names = raw_predicted_package_names&.split&.last&.strip
    # rubocop:enable Style/SafeNavigationChainLength
    ai_prediction.raw_prediction_output = predicted_string
    ai_prediction.process_ecosystem_prediction(raw_predicted_ecosystems)
    ai_prediction.process_package_prediction(raw_predicted_ecosystems, raw_predicted_package_names)
    ai_prediction.save!
  end

  def retry_rate_limit_error(exception)
    executions = executions_for(exception)
    if executions >= AdvisoryDB::Config::Capi.max_retries
      raise exception
    else
      retry_header = exception.retry_after # header
      wait = retry_header.is_a?(Float) && retry_header > 0 ? retry_header : 2.0
      retry_job wait:, error: exception
    end
  end
end
