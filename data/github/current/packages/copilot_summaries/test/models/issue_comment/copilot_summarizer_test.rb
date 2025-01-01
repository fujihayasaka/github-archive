# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueComment::CopilotSummarizerTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @issue = create(:issue, repository: @repo)
  end

  context "#body_length" do
    test "returns length of rendered Markdown body for comment" do
      comment = create(:issue_comment, issue: @issue, repository: @repo,
        body: "This is a [great](https://zombo.com) website! Please look:\n" \
          "<img src='some_file.png' alt='Magical views'>\n" \
          "![a user avatar](https://github.com/username.png) ![](/some-image-without-alt-text.jpeg)")
      expected_body_length = "This is a great website! Please look:\nMagical views\na user avatar".length
      summarizer = IssueComment::CopilotSummarizer.new(comment: comment, actor: comment.user)

      assert_equal expected_body_length, summarizer.body_length
    end
  end

  context "#copilot_api_reference_data" do
    test "returns a hash representing the comment for use as a CAPI reference" do
      creation_time = 1.week.ago
      author = create(:verified_user)
      body_markdown = <<~MARKDOWN
        <!--some side commentary-->Great idea, please consider.
      MARKDOWN
      comment = travel_to(creation_time) do
        create(:issue_comment, issue: @issue, repository: @repo, user: author, body: body_markdown)
      end
      create_pair(:issue_comment_reaction, content: "smile", issue_comment: comment)
      summarizer = IssueComment::CopilotSummarizer.new(comment: comment, actor: author)

      # This is specifically validating the context parameter is passed with the expected value
      expected_body = "Great idea, please consider."
      GitHub::Goomba::CopilotSummaryInputPipeline.expects(:to_text).with(comment.body, { entity: @repo }, nil).returns(expected_body).once

      expected = {
        author: author.display_login,
        body: expected_body,
        createdAt: creation_time.iso8601,
        reactionCounts: [{ reaction: "smile", count: 2 }],
      }
      assert_equal expected, summarizer.copilot_api_reference_data
    end

    test "strips images and links from comment body" do
      comment = create(:issue_comment, issue: @issue, repository: @repo,
        body: "This is a [great](https://zombo.com) website! Please look:\n" \
          "<img src='some_file.png' alt='Magical views'>\n" \
          "![a user avatar](https://github.com/username.png) ![](/some-image-without-alt-text.jpeg)")
      summarizer = IssueComment::CopilotSummarizer.new(comment: comment, actor: comment.user)

      actual = summarizer.copilot_api_reference_data

      assert_equal "This is a great website! Please look:\nMagical views\na user avatar", actual[:body]
    end
  end
end
