# typed: true
# frozen_string_literal: true

require "test_helper"

module CommmandPalette
  module Commands
    class PinIssueTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @user = create(:user)
        @repo = create(:repository, owner: @user)
        @issue = create(:issue, title: "Test Issue", user: @user, repository: @repo)
      end

      setup do
        context = build_context(current_user: @user, scope: @issue, subject: @issue)
        @command = CommandPalette::Commands::PinIssue.new(context)
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

        test "returns false if issue is already pinned" do
          @issue.pin(actor: @user)
          refute @command.enabled?
        end

        test "returns false if user doesn't have permission" do
          user = build(:user)
          context = build_context(current_user: user, scope: @issue, subject: @issue)
          refute CommandPalette::Commands::PinIssue.new(context).enabled?
        end

        test "returns false if repository has enough pinned issues" do
          issue1 = create(:issue, repository: @repo, user: @user)
          issue2 = create(:issue, repository: @repo, user: @user)
          issue3 = create(:issue, repository: @repo, user: @user)

          @repo.pinned_issues.create!(issue: issue1, pinned_by: @user, sort: 1)
          @repo.pinned_issues.create!(issue: issue2, pinned_by: @user, sort: 2)
          @repo.pinned_issues.create!(issue: issue3, pinned_by: @user, sort: 3)

          refute @command.enabled?
        end

        test "returns true if all conditions are met" do
          assert @command.enabled?
        end
      end

      context "#execute" do
        test "pins the issue" do
          refute @issue.pinned?

          response = @command.execute

          assert @issue.pinned?
          assert_equal response.action, CommandPalette::Commands::Response::ACTION_DISPLAY_FLASH
          assert_equal response.arguments[:type], :success
          assert_equal response.arguments[:message], "Pinned Issue: #{@issue.title}"
        end
      end
    end
  end
end
