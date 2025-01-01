# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotSummaryAgentResponseTest < GitHub::TestCase
  fixtures do
    @staff_user = create(:user, :employee)
  end

  test "creates a CopilotSummaryAgentResponse from a CopilotApi response hash" do
    summary_response = CopilotSummaryAgentResponse.from(capi_response)

    assert_instance_of CopilotSummaryAgentResponse, summary_response
    assert_instance_of CopilotSummaryAgentResponse::Choice, summary_response.choices.first
    assert_instance_of CopilotSummaryAgentResponse::CopilotChatMessage, summary_response.choices.first&.message
  end

  context "#completion_token_usage" do
    test "returns completion tokens used" do
      summary_response = CopilotSummaryAgentResponse.from(capi_response.merge(usage: { completion_tokens: 118 }))
      assert_equal 118, summary_response.completion_token_usage
    end
  end

  context "#prompt_token_usage" do
    test "returns prompt tokens used" do
      summary_response = CopilotSummaryAgentResponse.from(capi_response.merge(usage: { prompt_tokens: 3294 }))
      assert_equal 3294, summary_response.prompt_token_usage
    end
  end

  context "#total_token_usage" do
    test "returns total tokens used" do
      summary_response = CopilotSummaryAgentResponse.from(capi_response.merge(usage: { total_tokens: 3412 }))
      assert_equal 3412, summary_response.total_token_usage
    end
  end

  context "#summary" do
    test "returns the content of the first choice" do
      choice = {
        message: { role: "assistant", content: "this is a fake discussion summary" },
        content_filter_results: {},
        finish_reason: "stop",
        index: 0,
      }

      summary_response = CopilotSummaryAgentResponse.from(capi_response.merge(choices: [choice]))

      assert_equal "this is a fake discussion summary", summary_response.summary
    end

    test "returns nil if there are no choices" do
      summary_response = CopilotSummaryAgentResponse.from(capi_response.merge(choices: []))
      assert_nil summary_response.summary
    end
  end

  context "#summary_html" do
    test "returns the summary as html" do
      summary_response = CopilotSummaryAgentResponse.from(capi_response)

      summary_html = summary_response.summary_html(viewer: nil)
      assert_equal "<p>Some summary</p>", summary_html
      refute_includes "<!-- copilot-api response:", summary_html
    end

    test "does not include raw json html comment for non-staff user" do
      user = create(:user)
      user.enable_feature(:copilot_summary_custom_prompt)

      summary_response = CopilotSummaryAgentResponse.from(capi_response)

      summary_html = summary_response.summary_html(viewer: @staff_user)
      assert_includes "<p>Some summary</p>", summary_html
      refute_includes "<!-- copilot-api response:", summary_html
    end

    test "does not include raw json html comment for staff when feature flag disabled", skip_enterprise: true, skip_with_all_emus: true do
      @staff_user.disable_feature(:copilot_summary_custom_prompt)
      summary_response = CopilotSummaryAgentResponse.from(capi_response)

      summary_html = summary_response.summary_html(viewer: @staff_user)
      assert_includes "<p>Some summary</p>", summary_html
      refute_includes "<!-- copilot-api response:", summary_html
    end

    test "includes raw json html comment for staff in feature flag", skip_enterprise: true, skip_with_all_emus: true do
      @staff_user.enable_feature(:copilot_summary_custom_prompt)

      summary_response = CopilotSummaryAgentResponse.from(capi_response)

      summary_html = summary_response.summary_html(viewer: @staff_user)
      assert_includes summary_html, "<p>Some summary</p>"
      assert_includes summary_html, "<!-- copilot-api response:"
    end

    test "escapes malicious content", skip_enterprise: true, skip_with_all_emus: true do
      @staff_user.enable_feature(:copilot_summary_custom_prompt)

      choices = [
        {
          message: { role: "assistant", content: "<script>alert('foo')</script>" },
          content_filter_results: {},
          finish_reason: "stop",
          index: 0,
        }
      ]

      summary_response = CopilotSummaryAgentResponse.from(capi_response.merge(choices: choices))

      summary_html = summary_response.summary_html(viewer: @staff_user)
      assert_includes summary_html, "<!-- copilot-api response:"
      refute_includes summary_html, "<script>alert('foo')</script>"
      assert_includes summary_html, "&lt;script&gt;alert(&#39;foo&#39;)&lt;/script&gt;"
    end
  end

  private

  def capi_response
    {
      "choices": [{
        "content_filter_results": {
          "error": { "code": "", "message": "" },
          "hate": { "filtered": false, "severity": "safe" },
          "self_harm": { "filtered": false, "severity": "safe" },
          "sexual": { "filtered": false, "severity": "safe" },
          "violence": { "filtered": false, "severity": "safe" },
        },
        "finish_reason": "stop",
        "index": 0,
        "message": { "content": "Some summary", "padding": "", "role": "assistant" }
      }],
      "copilot_references": [{
        "type": "github.discussion",
        "data": {
          "id": 123,
          "number": 0,
          "repository": { "id": 0, "name": "", "owner": "" },
          "body": "Some discussion body",
          "authorLogin": "monalisa",
          "totalUpvotes": 1,
          "comments": [{
            "author": "monalisa",
            "createdAt": "2024-07-10T23:51:37Z",
            "body": "Some comment",
            "totalUpvotes": 1,
            "reactionCounts": [{ "reaction": "+1", "count": 5 }],
          }],
          "type": "discussion",
        },
        "id": "6887326",
        "metadata": { "display_name": "", "display_icon": "" },
      }],
      "created": 1723153009,
      "id": "123",
      "model": "gpt-3.5-turbo-0613",
      "prompt_filter_results": [{
        "content_filter_results": {
          "error": { "code": "", "message": "" },
          "hate": { "filtered": false, "severity": "safe" },
          "self_harm": { "filtered": false, "severity": "safe" },
          "sexual": { "filtered": false, "severity": "safe" },
          "violence": { "filtered": false, "severity": "safe" },
        },
        "prompt_index": 0
      }],
      "usage": { "completion_tokens": 118, "prompt_tokens": 3294, "total_tokens": 3412 },
    }.with_indifferent_access
  end
end
