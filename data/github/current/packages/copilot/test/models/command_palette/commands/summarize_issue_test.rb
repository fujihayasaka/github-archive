# typed: true
# frozen_string_literal: true

require "test_helper"

module CommmandPalette
  module Commands
    class SummarizeIssueTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @user = create(:user)
        @repo = create(:repository, owner: @user)
        @issue = create(:issue, user: @user, repository: @repo)
      end

      setup do
        context = build_context(current_user: @issue.user, scope: @issue, subject: @issue)
        @command = CommandPalette::Commands::SummarizeIssue.new(context)
      end

      context "#enabled?" do
        test "returns true when :issue_summarization is enabled" do
          GitHub.flipper[:issue_summarization].enable(@user)
          assert @command.enabled?
        end

        test "returns false when :issue_summarization is not enabled" do
          GitHub.flipper[:issue_summarization].disable(@user)
          refute @command.enabled?
        end
      end

      context "#execute" do
        test "queues a summary" do
          @command.execute
          summary = IssueSummary.find_by(issue: @issue, user: @issue.user)
          assert summary
          assert T.must(summary).scheduled?
        end
      end
    end
  end
end
