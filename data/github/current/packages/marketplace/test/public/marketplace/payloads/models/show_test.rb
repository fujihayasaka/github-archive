# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Payloads::Models::ShowTest < GitHub::TestCase
  CONTENT_FIXTURE = {
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

  def payload(language: "python", sdk: "azure-ai-inference")
    getting_started_payload = Marketplace::Payloads::Models::Show.new(
      model_input_schema: nil,
      current_user: @user,
      model: Marketplace::Types::AzureModels::Static::GPT4o,
      miniplayground_icebreaker: nil
    )
    Marketplace::Payloads::Models::GettingStartedContent.stubs(:fetch).returns(CONTENT_FIXTURE)
    getting_started_payload
  end

  context "#call" do
    test "returns a hash with the getting started content" do
      result = payload.call
      assert_equal Marketplace::Types::AzureModels::Static::GPT4o, result[:model]

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
  end
end unless GitHub.enterprise?
