# typed: true
# frozen_string_literal: true

require "test_helper"

class Discussion::CopilotSummarizerTest < GitHub::TestCase
  include CopilotPublicUserCacheable
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @org = create(:organization)
    @repo = create(:repository, owner: @org, has_discussions: true)
    @author = create(:verified_user)
    @org.add_member(@author)
    @repo.add_member(@author)
    @general_category = @repo.discussion_categories.find_by(name: DiscussionCategory::GENERAL_NAME)
    @discussion = create(:discussion, user: @author, repository: @repo, category: @general_category,
      body: "a" * CopilotThreadSummarizer::MIN_CHAR_COUNT_FOR_SUMMARIZING, title: "My great post")
  end

  setup do
    @summarizer = Discussion::CopilotSummarizer.new(discussion: @discussion, actor: @author)
  end

  context ".async_can_be_summarized? and .can_be_summarized?" do
    test "returns false for anonymous viewer" do
      GitHub.flipper[:discussions_copilot_summary].enable

      refute Discussion::CopilotSummarizer.can_be_summarized?(discussion: @discussion, viewer: nil)
      refute Discussion::CopilotSummarizer.async_can_be_summarized?(discussion: @discussion, viewer: nil).sync
    end

    test "returns false for viewer without Copilot access" do
      refute_predicate Copilot::User.new(@author), :has_copilot_access?, "need a user without Copilot"
      @author.enable_feature(:discussions_copilot_summary)

      refute Discussion::CopilotSummarizer.can_be_summarized?(discussion: @discussion, viewer: @author)
      refute Discussion::CopilotSummarizer.async_can_be_summarized?(discussion: @discussion, viewer: @author).sync
    end

    test "returns false when feature is disabled" do
      user = create(:copilot_feature_enabled_seat).assigned_user
      GitHub.flipper[:discussions_copilot_summary].disable

      refute Discussion::CopilotSummarizer.can_be_summarized?(discussion: @discussion, viewer: user)
      refute Discussion::CopilotSummarizer.async_can_be_summarized?(discussion: @discussion, viewer: user).sync
    end

    test "returns true for viewer with Copilot when feature is generally available" do
      user = create(:copilot_feature_enabled_seat).assigned_user
      user.enable_feature(:discussions_copilot_summary)
      user.enable_feature(:copilot_summary_ga)

      assert Discussion::CopilotSummarizer.can_be_summarized?(discussion: @discussion, viewer: user)
      assert Discussion::CopilotSummarizer.async_can_be_summarized?(discussion: @discussion, viewer: user).sync
    end

    test "returns true for viewer with Copilot through their org when feature is enabled and beta features are enabled" do
      org = create(:copilot_feature_enabled_enterprise_organization, :copilot_plan_enterprise)
      Copilot::Business.new(org.business).beta_features_github_chat_enable!
      user = create(:copilot_feature_enabled_seat, organization: org).assigned_user
      user.enable_feature(:discussions_copilot_summary)
      GitHub.flipper[:copilot_summary_ga].disable

      assert Discussion::CopilotSummarizer.can_be_summarized?(discussion: @discussion, viewer: user)
      assert Discussion::CopilotSummarizer.async_can_be_summarized?(discussion: @discussion, viewer: user).sync
    end

    test "returns false when discussion is too short for summarizing" do
      @discussion.update!(body: "too short")
      user = create(:copilot_feature_enabled_seat).assigned_user
      user.enable_feature(:discussions_copilot_summary)

      refute Discussion::CopilotSummarizer.can_be_summarized?(discussion: @discussion, viewer: user)
      refute Discussion::CopilotSummarizer.async_can_be_summarized?(discussion: @discussion, viewer: user).sync
    end

    test "limits queries per table" do
      discussion_body = "not long enough on its own to summarize"
      @discussion.update!(body: discussion_body)
      remaining_chars = CopilotThreadSummarizer::MIN_CHAR_COUNT_FOR_SUMMARIZING - discussion_body.size
      create(:discussion_comment, discussion: @discussion, repository: @repo, body: "a" * remaining_chars)
      @author.enable_feature(:discussions_copilot_summary)

      assert_query_count_per_table({
        "abilities" => 6,
        "business_organization_memberships" => 1,
        "business_user_accounts" => 1,
        "copilot_administrative_blocks" => 1,
        "copilot_complimentary_users" => TestEnv.test_all_features? ? 2 : 1,
        "copilot_seat_assignments" => 3,
        "copilot_seats" => 3,
        "discussion_comments" => 1,
        "subscription_items" => 1,
        "users" => 1,
      }) do
        Discussion::CopilotSummarizer.async_can_be_summarized?(discussion: @discussion, viewer: @author).sync
      end
    end
  end

  context "#body_length" do
    test "returns length of rendered discussion body" do
      @discussion.body = '<p>hello <img src="image-that-will-be-stripped.png"></p>'
      assert_equal "hello".length, @summarizer.body_length
    end
  end

  context "#comment_bodies_length" do
    test "returns length of rendered comment bodies" do
      comment1_body = "Hello world"
      comment2_body = 'Please consider <a href="/some/url/that/will/be/removed">my link</a>'
      comment1 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: comment1_body)
      comment2 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: comment2_body)
      assert_same_elements [comment1, comment2], @discussion.reload.comments

      assert_equal "Hello worldPlease consider my link".length, @summarizer.comment_bodies_length
    end
  end

  context "DISCUSSION_SUMMARY_NEGATIVE_FEEDBACK_LABELS" do
    test "includes valid values" do
      refute_empty Discussion::CopilotSummarizer::DISCUSSION_SUMMARY_NEGATIVE_FEEDBACK_LABELS
      Discussion::CopilotSummarizer::DISCUSSION_SUMMARY_NEGATIVE_FEEDBACK_LABELS.each do |value, label|
        assert_includes Discussion::CopilotSummarizer::DISCUSSION_SUMMARY_FEEDBACK_OPTIONS, value,
          "expected value to be a valid one for use in the Hydro enum"
        assert_predicate label, :present?, "expected to have a non-blank label for value #{value}"
      end
    end
  end

  context "#instrument_copilot_summary_feedback" do
    test "returns false when not given any feedback choices" do
      refute @summarizer.instrument_copilot_summary_feedback(feedback_choices: [])
      refute_hydro_messages(schema: "github.discussions.v2.GiveCopilotSummaryFeedback")
    end

    test "emits Hydro event and returns true on success" do
      assert @summarizer.instrument_copilot_summary_feedback(feedback_choices: %w(INCORRECT UNHELPFUL))

      assert_hydro_messages(count: 1, schema: "github.discussions.v2.GiveCopilotSummaryFeedback")
      assert_hydro_published({
        analytics_tracking_id: @author.analytics_tracking_id,
        feedback_choice: %w(INCORRECT UNHELPFUL),
        feedback: nil,
        repository_id: @repo.id,
        organization_id: @org.id,
        header_request_id: nil,
        prompt_version: Discussion::CopilotSummarizer::USER_PROMPT_VERSION,
        github_revision: GitHub.current_sha,
      }, schema: "github.discussions.v2.GiveCopilotSummaryFeedback")
    end

    test "returns false when given an invalid feedback choice" do
      refute @summarizer.instrument_copilot_summary_feedback(feedback_choices: %w(INCORRECT SOME_RANDOM_VALUE))
      refute_hydro_messages(schema: "github.discussions.v2.GiveCopilotSummaryFeedback")
    end
  end

  context "#summarize" do
    test "emits Hydro event" do
      capi_response = {
        choices: [
          {
            message: { role: "assistant", content: "this is a fake discussion summary" },
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
          default_prompt: Discussion::CopilotSummarizer::USER_PROMPT).returns(capi_response)

      @summarizer.summarize

      assert_hydro_messages(count: 1, schema: "github.discussions.v2.CopilotSummarize")
      assert_hydro_published({
        analytics_tracking_id: @author.analytics_tracking_id,
        repository_id: @repo.id,
        organization_id: @org.id,
        body_length: @summarizer.body_length,
        comment_bodies_length: @summarizer.comment_bodies_length,
        comment_count: @summarizer.comment_count,
      }, schema: "github.discussions.v2.CopilotSummarize")
    end

    test "passes along custom prompt when given" do
      capi_response = {
        choices: [
          {
            message: { role: "assistant", content: "this is a fake discussion summary" },
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
          default_prompt: Discussion::CopilotSummarizer::USER_PROMPT).returns(capi_response)

      @summarizer.summarize(prompt: prompt)

      assert_hydro_published({
        analytics_tracking_id: @author.analytics_tracking_id,
        repository_id: @repo.id,
        organization_id: @org.id,
        body_length: @summarizer.body_length,
        comment_bodies_length: @summarizer.comment_bodies_length,
        comment_count: @summarizer.comment_count,
      }, schema: "github.discussions.v2.CopilotSummarize")
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
          "type": "github.discussion",
          "data": {
            "id": 123,
            "number": 0,
            "repository": { "id": 0, "name": "", "owner": "" },
            "body": "Some discussion body",
            "authorLogin": "monalisa",
            "totalUpvotes": 1,
            "comments": [],
            "type": "discussion",
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
          default_prompt: Discussion::CopilotSummarizer::USER_PROMPT).returns(capi_response)

      @summarizer.summarize

      assert_dogstats_distribution_value 118, "discussions.copilot.summarize.tokens_used",
        tags: ["model:#{model}", "usage_type:completion"]
      assert_dogstats_distribution_value 3294, "discussions.copilot.summarize.tokens_used",
        tags: ["model:#{model}", "usage_type:prompt"]
    end
  end

  context "#copilot_api_reference" do
    test "returns a hash representing a reference we can send to CAPI that includes the discussion data" do
      expected = {
        type: "github.discussion",
        id: "#{@discussion.id}",
        data: @summarizer.copilot_api_reference_data,
      }
      assert_equal expected, @summarizer.copilot_api_reference
    end
  end

  context "#copilot_api_reference_data" do
    test "returns a hash representing the discussion for use within a CAPI reference" do
      body_markdown = <<~MARKDOWN
        This is my great post.

        <!-- Please pay no attention to comments like this. -->

        I have included a photo: ![some user avatar](/some-image.png)
      MARKDOWN
      @discussion.update!(body: body_markdown)
      label_o = create(:label, repository: @repo, name: "Omeluum", description: "Our favorite mind flayer")
      label_b = create(:label, repository: @repo, name: "Blurg", description: nil)
      create(:applied_discussion_label, repository: @repo, discussion: @discussion, label: label_o)
      create(:applied_discussion_label, repository: @repo, discussion: @discussion, label: label_b)
      assert_difference("@discussion.reload.total_upvotes") { create(:discussion_vote, discussion: @discussion) }
      reaction = create(:discussion_reaction, discussion: @discussion)
      poll = create(:discussion_poll, discussion: @discussion, option_texts: %w(First Second Third))
      create(:discussion_poll_vote, poll: poll, option: poll.options.find_by(option: "First"))
      create_pair(:discussion_poll_vote, poll: poll, option: poll.options.find_by(option: "Third"))

      # This is specifically validating the context parameter is passed with the expected value
      expected_body = "This is my great post.\n\nI have included a photo: some user avatar"
      GitHub::Goomba::CopilotSummaryInputPipeline.expects(:to_text).with(@discussion.body, { entity: @repo }, nil).returns(expected_body).once

      expected = {
        type: "discussion",
        body: expected_body,
        title: @discussion.title,
        id: @discussion.id,
        number: @discussion.number,
        state: @discussion.state,
        authorLogin: @author.display_login,
        answer: nil,
        repository: { id: @repo.id, name: @repo.name, owner: @repo.owner_display_login },
        comments: [],
        totalUpvotes: 2,
        reactionCounts: [{ reaction: reaction.content, count: 1 }],
        labels: [
          { name: "Blurg", description: nil },
          { name: "Omeluum", description: "Our favorite mind flayer" },
        ],
        category: { name: DiscussionCategory::GENERAL_NAME, description: @general_category.description },
        poll: {
          question: poll.question,
          options: [
            { option: "First", totalVotes: 1 },
            { option: "Second", totalVotes: 0 },
            { option: "Third", totalVotes: 2 },
          ],
        },
      }
      assert_equal expected, @summarizer.copilot_api_reference_data
    end

    test "strips images and links from discussion body" do
      @discussion.body = "This is a [great](https://zombo.com) website! Please look:\n" \
        "<img src='some_file.png' alt='Magical views'>\n" \
        "![a user avatar](https://github.com/username.png) ![](/some-image-without-alt-text.jpeg)"

      actual = @summarizer.copilot_api_reference_data

      assert_equal "This is a great website! Please look:\nMagical views\na user avatar", actual[:body]
    end

    test "does not label chosen comment as answer when discussion category does not support answers" do
      answer = create(:discussion_comment, discussion: @discussion, repository: @repo)
      @discussion.update_attribute(:chosen_comment_id, answer.id)
      refute_predicate @discussion, :supports_mark_as_answer?

      result = @summarizer.copilot_api_reference_data

      assert_nil result[:answer]
      updated_answer_summarizer = DiscussionComment::CopilotSummarizer.new(comment: answer.reload, actor: answer.user)
      assert_includes result[:comments], updated_answer_summarizer.copilot_api_reference_data
    end

    test "lists answer separate from other comments" do
      qa_category = @repo.discussion_categories.find_by(supports_mark_as_answer: true)
      refute_nil qa_category, "need a discussion category that allows marking answers"
      discussion = create(:discussion, user: @author, repository: @repo, category: qa_category)
      answer = create(:discussion_comment, :answer, discussion: discussion, repository: @repo)
      answer_summarizer = DiscussionComment::CopilotSummarizer.new(comment: answer.reload, actor: @author)
      other_comment = create(:discussion_comment, discussion: discussion, repository: @repo)
      other_comment_summarizer = DiscussionComment::CopilotSummarizer.new(comment: other_comment.reload,
        actor: @author)

      expected = {
        type: "discussion",
        body: discussion.body,
        title: discussion.title,
        id: discussion.id,
        number: discussion.number,
        repository: { id: @repo.id, name: @repo.name, owner: @repo.owner_display_login },
        state: @discussion.state,
        authorLogin: @author.display_login,
        answer: answer_summarizer.copilot_api_reference_data,
        comments: [other_comment_summarizer.copilot_api_reference_data],
        totalUpvotes: 1,
        reactionCounts: [],
        labels: [],
        category: { name: qa_category.name, description: qa_category.description },
        poll: nil,
      }

      summarizer = Discussion::CopilotSummarizer.new(discussion: discussion, actor: @author)

      assert_equal expected, summarizer.copilot_api_reference_data
    end

    test "includes all top-level and nested comments when the discussion has within the limit" do
      comment1 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Oldest comment")
      comment2 = create(:discussion_comment, discussion: @discussion, repository: @repo,
        body: "Second top-level comment")
      reply1 = create(:discussion_comment, discussion: @discussion, repository: @repo, parent_comment: comment1,
        body: "Oldest nested comment")
      reply2 = create(:discussion_comment, discussion: @discussion, repository: @repo, parent_comment: comment2,
        body: "Newest nested comment")

      expected = {
        type: "discussion",
        body: @discussion.body,
        title: @discussion.title,
        id: @discussion.id,
        number: @discussion.number,
        repository: { id: @repo.id, name: @repo.name, owner: @repo.owner_display_login },
        state: @discussion.state,
        authorLogin: @author.display_login,
        answer: nil,
        comments: [comment1, comment2, reply1, reply2]
          .map(&:reload) # reload each comment so its `total_upvotes` is stable
          .map do |comment|
            DiscussionComment::CopilotSummarizer.new(comment: comment, actor: @author).copilot_api_reference_data
          end,
        totalUpvotes: 1,
        reactionCounts: [],
        labels: [],
        category: { name: DiscussionCategory::GENERAL_NAME, description: @general_category.description },
        poll: nil,
      }

      assert_equal expected, @summarizer.copilot_api_reference_data
    end

    test "omits spammy comment" do
      create(:spammy_discussion_comment, discussion: @discussion, repository: @repo)
      expected = {
        type: "discussion",
        body: @discussion.body,
        title: @discussion.title,
        id: @discussion.id,
        number: @discussion.number,
        state: @discussion.state,
        authorLogin: @author.display_login,
        repository: { id: @repo.id, name: @repo.name, owner: @repo.owner_display_login },
        answer: nil,
        comments: [],
        totalUpvotes: 1,
        reactionCounts: [],
        labels: [],
        category: { name: DiscussionCategory::GENERAL_NAME, description: @general_category.description },
        poll: nil,
      }
      assert_equal expected, @summarizer.copilot_api_reference_data
    end if GitHub.spamminess_check_enabled?

    test "omits hidden comment" do
      hidden_comment = create(:discussion_comment, :minimized, discussion: @discussion, repository: @repo)
      assert_includes @discussion.comments, hidden_comment

      result = @summarizer.copilot_api_reference_data

      refute_includes result[:comments], hidden_comment
    end

    test "omits deleted comment" do
      deleted_comment = create(:discussion_comment, :wiped, discussion: @discussion, repository: @repo)
      assert_includes @discussion.comments, deleted_comment

      result = @summarizer.copilot_api_reference_data

      refute_includes result[:comments], deleted_comment
    end

    test "omits comments in the middle when the discussion has more comments than the previous limit and copilot_summary_larger_context disabled" do
      comment1 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Oldest comment")
      reply = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Oldest comment reply",
        parent_comment: comment1)
      comment2 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Middle comment")
      comment3 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Newest comment")
      reply2 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Newest comment reply",
        parent_comment: comment2)
      assert_same_elements [comment1, reply, comment2, comment3, reply2], @discussion.comments

      expected = {
        type: "discussion",
        body: @discussion.body,
        title: @discussion.title,
        id: @discussion.id,
        number: @discussion.number,
        state: @discussion.state,
        authorLogin: @author.display_login,
        repository: { id: @repo.id, name: @repo.name, owner: @repo.owner_display_login },
        answer: nil,
        comments: [comment1, reply, comment3, reply2]
          .map(&:reload) # reload each comment so its `total_upvotes` is stable
          .map do |comment|
            DiscussionComment::CopilotSummarizer.new(comment: comment, actor: @author).copilot_api_reference_data
          end,
        totalUpvotes: 1,
        reactionCounts: [],
        labels: [],
        category: { name: DiscussionCategory::GENERAL_NAME, description: @general_category.description },
        poll: nil,
      }

      # disable the feature flags (for ALL_FEATURES)
      @author.disable_feature(:copilot_summary_send_all_comments)
      @author.disable_feature(:copilot_summary_larger_context)

      actual = Discussion::CopilotSummarizer.stub_consts(
        NEWER_COMMENT_LIMIT: 4,
        OLDER_COMMENT_LIMIT: 4,
        PREV_NEWER_COMMENT_LIMIT: 2,
        PREV_OLDER_COMMENT_LIMIT: 2,
      ) do
        @summarizer.copilot_api_reference_data
      end

      assert_equal expected, actual
    end
  end

  test "omits comments in the middle when the discussion has more comments than the limit and copilot_summary_larger_context enabled" do
    comment1 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Oldest comment")
    reply = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Oldest comment reply",
      parent_comment: comment1)
    comment2 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Middle comment")
    comment3 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Newest comment")
    reply2 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Newest comment reply",
      parent_comment: comment2)
    assert_same_elements [comment1, reply, comment2, comment3, reply2], @discussion.comments

    expected = {
      type: "discussion",
      body: @discussion.body,
      title: @discussion.title,
      id: @discussion.id,
      number: @discussion.number,
      state: @discussion.state,
      authorLogin: @author.display_login,
      repository: { id: @repo.id, name: @repo.name, owner: @repo.owner_display_login },
      answer: nil,
      comments: [comment1, reply, comment3, reply2]
        .map(&:reload) # reload each comment so its `total_upvotes` is stable
        .map do |comment|
          DiscussionComment::CopilotSummarizer.new(comment: comment, actor: @author).copilot_api_reference_data
        end,
      totalUpvotes: 1,
      reactionCounts: [],
      labels: [],
      category: { name: DiscussionCategory::GENERAL_NAME, description: @general_category.description },
      poll: nil,
    }

    # disable the feature flags (for ALL_FEATURES)
    @author.disable_feature(:copilot_summary_send_all_comments)
    @author.enable_feature(:copilot_summary_larger_context)

    # Uses newer values for the limit since the feature flag is enabled
    actual = Discussion::CopilotSummarizer.stub_consts(
      NEWER_COMMENT_LIMIT: 2,
      OLDER_COMMENT_LIMIT: 2,
      PREV_NEWER_COMMENT_LIMIT: 4,
      PREV_OLDER_COMMENT_LIMIT: 4,
    ) do
      @summarizer.copilot_api_reference_data
    end

    assert_equal expected, actual
  end

  test "does not omit comments in the middle when exceeding limit with copilot_summary_no_comment_limit flag enabled" do
    comment1 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Oldest comment")
    reply = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Oldest comment reply",
      parent_comment: comment1)
    comment2 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Middle comment")
    comment3 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Newest comment")
    reply2 = create(:discussion_comment, discussion: @discussion, repository: @repo, body: "Newest comment reply",
      parent_comment: comment2)
    assert_same_elements [comment1, reply, comment2, comment3, reply2], @discussion.comments

    expected = {
      type: "discussion",
      body: @discussion.body,
      title: @discussion.title,
      id: @discussion.id,
      number: @discussion.number,
      state: @discussion.state,
      authorLogin: @author.display_login,
      repository: { id: @repo.id, name: @repo.name, owner: @repo.owner_display_login },
      answer: nil,
      comments: [comment1, reply, comment2, comment3, reply2]
        .map(&:reload) # reload each comment so its `total_upvotes` is stable
        .map do |comment|
          DiscussionComment::CopilotSummarizer.new(comment: comment, actor: @author).copilot_api_reference_data
        end,
      totalUpvotes: 1,
      reactionCounts: [],
      labels: [],
      category: { name: DiscussionCategory::GENERAL_NAME, description: @general_category.description },
      poll: nil,
    }

    # enable the feature flag
    @author.enable_feature(:copilot_summary_send_all_comments)

    actual = Discussion::CopilotSummarizer.stub_consts(
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
