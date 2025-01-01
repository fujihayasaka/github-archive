# typed: true
# frozen_string_literal: true

require "test_helper"

module CommmandPalette
  module Commands
    class UnpinIssueTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @user = create(:user)
        @repo = create(:repository, owner: @user)
        @issue = create(:issue, title: "Test Issue", user: @user, repository: @repo)
      end

      setup do
        context = build_context(current_user: @user, scope: @issue, subject: @issue)
        @command = CommandPalette::Commands::UnpinIssue.new(context)
      end

      context "#enabled?" do
        test "returns false if issues disabled on repo" do
          @repo.update!(has_issues: false)
          refute @command.enabled?
        end

        test "returns false if repo is locked for migration" do
          @repo.lock_for_migration
          refute @command.enabled?
        end

        test "returns false if repo is archived" do
          @repo.set_archived
          refute @command.enabled?
        end

        test "returns false if issue is not already pinned" do
          refute @command.enabled?
        end

        test "returns false if user doesn't have permission" do
          user = build(:user)
          context = build_context(current_user: user, scope: @issue, subject: @issue)
          refute CommandPalette::Commands::UnpinIssue.new(context).enabled?
        end

        test "returns true if all conditions are met" do
          @issue.pin(actor: @user)
          assert @command.enabled?
        end
      end

      context "#execute" do
        test "unpins the issue" do
          @issue.pin(actor: @user)
          assert @issue.pinned?

          @issue.reload
          response = @command.execute

          refute @issue.pinned?
          assert_equal response.action, CommandPalette::Commands::Response::ACTION_DISPLAY_FLASH
          assert_equal response.arguments[:type], :success
          assert_equal response.arguments[:message], "Unpinned Issue: #{@issue.title}"
        end
      end
    end
  end
end
