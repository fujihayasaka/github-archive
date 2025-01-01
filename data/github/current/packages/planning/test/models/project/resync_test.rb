# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectResyncingTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    @owner = create(:user)

    @org = create(:organization, plan: "silver").tap do |o|
      o.add_member(@owner, action: :admin)
    end

    @repo = create(:private_repository, owner: @org)

    @project = create(:project, owner: @repo)
    @column = create(:project_column, project: @project)

    @issue = create(:issue, repository: @repo)
    @issue_card = create(:project_card, column: @column, content: @issue)
  end

  context "resync workflows" do
    test "resync_workflows! moves a card" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @issue.close(@owner)

      done_column = create(:project_column, project: @project, name: "done")

      @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, column: done_column)

      @project.resync_workflows!(actor: @owner)
      @issue_card.reload
      assert_equal done_column.id, @issue_card.column_id
      assert_equal 1, GitHub.dogstats.increments("job.resync_project_workflows.resync_triggered").length
    end

    test "resync_workflows! moves a card even if the column max with archived cards is hit" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @issue.close(@owner)

      done_column = create(:project_column, project: @project, name: "done")
      create(:archived_project_card, column: done_column)

      @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, column: done_column)

      ProjectColumn.stub_const(:MAX_CARDS, 1) do
        @project.resync_workflows!(actor: @owner)
        @issue_card.reload
        assert_equal done_column, @issue_card.column
      end
    end

    test "resync_workflows! limits to the requested @project" do
      done_column = create(:project_column, project: @project, name: "done")

      project_2 = create(:project, owner: @repo)
      column_2 = create(:project_column, project: project_2, name: "start")
      done_column_2 = create(:project_column, project: project_2, name: "done")

      card_2 = create(:project_card, column: column_2, content: create(:issue, repository: @repo), creator: @owner)
      card_2.content.close(@owner)

      @issue.close(@owner)

      @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, column: done_column)
      project_2.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, column: done_column_2)

      @project.resync_workflows!(actor: @owner)

      @issue_card.reload
      card_2.reload
      assert_equal done_column.id, @issue_card.column_id
      assert_equal column_2.id, card_2.column_id
    end

    test "resync runs pending card trigger first" do
      todo_column = create(:project_column, project: @project, name: "todo")
      done_column = create(:project_column, project: @project, name: "done")
      issue = create(:issue, repository: @repo)
      card = create(:pending_project_card, project: @project, content: issue)
      issue.repository.add_member(issue.user)

      issue.close(issue.user)

      @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_PENDING_CARD_ADDED_TRIGGER, column: todo_column)
      @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, column: done_column)

      @project.resync_workflows!(actor: @owner)

      assert_same_elements %w(closed added_to_project moved_columns_in_project), issue.events.collect(&:event)
      card.reload
      assert_equal done_column.id, card.column_id
    end

    test "resync runs review card triggers before other pull request triggers" do
      pull = make_pr_and_repos
      owner = @make_pr_repo_owner
      project = create(:project, owner: pull.repository)
      column = create(:project_column, project: project)
      pull_card = create(:project_card, column: column, content: pull.issue)
      review = create(:pull_request_review, user: owner, pull_request: pull)
      review.approve!
      pull.close(pull.user)

      in_progress_column = create(:project_column, project: project, name: "in progress")
      done_column = create(:project_column, project: project, name: "done")

      project.project_workflows.set_workflow(creator: owner, trigger_type: ProjectWorkflow::PR_CLOSED_NOT_MERGED_TRIGGER, column: done_column)
      project.project_workflows.set_workflow(creator: owner, trigger_type: ProjectWorkflow::PR_APPROVED_TRIGGER, column: in_progress_column)

      project.resync_workflows!(actor: owner)

      pull_card.reload
      assert_equal done_column.id, pull_card.column_id
    end

    test "resync runs reopen triggers before other review triggers" do
      Spokesd.enable_spokesd

      pull = make_pr_and_repos
      owner = @make_pr_repo_owner
      project = create(:project, owner: pull.repository)
      column = create(:project_column, project: project)
      pull_card = create(:project_card, column: column, content: pull.issue)
      review = create(:pull_request_review, user: owner, pull_request: pull)
      review.approve!
      pull.close
      pull.open(owner)

      in_progress_column = create(:project_column, project: project, name: "in progress")
      todo_column = create(:project_column, project: project, name: "todo")

      project.project_workflows.set_workflow(creator: owner, trigger_type: ProjectWorkflow::PR_APPROVED_TRIGGER, column: in_progress_column)
      project.project_workflows.set_workflow(creator: owner, trigger_type: ProjectWorkflow::PR_REOPENED_TRIGGER, column: todo_column)

      project.resync_workflows!(actor: owner)

      pull_card.reload
      assert_equal in_progress_column.id, pull_card.column_id
    end
  end

  context "Sync limit" do
    test "Resync updates last_sync_at" do
      time_0 = Time.current
      Timecop.freeze(time_0) do
        assert_nil @project.last_sync_at
        @project.resync_workflows!(actor: @owner)
        @project.reload
        assert_equal time_0.to_i, @project.last_sync_at.to_i
      end
    end
  end

  context "store lock value in GitHub.kv" do
    test "resync kv value is set and deleted during resync" do
      # rubocop:todo GitHub/DoNotUseGlobalKv
      GitHub.kv.expects(:set).with(@project.lock_key(Project::ProjectLock::PROJECT_RESYNCING), @owner.login).once
      # rubocop:enable GitHub/DoNotUseGlobalKv
      # rubocop:todo GitHub/DoNotUseGlobalKv
      GitHub.kv.expects(:del).with(@project.lock_key(Project::ProjectLock::PROJECT_RESYNCING)).once
      # rubocop:enable GitHub/DoNotUseGlobalKv

      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert_nil GitHub.kv.get(@project.lock_key(Project::ProjectLock::PROJECT_RESYNCING)).value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
      @project.resync_workflows!(actor: @owner)
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert_nil GitHub.kv.get(@project.lock_key(Project::ProjectLock::PROJECT_RESYNCING)).value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end

    test "does not set and delete kv if project locked for resync" do
      @project.lock!(lock_type: Project::ProjectLock::PROJECT_RESYNCING, actor: @owner)

      # rubocop:todo GitHub/DoNotUseGlobalKv
      GitHub.kv.expects(:set).with(@project.lock_key(Project::ProjectLock::PROJECT_RESYNCING), @owner.login).never
      # rubocop:enable GitHub/DoNotUseGlobalKv
      # rubocop:todo GitHub/DoNotUseGlobalKv
      GitHub.kv.expects(:del).with(@project.lock_key(Project::ProjectLock::PROJECT_RESYNCING)).never
      # rubocop:enable GitHub/DoNotUseGlobalKv

      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert GitHub.kv.get(@project.lock_key(Project::ProjectLock::PROJECT_RESYNCING)).value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
      @project.resync_workflows!(actor: @owner)
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert GitHub.kv.get(@project.lock_key(Project::ProjectLock::PROJECT_RESYNCING)).value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end
  end

  context "live updates" do
    test "sends lock/unlock live update notifications when resync starts/stops" do
      locked_data = {
        name: @project.name,
        locked: @owner.login,
        project_migration: nil,
      }

      unlocked_data = {
        name: @project.name,
        locked: false,
        project_migration: nil,
      }
      channel = GitHub::WebSocket::Channels.project_metadata(@project)

      GitHub::WebSocket.expects(:notify_project_channel).with(@project, channel, locked_data).returns([]).once
      GitHub::WebSocket.expects(:notify_project_channel).with(@project, channel, unlocked_data).returns([]).once

      @project.resync_workflows!(actor: @owner)
    end

    test "does not send lock/unlock notifications if project is locked for resync" do
      @project.lock!(lock_type: Project::ProjectLock::PROJECT_RESYNCING, actor: @owner)

      locked_data = {
        name: @project.name,
        locked: @owner.login,
        project_migration: nil,
      }

      unlocked_data = {
        name: @project.name,
        locked: false,
        project_migration: nil,
      }

      channel = GitHub::WebSocket::Channels.project_metadata(@project)

      GitHub::WebSocket.expects(:notify_project_channel).with(@project, channel, locked_data).returns([]).never
      GitHub::WebSocket.expects(:notify_project_channel).with(@project, channel, unlocked_data).returns([]).never

      @project.resync_workflows!(actor: @owner)
    end
  end
end
