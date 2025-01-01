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
      params: ActionController::Parameters.new(params),
    )
    show_payload
  end

  def stub_models
    AzureModels::CatalogItem.stubs(:find_by).with(key: "all_models")
      .returns(AzureModels::CatalogItem.new(value: [GitHubModels::Types::Static::GPT4].to_json))
    AzureModels::CatalogItem.stubs(:find_by!).with(key: "azure-openai/gpt-4")
      .returns(AzureModels::CatalogItem.new(value: {
        model: GitHubModels::Types::Static::GPT4,
        schema: GitHubModels::Types::Static::GPT4_SCHEMA,
      }.to_json))

    GitHubModels::Payloads::GettingStartedContent.stubs(:fetch).returns(GETTING_STARTED)
  end

  context "#call" do
    test "returns a hash with the getting started content" do
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
        result = payload(params: { compare_to: "gpt-4" }).call

        assert_equal GitHubModels::Types::Static::GPT4, result[:comparedModelDetails][:catalogData]
        assert_equal GitHubModels::Types::Static::GPT4_SCHEMA, result[:comparedModelDetails][:modelInputSchema]
      end

      test "is nil if the compare_to param is invalid" do
        result = payload(params: { compare_to: "unknown-model" }).call

        assert_nil result[:comparedModelDetails]
      end
    end
  end
end unless GitHub.enterprise?
