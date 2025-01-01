# typed: true
# frozen_string_literal: true

require "test_helper"

class Issue::CopilotSummarizerTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @author = create(:verified_user)
    @org.add_member(@author)
    @repo.add_member(@author)
    @issue = create(:issue, user: @author, repository: @repo, body: "This is a big bug.")
  end

  setup do
    @summarizer = Issue::CopilotSummarizer.new(issue: @issue)
  end

  context "ISSUE_SUMMARY_NEGATIVE_FEEDBACK_LABELS" do
    test "includes valid values" do
      refute_empty Issue::CopilotSummarizer::ISSUE_SUMMARY_NEGATIVE_FEEDBACK_LABELS
      Issue::CopilotSummarizer::ISSUE_SUMMARY_NEGATIVE_FEEDBACK_LABELS.each do |value, label|
        assert_includes Issue::CopilotSummarizer::ISSUE_SUMMARY_FEEDBACK_OPTIONS, value,
          "expected value to be a valid one for use in the Hydro enum"
        assert_predicate label, :present?, "expected to have a non-blank label for value #{value}"
      end
    end
  end

  context "#instrument_copilot_summary_feedback" do
    test "returns false when not given any feedback choices" do
      refute @summarizer.instrument_copilot_summary_feedback(actor: @author, feedback_choices: [])
      refute_hydro_messages(schema: "github.v1.GiveCopilotIssueSummaryFeedback")
    end

    test "emits Hydro event and returns true on success" do
      assert @summarizer.instrument_copilot_summary_feedback(actor: @author,
        feedback_choices: %w(INCORRECT UNHELPFUL))

      assert_hydro_messages(count: 1, schema: "github.v1.GiveCopilotIssueSummaryFeedback")
      assert_hydro_published({
        analytics_tracking_id: @author.analytics_tracking_id,
        feedback_choice: %w(INCORRECT UNHELPFUL),
        feedback: nil,
        repository_id: @repo.id,
        organization_id: @org.id,
        header_request_id: nil,
        prompt_version: Issue::CopilotSummarizer::USER_PROMPT_VERSION,
      }, schema: "github.v1.GiveCopilotIssueSummaryFeedback")
    end

    test "returns false when given an invalid feedback choice" do
      refute @summarizer.instrument_copilot_summary_feedback(actor: @author,
        feedback_choices: %w(INCORRECT SOME_RANDOM_VALUE))
      refute_hydro_messages(schema: "github.v1.GiveCopilotIssueSummaryFeedback")
    end
  end

  context "#summarize" do
    test "emits Hydro event" do
      capi_response = {
        choices: [
          {
            message: { role: "assistant", content: "this is a fake issue summary" },
            content_filter_results: {},
            finish_reason: "stop",
            index: 0,
          }
        ],
        created: 123,
        usage: {},
        prompt_filter_results: [{}],
        id: "123",
        model: "gpt-3.5-turbo-0613",
        copilot_references: [{}],
      }.with_indifferent_access
      Copilot::User::CopilotApi.any_instance.expects(:summarize).once
        .with(references: [@summarizer.copilot_api_reference], custom_prompt: nil,
          default_prompt: Issue::CopilotSummarizer::USER_PROMPT).returns(capi_response)

      @summarizer.summarize(actor: @author, token: Copilot::EncryptedToken.from("foo"))

      assert_hydro_messages(count: 1, schema: "github.v1.CopilotSummarizeIssue")
      assert_hydro_published({
        analytics_tracking_id: @author.analytics_tracking_id,
        repository_id: @repo.id,
        organization_id: @org.id,
      }, schema: "github.v1.CopilotSummarizeIssue")
    end

    test "passes along custom prompt when given" do
      capi_response = {
        choices: [
          {
            message: { role: "assistant", content: "this is a fake issue summary" },
            content_filter_results: {},
            finish_reason: "stop",
            index: 0,
          }
        ],
        created: 123,
        usage: {},
        prompt_filter_results: [{}],
        id: "123",
        model: "gpt-3.5-turbo-0613",
        copilot_references: [{}],
      }.with_indifferent_access
      prompt = "You're in a desert, walking along in the sand, when all of a sudden you look down and see a tortoise."

      Copilot::User::CopilotApi.any_instance.expects(:summarize).once
        .with(references: [@summarizer.copilot_api_reference], custom_prompt: prompt,
          default_prompt: Issue::CopilotSummarizer::USER_PROMPT).returns(capi_response)

      @summarizer.summarize(actor: @author, token: Copilot::EncryptedToken.from("foo"), prompt: prompt)
    end

    test "counts token usage" do
      model = "gpt-3.5-turbo-0613"
      capi_response = {
        "choices": [{
          "content_filter_results": {},
          "finish_reason": "stop",
          "index": 0,
          "message": { "content": "Some summary", "padding": "", "role": "assistant" }
        }],
        "copilot_references": [{
          "type": "github.issue",
          "data": {
            "id": 123,
            "number": 0,
            "repository": { "id": 0, "name": "", "owner": "" },
            "body": "Some issue body",
            "authorLogin": "monalisa",
            "comments": [],
            "type": "issue",
          },
          "id": "6887326",
          "metadata": { "display_name": "", "display_icon": "" },
        }],
        "created": 1723153009,
        "id": "123",
        "model": model,
        "prompt_filter_results": [{ "content_filter_results": {}, "prompt_index": 0 }],
        "usage": { "completion_tokens": 118, "prompt_tokens": 3294, "total_tokens": 3412 },
      }.with_indifferent_access

      Copilot::User::CopilotApi.any_instance.expects(:summarize).once
        .with(references: [@summarizer.copilot_api_reference], custom_prompt: nil,
          default_prompt: Issue::CopilotSummarizer::USER_PROMPT).returns(capi_response)

      @summarizer.summarize(actor: @author, token: Copilot::EncryptedToken.from("foo"))

      assert_dogstats_distribution_value 118, "issues.copilot.summarize.tokens_used",
        tags: ["model:#{model}", "usage_type:completion"]
      assert_dogstats_distribution_value 3294, "issues.copilot.summarize.tokens_used",
        tags: ["model:#{model}", "usage_type:prompt"]
    end
  end

  context "#copilot_api_reference" do
    test "returns a hash representing a reference we can send to CAPI that includes the issue data" do
      expected = {
        type: "github.issue",
        id: "#{@issue.id}",
        data: @summarizer.copilot_api_reference_data,
      }
      assert_equal expected, @summarizer.copilot_api_reference
    end
  end

  context "#copilot_api_reference_data" do
    test "returns a hash representing the issue for use within a CAPI reference" do
      expected = {
        type: "issue",
        id: @issue.id,
        number: @issue.number,
        repo: { id: @repo.id, name: @repo.name, owner: @repo.owner_display_login },
        title: @issue.title,
        body: @issue.body,
        state: @issue.state,
        authorLogin: @author.display_login,
      }
      assert_equal expected, @summarizer.copilot_api_reference_data
    end

    test "strips images and links from issue body" do
      @issue.body = "This is a [great](https://zombo.com) website! Please look:\n" \
        "<img src='some_file.png' alt='Magical views'>\n" \
        "![a user avatar](https://github.com/username.png) ![](/some-image-without-alt-text.jpeg)"

      actual = @summarizer.copilot_api_reference_data

      assert_equal "This is a great website! Please look:\nMagical views\na user avatar", actual[:body]
    end
  end
end
