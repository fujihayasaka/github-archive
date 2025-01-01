# typed: true
# frozen_string_literal: true

require "test_helper"

module CommmandPalette
  module Commands
    class CloneCopyHttpsTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @user = create(:user)
        @repo = create(:repository, owner: @user)
        @issue = create(:issue, user: @user, repository: @repo)
      end

      setup do
        issue_context = build_context(current_user: @user, scope: @issue, subject: @issue)
        @issue_command = CommandPalette::Commands::CloneCopyHttps.new(issue_context)

        repo_context = build_context(current_user: @user, scope: @repo, subject: @repo)
        @repo_command = CommandPalette::Commands::CloneCopyHttps.new(repo_context)
      end

      context "#enabled?" do
        test "returns false if repo not readable by user" do
          @repo.expects(:readable_by?).with(@user).returns(false)
          refute @repo_command.enabled?
        end

        test "returns false if certificate is required" do
          @repo.expects(:ssh_certificate_requirement_enabled?).returns(true)
          refute @repo_command.enabled?
        end

        test "returns true if all conditions are met" do
          assert @repo_command.enabled?
        end
      end

      context "#repository" do
        test "returns the subject if its a repository" do
          assert_equal @repo, @repo_command.repository
        end

        test "returns the subjects repository when not a repository" do
          assert_equal @repo, @issue_command.repository
        end
      end

      context "#copyable_text" do
        test "returns the repo url if subject is not a repository" do
          assert_equal "https://#{GitHub.host_name}/#{@user.login}/#{@repo.name}.git", @issue_command.copyable_text
        end

        test "returns the repo url if subject is a repository" do
          assert_equal "https://#{GitHub.host_name}/#{@user.login}/#{@repo.name}.git", @repo_command.copyable_text
        end
      end
    end
  end
end
