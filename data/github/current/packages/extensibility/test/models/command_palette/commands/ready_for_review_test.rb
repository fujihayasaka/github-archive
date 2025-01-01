# typed: true
# frozen_string_literal: true

require "test_helper"

module CommmandPalette
  module Commands
    class ReadyForReviewTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @owner = create(:user, login: "owner")
        @user = create(:user)
        @repo = create(:repository, owner: @owner, from_example: :pull_request_fork)
        @repo.add_member(@user)

        @issue = create(
          :issue,
          repository: @repo,
          user: @owner,
          pull_request: @repo.comparison("master", "topic").build_pull_request(user: @owner)
        )
        @pull_request = @issue.pull_request
        @pull_request.update_attribute(:draft, true)

        @advisory = create(:repository_advisory, repository: @repo, author: @owner)
        perform_enqueued_jobs(only: [RepositoryCloneJob]) do
          GitHub.context.push(actor_id: @owner.id)
          @workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @owner).tap(&:save!)
        end

        @workspace_pr = PullRequest.create_for!(
          @workspace_repo,
          user: @owner,
          base: "master",
          head: "topic",
          title: "some other silly changes"
        )
        @workspace_pr.update_attribute(:draft, true)
      end

      setup do
        context = build_context(current_user: @user, scope: @pull_request, subject: @pull_request)
        @command = CommandPalette::Commands::ReadyForReview.new(context)
      end

      context "#enabled?" do
        test "returns false if the user cannot mark the pull request as ready for review" do
          @pull_request.expects(:can_mark_ready_for_review?).with(@user).returns(false)
          refute @command.enabled?
        end

        test "returns true if the user can change the draft state" do
          assert @command.enabled?
        end
      end

      context "#execute" do
        test "marks the pull request as ready for review" do
          assert @pull_request.draft?

          response = @command.execute

          assert @pull_request.ready_for_review?
          assert_equal response.action, CommandPalette::Commands::Response::ACTION_DISPLAY_FLASH
          assert_equal response.arguments[:type], :success
          assert_equal response.arguments[:message], "Marked pull request as ready for review"
        end

        test "marks the pull request as ready for review in the workspace repo" do
          Repository.any_instance.stubs(:plan_supports?).returns(true)

          context = build_context(current_user: @owner, scope: @workspace_pr, subject: @workspace_pr)
          command = CommandPalette::Commands::ReadyForReview.new(context)

          assert @workspace_pr.draft?

          response = command.execute

          assert @workspace_pr.ready_for_review?
          assert_equal response.action, CommandPalette::Commands::Response::ACTION_DISPLAY_FLASH
          assert_equal response.arguments[:type], :success
          assert_equal response.arguments[:message], "Marked pull request as ready for review"
        end
      end
    end
  end
end
