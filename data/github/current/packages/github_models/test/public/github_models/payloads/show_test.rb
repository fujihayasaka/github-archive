# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::Payloads::ShowTest < GitHub::TestCase
  GETTING_STARTED = {
    "python": {
      "name": "Python",
      "sdks": {
        "azure-ai-inference": {
          "name": "Azure AI Inference SDK",
          "content": "I am markdown content",
          "code_sample": "I am a code sample",
        }
      }
    },
    "rest": {
      "name": "REST",
      "sdks": {
        "curl": {
          "name": "cURL",
          "content": "I am markdown content",
          "code_sample": "I am a code sample",
        }
      }
    }
  }

  fixtures do
    @user = create(:user)
  end

  setup do
    stub_models
  end

  def payload(language: "python", sdk: "azure-ai-inference", params: {})
    show_payload = GitHubModels::Payloads::Show.new(
      model_input_schema: nil,
      current_user: @user,
      model: GitHubModels::Types::Static::GPT4o,
      miniplayground_icebreaker: nil,
      prompt_extraction_code_snippet: "client.chat('You are an AI chatbot')",
      params: ActionController::Parameters.new(params),
      improved_prompt_model: GitHubModels::Types::Static::GPT4,
      prompt_extraction_model: GitHubModels::Types::Static::GPT4,
    )
    show_payload
  end

  def stub_models
    @model_gpt4o = create(:github_models_catalog_item, :gpt_4o)

    GitHubModels::Payloads::GettingStartedContent.stubs(:fetch).returns(GETTING_STARTED)
  end

  context "#call" do
    test "returns a hash with the getting started content" do
      disable_feature_flag(:github_models_dynamic_getting_started_content)
      result = payload.call
      assert_equal GitHubModels::Types::Static::GPT4o, result[:model]

      expected_toc = {
        "python": {
          name: "Python",
          sdks: {
            "azure-ai-inference": {
              name: "Azure AI Inference SDK",
              content: "<div class=\"markdown-body\"><p>I am markdown content</p></div>",
              tocHeadings: [],
              codeSamples: "I am a code sample",
            }
          }
        },
        "rest": {
          name: "REST",
          sdks: {
            "curl": {
              name: "cURL",
              content: "<div class=\"markdown-body\"><p>I am markdown content</p></div>",
              tocHeadings: [],
              codeSamples: "I am a code sample",
            }
          }
        }
      }
      assert_equal expected_toc, result[:gettingStarted]
    end

    context "comparedModelDetails" do
      test "is nil if the compare_to param is not present" do
        result = payload.call

        assert_nil result[:comparedModelDetails]
      end

      test "contains the model details if compare_to is a valid model name" do
        result = payload(params: { compare_to: "gpt-4o" }).call

        assert_equal @model_gpt4o.to_model, result[:comparedModelDetails][:catalogData]
        assert_equal @model_gpt4o.to_schema, result[:comparedModelDetails][:modelInputSchema]
      end

      test "is nil if the compare_to param is invalid" do
        result = payload(params: { compare_to: "unknown-model" }).call

        assert_nil result[:comparedModelDetails]
      end
    end
  end
end unless GitHub.enterprise?
