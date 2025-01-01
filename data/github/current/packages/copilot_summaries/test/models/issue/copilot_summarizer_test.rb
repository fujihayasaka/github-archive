# typed: true
# frozen_string_literal: true

require "test_helper"

class Issue::CopilotSummarizerTest < GitHub::TestCase
  include CopilotPublicUserCacheable
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @author = create(:verified_user)
    @org.add_member(@author)
    @repo.add_member(@author)
    @issue = create(:issue, user: @author, repository: @repo,
      body: "a" * CopilotThreadSummarizer::MIN_CHAR_COUNT_FOR_SUMMARIZING)
  end

  setup do
    @summarizer = Issue::CopilotSummarizer.new(issue: @issue, actor: @author)
  end

  context ".async_can_be_summarized? and .can_be_summarized?" do
    test "returns false for anonymous viewer" do
      GitHub.flipper[:issues_copilot_summary].enable

      refute Issue::CopilotSummarizer.can_be_summarized?(issue: @issue, viewer: nil)
      refute Issue::CopilotSummarizer.async_can_be_summarized?(issue: @issue, viewer: nil).sync
    end

    test "returns false for viewer without Copilot access" do
      refute_predicate Copilot::User.new(@author), :has_copilot_access?, "need a user without Copilot"
      @author.enable_feature(:issues_copilot_summary)

      refute Issue::CopilotSummarizer.can_be_summarized?(issue: @issue, viewer: @author)
      refute Issue::CopilotSummarizer.async_can_be_summarized?(issue: @issue, viewer: @author).sync
    end

    test "returns false when feature is disabled" do
      user = create(:copilot_feature_enabled_seat).assigned_user
      GitHub.flipper[:issues_copilot_summary].disable

      refute Issue::CopilotSummarizer.can_be_summarized?(issue: @issue, viewer: user)
      refute Issue::CopilotSummarizer.async_can_be_summarized?(issue: @issue, viewer: user).sync
    end

    test "returns true for viewer with Copilot when feature is generally available" do
      user = create(:copilot_feature_enabled_seat).assigned_user
      user.enable_feature(:issues_copilot_summary)
      user.enable_feature(:copilot_summary_ga)

      assert Issue::CopilotSummarizer.can_be_summarized?(issue: @issue, viewer: user)
      assert Issue::CopilotSummarizer.async_can_be_summarized?(issue: @issue, viewer: user).sync
    end

    test "returns true for viewer with Copilot through their org when feature is enabled and beta features are enabled" do
      org = create(:copilot_feature_enabled_enterprise_organization, :copilot_plan_enterprise)
      Copilot::Business.new(org.business).beta_features_github_chat_enable!
      user = create(:copilot_feature_enabled_seat, organization: org).assigned_user
      user.enable_feature(:issues_copilot_summary)
      GitHub.flipper[:copilot_summary_ga].disable

      assert Issue::CopilotSummarizer.can_be_summarized?(issue: @issue, viewer: user)
      assert Issue::CopilotSummarizer.async_can_be_summarized?(issue: @issue, viewer: user).sync
    end

    test "returns false when issue is too short for summarizing" do
      @issue.update!(body: "too short")
      user = create(:copilot_feature_enabled_seat).assigned_user
      user.enable_feature(:issues_copilot_summary)

      refute Issue::CopilotSummarizer.can_be_summarized?(issue: @issue, viewer: user)
      refute Issue::CopilotSummarizer.async_can_be_summarized?(issue: @issue, viewer: user).sync
    end

    test "limits queries per table" do
      issue_body = "not long enough on its own to summarize"
      @issue.update!(body: issue_body)
      remaining_chars = CopilotThreadSummarizer::MIN_CHAR_COUNT_FOR_SUMMARIZING - issue_body.size
      create(:issue_comment, issue: @issue, repository: @repo, body: "a" * remaining_chars)
      @author.enable_feature(:issues_copilot_summary)

      assert_query_count_per_table({
        "abilities" => 6,
        "business_organization_memberships" => 1,
        "business_user_accounts" => 1,
        "copilot_administrative_blocks" => 1,
        "copilot_complimentary_users" => TestEnv.test_all_features? ? 2 : 1,
        "copilot_seat_assignments" => 3,
        "copilot_seats" => 3,
        "issue_comments" => 1,
        "subscription_items" => 1,
        "users" => 1,
      }) do
        Issue::CopilotSummarizer.async_can_be_summarized?(issue: @issue, viewer: @author).sync
      end
    end
  end

  context "#body_length" do
    test "returns length of rendered issue body" do
      assert_empty @issue.comments, "need an issue with no comments"
      @issue.body = '<p>hello <img src="image-that-will-be-stripped.png"></p>'

      assert_equal "hello".length, @summarizer.body_length
    end
  end

  context "#comment_bodies_length" do
    test "returns length of rendered comment bodies" do
      comment1_body = "Hello world"
      comment2_body = 'Please consider <a href="/some/url/that/will/be/removed">my link</a>'
      comment1 = create(:issue_comment, issue: @issue, repository: @repo, body: comment1_body)
      comment2 = create(:issue_comment, issue: @issue, repository: @repo, body: comment2_body)
      assert_same_elements [comment1, comment2], @issue.reload.comments

      assert_equal "Hello worldPlease consider my link".length, @summarizer.comment_bodies_length
    end
  end

  context ".feature_enabled?" do
    test "returns true when user is explicitly in the flag" do
      @author.enable_feature(:issues_copilot_summary)
      assert Issue::CopilotSummarizer.feature_enabled?(viewer: @author)
    end

    test "returns false when flag is fully disabled" do
      GitHub.flipper[:issues_copilot_summary].disable
      refute Issue::CopilotSummarizer.feature_enabled?(viewer: @author)
    end

    test "returns true when user belongs to an org in the feature flag" do
      @org.enable_feature(:issues_copilot_summary)
      assert Issue::CopilotSummarizer.feature_enabled?(viewer: @author)
    end
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
      refute @summarizer.instrument_copilot_summary_feedback(feedback_choices: [])
      refute_hydro_messages(schema: "github.v1.GiveCopilotIssueSummaryFeedback")
    end

    test "emits Hydro event and returns true on success" do
      assert @summarizer.instrument_copilot_summary_feedback(feedback_choices: %w(INCORRECT UNHELPFUL))

      assert_hydro_messages(count: 1, schema: "github.v1.GiveCopilotIssueSummaryFeedback")
      assert_hydro_published({
        analytics_tracking_id: @author.analytics_tracking_id,
        feedback_choice: %w(INCORRECT UNHELPFUL),
        feedback: nil,
        repository_id: @repo.id,
        organization_id: @org.id,
        header_request_id: nil,
        prompt_version: Issue::CopilotSummarizer::USER_PROMPT_VERSION,
        github_revision: GitHub.current_sha,
      }, schema: "github.v1.GiveCopilotIssueSummaryFeedback")
    end

    test "returns false when given an invalid feedback choice" do
      refute @summarizer.instrument_copilot_summary_feedback(feedback_choices: %w(INCORRECT SOME_RANDOM_VALUE))
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

      @summarizer.summarize

      assert_hydro_messages(count: 1, schema: "github.v1.CopilotSummarizeIssue")
      assert_hydro_published({
        analytics_tracking_id: @author.analytics_tracking_id,
        repository_id: @repo.id,
        organization_id: @org.id,
        body_length: @summarizer.body_length,
        comment_bodies_length: @summarizer.comment_bodies_length,
        comments_count: @summarizer.comments_count,
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

      @summarizer.summarize(prompt: prompt)
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

      @summarizer.summarize

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
      body_markdown = <<~MARKDOWN
        This is a [great](https://zombo.com) website! Please look. <!-- some secret message -->
      MARKDOWN
      @issue.update!(body: body_markdown)
      GitHub.flipper[:issue_types].enable
      issue_type = create(:issue_type, name: "Task_#{SecureRandom.hex(4)}", owner: @org) # Ensure unique name

      reaction = create(:issue_reaction, issue: @issue)
      label_o = create(:label, repository: @repo, name: "Omeluum", description: "Our favorite mind flayer")
      label_b = create(:label, repository: @repo, name: "Blurg", description: nil)
      @issue.add_labels([label_o, label_b])

      sub_issue1 = travel_to(1.minute.ago) do # make sure sub-issues have different creation times
        create(:issue, repository: @repo, user: @author)
      end
      sub_issue1.update!(issue_type: issue_type) # set issue type on one sub-issue but not the other
      sub_issue2 = create(:issue, repository: @repo, user: @author)
      @issue.add_sub_issue!(sub_issue1, @author.id)
      @issue.add_sub_issue!(sub_issue2, @author.id)

      @issue.update!(issue_type: issue_type) # set issue type on top-level issue

      # This is specifically validating the context parameter is passed with the expected value
      expected_body = "This is a great website! Please look."
      GitHub::Goomba::CopilotSummaryInputPipeline.expects(:to_text).with(@issue.body, { entity: @repo }, nil).returns(expected_body).once

      expected = {
        type: "issue",
        id: @issue.id,
        number: @issue.number,
        repository: { id: @repo.id, name: @repo.name, owner: @repo.owner_display_login },
        title: @issue.title,
        body: expected_body,
        state: @issue.state,
        authorLogin: @author.display_login,
        comments: [],
        reactionCounts: [{ reaction: reaction.content, count: 1 }],
        labels: [
          { name: "Blurg", description: nil },
          { name: "Omeluum", description: "Our favorite mind flayer" },
        ],
        subIssues: [
          {
            title: sub_issue1.title,
            url: sub_issue1.url,
            labels: sub_issue1.labels.map { |label| { name: label.name, description: label.description } },
            issueType: { name: issue_type.name, description: issue_type.description },
          },
          {
            title: sub_issue2.title,
            url: sub_issue2.url,
            labels: sub_issue2.labels.map { |label| { name: label.name, description: label.description } },
          },
        ],
        issueType: { name: issue_type.name, description: issue_type.description },
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

    test "includes all comments when the issue has within the limit" do
      comment1 = create(:issue_comment, issue: @issue, repository: @repo, body: "Oldest comment")
      comment2 = create(:issue_comment, issue: @issue, repository: @repo, body: "Second comment")

      expected = {
        type: "issue",
        id: @issue.id,
        number: @issue.number,
        repository: { id: @repo.id, name: @repo.name, owner: @repo.owner_display_login },
        title: @issue.title,
        body: @issue.body,
        authorLogin: @author.display_login,
        state: "open",
        comments: [comment1, comment2].map do |comment|
          IssueComment::CopilotSummarizer.new(comment: comment, actor: @author).copilot_api_reference_data
        end,
        reactionCounts: [],
        labels: [],
        subIssues: [],
      }

      assert_equal expected, @summarizer.copilot_api_reference_data
    end

    test "omits spammy comment" do
      create(:issue_comment, :spammy, issue: @issue, repository: @repo)
      expected = {
        type: "issue",
        id: @issue.id,
        number: @issue.number,
        repository: { id: @repo.id, name: @repo.name, owner: @repo.owner_display_login },
        title: @issue.title,
        body: @issue.body,
        state: "open",
        authorLogin: @author.display_login,
        comments: [],
        reactionCounts: [],
        labels: [],
        subIssues: [],
      }
      assert_equal expected, @summarizer.copilot_api_reference_data
    end if GitHub.spamminess_check_enabled?

    test "omits comments in the middle when the issue has more comments than the previous limit and copilot_summary_larger_context disabled" do
      comment1 = create(:issue_comment, issue: @issue, repository: @repo, body: "Oldest comment")
      comment2 = create(:issue_comment, issue: @issue, repository: @repo, body: "Middle comment")
      comment3 = create(:issue_comment, issue: @issue, repository: @repo, body: "Newest comment")
      assert_same_elements [comment1, comment2, comment3], @issue.comments

      expected = {
        type: "issue",
        id: @issue.id,
        number: @issue.number,
        repository: { id: @repo.id, name: @repo.name, owner: @repo.owner_display_login },
        title: @issue.title,
        body: @issue.body,
        state: "open",
        authorLogin: @author.display_login,
        comments: [comment1, comment3].map do |comment|
          IssueComment::CopilotSummarizer.new(comment: comment, actor: @author).copilot_api_reference_data
        end,
        reactionCounts: [],
        labels: [],
        subIssues: [],
      }

      # disable the feature flags (for ALL_FEATURES)
      @author.disable_feature(:copilot_summary_send_all_comments)
      @author.disable_feature(:copilot_summary_larger_context)

      actual = Issue::CopilotSummarizer.stub_consts(
        NEWER_COMMENT_LIMIT: 2,
        OLDER_COMMENT_LIMIT: 2,
        PREV_NEWER_COMMENT_LIMIT: 1,
        PREV_OLDER_COMMENT_LIMIT: 1,
      ) do
        @summarizer.copilot_api_reference_data
      end

      assert_equal expected, actual
    end

    test "omits comments in the middle when the issue has more comments than the limit and copilot_summary_larger_context enabled" do
      comment1 = create(:issue_comment, issue: @issue, repository: @repo, body: "Oldest comment")
      comment2 = create(:issue_comment, issue: @issue, repository: @repo, body: "Middle comment")
      comment3 = create(:issue_comment, issue: @issue, repository: @repo, body: "Newest comment")
      assert_same_elements [comment1, comment2, comment3], @issue.comments

      expected = {
        type: "issue",
        id: @issue.id,
        number: @issue.number,
        repository: { id: @repo.id, name: @repo.name, owner: @repo.owner_display_login },
        title: @issue.title,
        body: @issue.body,
        state: "open",
        authorLogin: @author.display_login,
        comments: [comment1, comment3].map do |comment|
          IssueComment::CopilotSummarizer.new(comment: comment, actor: @author).copilot_api_reference_data
        end,
        reactionCounts: [],
        labels: [],
        subIssues: [],
      }

      # disable the feature flags (for ALL_FEATURES)
      @author.disable_feature(:copilot_summary_send_all_comments)
      @author.enable_feature(:copilot_summary_larger_context)

      # Uses newer values for the limit since the feature flag is enabled
      actual = Issue::CopilotSummarizer.stub_consts(
        NEWER_COMMENT_LIMIT: 1,
        OLDER_COMMENT_LIMIT: 1,
        PREV_NEWER_COMMENT_LIMIT: 2,
        PREV_OLDER_COMMENT_LIMIT: 2,
      ) do
        @summarizer.copilot_api_reference_data
      end

      assert_equal expected, actual
    end

    test "does not omit comments in the middle when exceeding limit with copilot_summary_no_comment_limit flag enabled" do
      comment1 = create(:issue_comment, issue: @issue, repository: @repo, body: "Oldest comment")
      comment2 = create(:issue_comment, issue: @issue, repository: @repo, body: "Middle comment")
      comment3 = create(:issue_comment, issue: @issue, repository: @repo, body: "Newest comment")
      assert_same_elements [comment1, comment2, comment3], @issue.comments

      expected = {
        type: "issue",
        id: @issue.id,
        number: @issue.number,
        repository: { id: @repo.id, name: @repo.name, owner: @repo.owner_display_login },
        title: @issue.title,
        body: @issue.body,
        state: "open",
        authorLogin: @author.display_login,
        comments: [comment1, comment2, comment3].map do |comment|
          IssueComment::CopilotSummarizer.new(comment: comment, actor: @author).copilot_api_reference_data
        end,
        reactionCounts: [],
        labels: [],
        subIssues: [],
      }

      # enable the feature flag
      @author.enable_feature(:copilot_summary_send_all_comments)

      actual = Issue::CopilotSummarizer.stub_consts(
        NEWER_COMMENT_LIMIT: 1,
        OLDER_COMMENT_LIMIT: 1,
        PREV_NEWER_COMMENT_LIMIT: 1,
        PREV_OLDER_COMMENT_LIMIT: 1,
      ) do
        @summarizer.copilot_api_reference_data
      end

      assert_equal expected, actual
    end
  end
end
