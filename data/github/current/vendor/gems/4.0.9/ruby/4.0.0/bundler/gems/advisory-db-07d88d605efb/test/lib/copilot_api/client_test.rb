# frozen_string_literal: true

require "test_helper"

class CopilotAPIClientTest < ActiveSupport::TestCase
  setup do
    CopilotAPI::Client.stubs(:enabled?).returns(true)
    AdvisoryDB::Features.stubs(:enabled?).returns(true)
  end

  test "can connect to copilot api for gpt-4o model" do
    payload = {
      model: "gpt-4o-2024-05-13",
      messages: [{ role: "user", content: "This is a prompt string" }],
      max_tokens: 7,
      temperature: 1.0,
      stop: [],
    }

    VCR.use_cassette("capi_make_prediction_gpt4o") do
      response = CopilotAPI::Client.make_prediction(**payload)
      assert response.status, 200
      # rubocop:disable Style/SafeNavigationChainLength
      assert response.body&.[]("choices")&.[](0)&.[]("message")&.[]("role"), "assistant"
      # rubocop:enable Style/SafeNavigationChainLength
    end
  end

  test "can make a *correct* prediction for ecosystem and package with gpt-4o model" do
    ai_prediction = create(:ai_prediction_gpt4o)
    payload = {
      model: "gpt-4o-2024-05-13",
      messages: [{ role: "system", content: ai_prediction.prediction_context }, { role: "user", content: ai_prediction.prompt }],
      max_tokens: 100,
      temperature: 0,
      stop: [],
    }

    VCR.use_cassette("capi_make_prediction_ecosystem_package_gpt4o") do
      response = CopilotAPI::Client.make_prediction(**payload)
      assert response.status, 200
      # rubocop:disable Style/SafeNavigationChainLength
      assert response.body&.[]("choices")&.[](0)&.[]("message")&.[]("role"), "assistant"
      assert response.body&.[]("choices")&.[](0)&.[]("message")&.[]("content"), "Ecosystem: NuGet\nPackage name: Microsoft.NETCore.AppMicrosoft.NETCore.App"
      # rubocop:enable Style/SafeNavigationChainLength
    end
  end
end
