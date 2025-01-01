# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectResyncTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    @owner = create(:user, login: "ari")
    @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
    forker = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: forker, fork_repo: @repo, from_example: :pull_request_fork)

    issue = create(:issue, user: forker, repository: @repo)
    @pr = PullRequest.create_for(@repo, {
      base:  "master",
      head:  "#{@fork.user}:topic",
      user:  issue.user,
      issue: issue,
    })

    issue = create(:issue, user: forker, repository: @repo)
    @pending_pr = PullRequest.create_for(@repo, {
      base:  "master",
      head:  "master-forward-2",
      user:  issue.user,
      issue: issue,
    })

    @project = create(:project, owner: @repo)
    @column = create(:project_column, project: @project)
    @column_2 = create(:project_column, project: @project)
    @issue = create(:issue, repository: @repo)
    @pending_issue = create(:issue, repository: @repo)

    @issue_card = create(:project_card, column: @column, content: @issue)
    @pending_issue_card = create(:pending_project_card, project: @project, content: @pending_issue)

    @pr_card = create(:project_card, column: @column, content: @pr.issue)
    @pending_pr_card = create(:pending_project_card, project: @project, content: @pending_pr.issue)

    @external_triggers = ProjectWorkflow::EXTERNAL_TRIGGERS
    @pending_triggers = ProjectWorkflow::PENDING_CARD_TRIGGERS
    @nonpending_triggers = @external_triggers - @pending_triggers
  end

  setup do
    # PR merge state persists between runs so we need to re-apply
    # example_repo here to make sure things are in the clean slate
    # state for tests
    example_repo :pull_request_source, @repo
    example_repo :pull_request_fork,   @fork
  end

  context "resyncing project boards" do
    context "finding cards for resync" do
      test "no resync needed for notes" do
        card = create(:note_project_card, column: @column)

        @external_triggers.each do |trigger_type|
          refute_card_found_for_workflow(card, trigger_type, @column)
          refute_card_found_for_workflow(card, trigger_type, @column_2)
        end
      end

      test "no resync for archived cards" do
        @issue_card.archive
        @issue.close

        @external_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@issue_card, trigger_type, @column)
          refute_card_found_for_workflow(@issue_card, trigger_type, @column_2)
        end
      end

      test "pending card resync for issue and pr in triage" do
        @external_triggers.each do |trigger_type|
          if trigger_type == ProjectWorkflow::ISSUE_PENDING_CARD_ADDED_TRIGGER
            assert_card_found_for_workflow(@pending_issue_card, trigger_type, @column)
          elsif trigger_type == ProjectWorkflow::PR_PENDING_CARD_ADDED_TRIGGER
            assert_card_found_for_workflow(@pending_pr_card, trigger_type, @column)

          else
            refute_card_found_for_workflow(@pending_issue_card, trigger_type, @column)
            refute_card_found_for_workflow(@pending_pr_card, trigger_type, @column)
          end
        end
      end

      test "no resync for open issues already in a column" do
        @external_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@issue_card, trigger_type, @column)
          refute_card_found_for_workflow(@issue_card, trigger_type, @column_2)
        end
      end

      test "ISSUE_CLOSED resync for closed issue in the wrong column" do
        @issue.close
        @external_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@issue_card, trigger_type, @column)

          if trigger_type == ProjectWorkflow::ISSUE_CLOSED_TRIGGER
            assert_card_found_for_workflow(@issue_card, trigger_type, @column_2)
          else
            refute_card_found_for_workflow(@issue_card, trigger_type, @column_2)
          end
        end
      end

      test "ignore non-pending trigger resync for closed issue in triage" do
        @pending_issue.close
        @nonpending_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@pending_issue_card, trigger_type, @column)
          refute_card_found_for_workflow(@pending_issue_card, trigger_type, @column_2)
        end
      end

      test "ISSUE_REOPENED resync for reopened issue in the wrong column" do
        @issue.close
        @issue.open(@owner)
        @external_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@issue_card, trigger_type, @column)

          if ProjectWorkflow::ISSUE_REOPENED_TRIGGER == trigger_type
            assert_card_found_for_workflow(@issue_card, trigger_type, @column_2)
          else
            refute_card_found_for_workflow(@issue_card, trigger_type, @column_2)
          end
        end
      end

      test "ignore non-pending trigger resync for reopened issue in triage" do
        @pending_issue.close
        @pending_issue.open(@owner)
        @nonpending_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@pending_issue_card, trigger_type, @column)
          refute_card_found_for_workflow(@pending_issue_card, trigger_type, @column_2)
        end
      end

      test "No resync for open PR already in project" do
        @external_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@pr_card, trigger_type, @column)
          refute_card_found_for_workflow(@pr_card, trigger_type, @column_2)
        end
      end

      test "ignore non-pending trigger resync for closed PR in triage" do
        @pending_pr.close
        @nonpending_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@pr_card, trigger_type, @column)
          refute_card_found_for_workflow(@pr_card, trigger_type, @column_2)
        end
      end

      test "PR_CLOSED_NOT_MERGED for closed PR in wrong column" do
        @pr.close
        @external_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@pr_card, trigger_type, @column)
          if trigger_type == ProjectWorkflow::PR_CLOSED_NOT_MERGED_TRIGGER
            assert_card_found_for_workflow(@pr_card, trigger_type, @column_2)
          else
            refute_card_found_for_workflow(@pr_card, trigger_type, @column_2)
          end
        end
      end

      test "PR_REOPENED resync for reopened PR in wrong column" do
        Spokesd.enable_spokesd

        @pr.close
        @pr.open(@owner)
        @external_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@pr_card, trigger_type, @column)
          if ProjectWorkflow::PR_REOPENED_TRIGGER == trigger_type
            assert_card_found_for_workflow(@pr_card, trigger_type, @column_2)
          else
            refute_card_found_for_workflow(@pr_card, trigger_type, @column_2)
          end
        end
      end

      test "ignore non-pending trigger resync for reopened PR in triage" do
        Spokesd.enable_spokesd

        @pending_pr.close
        @pending_pr.open(@owner)
        @nonpending_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@pending_issue_card, trigger_type, @column)
          refute_card_found_for_workflow(@pending_issue_card, trigger_type, @column_2)
        end
      end

      test "PR_MERGED resync for merged PR in wrong column" do
        result = @pr.merge
        flunk result[1] unless result[0]

        @external_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@pr_card, trigger_type, @column)
          if trigger_type == ProjectWorkflow::PR_MERGED_TRIGGER
            assert_card_found_for_workflow(@pr_card, trigger_type, @column_2)
          else
            refute_card_found_for_workflow(@pr_card, trigger_type, @column_2)
          end
        end
      end

      test "ignore non-pending trigger resync for merged PR in triage" do
        @pending_pr.merge

        @nonpending_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@pr_card, trigger_type, @column)
          refute_card_found_for_workflow(@pr_card, trigger_type, @column_2)
        end
      end

      test "PR_APPROVED_TRIGGER for approved PR review in wrong column" do
        reviewer = create(:user)
        review = create(:pull_request_review, user: reviewer, pull_request: @pr)
        review.approve!

        @external_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@pr_card, trigger_type, @column)
          if trigger_type == ProjectWorkflow::PR_APPROVED_TRIGGER
            assert_card_found_for_workflow(@pr_card, trigger_type, @column_2)
          else
            refute_card_found_for_workflow(@pr_card, trigger_type, @column_2)
          end
        end
      end

      test "PR_PENDING_APPROVAL_TRIGGER for changes requested PR review in wrong column" do
        reviewer = create(:user)
        review = create(:pull_request_review, user: reviewer, pull_request: @pr)
        review.request_changes!

        @external_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@pr_card, trigger_type, @column)
          if trigger_type == ProjectWorkflow::PR_PENDING_APPROVAL_TRIGGER
            assert_card_found_for_workflow(@pr_card, trigger_type, @column_2)
          else
            refute_card_found_for_workflow(@pr_card, trigger_type, @column_2)
          end
        end
      end

      test "PR_PENDING_APPROVAL_TRIGGER for dismissed PR review in wrong column" do
        reviewer = create(:user)
        review = create(:pull_request_review, user: reviewer, pull_request: @pr)
        review.approve!
        review.dismiss!(@owner, message: "dismissed!")

        @external_triggers.each do |trigger_type|
          refute_card_found_for_workflow(@pr_card, trigger_type, @column)
          if trigger_type == ProjectWorkflow::PR_PENDING_APPROVAL_TRIGGER
            assert_card_found_for_workflow(@pr_card, trigger_type, @column_2)
          else
            refute_card_found_for_workflow(@pr_card, trigger_type, @column_2)
          end
        end
      end

      test "Multiple close/reopens of a PR during search period only returns card for last event" do
        Spokesd.enable_spokesd

        project = create(:project, owner: @repo)
        column = create(:project_column, project: project)
        column_2 = create(:project_column, project: project)
        column_3 = create(:project_column, project: project)

        pr_card = create(:pending_project_card, column: column, content: @pr.issue)
        pr_card.content.close
        pr_card.content.open(@owner)
        pr_card.content.close
        pr_card.content.open(@owner)

        old_pr_reopen_workflow = project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::PR_REOPENED_TRIGGER, column: column_2)
        cards = old_pr_reopen_workflow.cards_needing_resync(as_of: Time.current)
        assert_equal [pr_card.id], cards.pluck(:id)

        new_pr_reopen_workflow = project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::PR_REOPENED_TRIGGER, column: column_2)
        cards = new_pr_reopen_workflow.cards_needing_resync(as_of: Time.current)
        assert_equal [pr_card.id], cards.pluck(:id)

        closed_pr_workflow = project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::PR_CLOSED_NOT_MERGED_TRIGGER, column: column_3)
        cards = closed_pr_workflow.cards_needing_resync(as_of: Time.current)
        assert_empty cards

        new_issue_reopen_workflow = project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_REOPENED_TRIGGER, column: column_2)
        cards = new_issue_reopen_workflow.cards_needing_resync(as_of: Time.current)
        assert_empty cards
      end

      test "Multiple close/reopens of an issue during search period only returns card for last event" do
        project = create(:project, owner: @repo)
        column = create(:project_column, project: project)
        column_2 = create(:project_column, project: project)
        column_3 = create(:project_column, project: project)

        issue_card = create(:pending_project_card, column: column, content: @issue)
        issue_card.content.close
        issue_card.content.open(@owner)
        issue_card.content.close
        issue_card.content.open(@owner)

        old_issue_reopen_workflow = project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_REOPENED_TRIGGER, column: column_2)
        cards = old_issue_reopen_workflow.cards_needing_resync(as_of: Time.current)
        assert_equal [issue_card.id], cards.pluck(:id)

        new_issue_reopen_workflow = project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_REOPENED_TRIGGER, column: column_2)
        cards = new_issue_reopen_workflow.cards_needing_resync(as_of: Time.current)
        assert_equal [issue_card.id], cards.pluck(:id)

        closed_issue_workflow = project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, column: column_3)
        cards = closed_issue_workflow.cards_needing_resync(as_of: Time.current)
        assert_empty cards

        new_pr_reopen_workflow = project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::PR_REOPENED_TRIGGER, column: column_2)
        cards = new_pr_reopen_workflow.cards_needing_resync(as_of: Time.current)
        assert_empty cards
      end

      test "time bounding returns only old cards - closed issues" do
        time_0 = Time.current
        card_1 = T.let(nil, T.nilable(ProjectCard))
        Timecop.freeze(time_0 - 10.seconds) do
          card_1 = create(:project_card, column: @column_2, content: create(:issue, repository: @repo), creator: @owner)
          card_1.content.close
        end
        Timecop.freeze(time_0) do
          workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, column: @column)
          cards = workflow.cards_needing_resync(as_of: Time.current - 15.seconds)
          assert_empty cards
          cards = workflow.cards_needing_resync(as_of: Time.current)
          assert_equal [T.must(card_1).id], cards.pluck(:id)
        end
      end

      test "time bounding returns only newer cards - reopened issues" do
        time_0 = Time.current
        card_1 = T.let(nil, T.nilable(ProjectCard))
        Timecop.freeze(time_0 - 10.seconds) do
          card_1 = create(:project_card, column: @column_2, content: create(:issue, repository: @repo), creator: @owner)
          card_1.content.close
          card_1.content.open(@owner)
        end
        Timecop.freeze(time_0) do
          workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_REOPENED_TRIGGER, column: @column)
          cards = workflow.cards_needing_resync(as_of: Time.current - 15.seconds)
          assert_empty cards
          cards = workflow.cards_needing_resync(as_of: Time.current)
          assert_equal [T.must(card_1).id], cards.pluck(:id)
        end
      end

      test "time bounding returns only newer cards - merged PRs" do
        time_0 = Time.current
        card_1 = T.let(nil, T.nilable(ProjectCard))
        Timecop.freeze(time_0 - 10.seconds) do
          @pr_card.destroy
          card_1 = create(:project_card, column: @column_2, content: @pr.issue, creator: @owner)
          result = @pr.merge
          flunk result[1] unless result[0]
        end
        Timecop.freeze(time_0) do
          workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::PR_MERGED_TRIGGER, column: @column)
          cards = workflow.cards_needing_resync(as_of: Time.current - 15.seconds)
          assert_empty cards
          cards = workflow.cards_needing_resync(as_of: Time.current)
          assert_equal [T.must(card_1).id], cards.pluck(:id)
        end
      end

      test "time bounding returns only newer cards - closed PRs" do
        time_0 = Time.current
        card_1 = T.let(nil, T.nilable(ProjectCard))
        Timecop.freeze(time_0 - 10.seconds) do
          @pr_card.destroy
          card_1 = create(:project_card, column: @column_2, content: @pr.issue, creator: @owner)
          @pr.close
        end
        Timecop.freeze(time_0) do
          workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::PR_CLOSED_NOT_MERGED_TRIGGER, column: @column)
          cards = workflow.cards_needing_resync(as_of: Time.current - 15.seconds)
          assert_empty cards
          cards = workflow.cards_needing_resync(as_of: Time.current)
          assert_equal [T.must(card_1).id], cards.pluck(:id)
        end
      end

      test "time bounding returns newer cards using invalid MySQL date/time formats" do
        datetime = "2018-10-31T10:10:10.405-04:00"
        card_1 = T.let(nil, T.nilable(ProjectCard))

        # 10 seconds earlier.
        Timecop.freeze("2018-10-31T10:10:00.405-04:00") do
          @pr_card.destroy
          card_1 = create(:project_card, column: @column_2, content: @pr.issue, creator: @owner)
          @pr.close(closer = @owner)
        end

        Timecop.freeze(datetime) do
          workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::PR_CLOSED_NOT_MERGED_TRIGGER, column: @column)
          cards = workflow.cards_needing_resync(as_of: "2018-10-31T10:09:55.405-04:00") # 15 seconds earlier.
          assert_empty cards

          cards = workflow.cards_needing_resync(as_of: datetime)
          assert_equal [T.must(card_1).id], cards.pluck(:id)
        end
      end
    end

    context "Resync" do
      test "Resynced card count correct" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        card_1 = create(:project_card, column: @column, content: create(:issue, repository: @repo))
        card_1.content.close
        card_2 = create(:project_card, column: @column, content: create(:issue, repository: @repo))
        card_2.content.close
        workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, column: @column_2)
        workflow.resync!(actor: @owner, as_of: Time.current)
        assert_equal 2, GitHub.dogstats.increments("job.resync_project_workflows.card_resynced").length
      end
    end
  end

  def get_resync_cards_for_trigger_on_column(trigger, column)
    workflow = column.project.project_workflows.set_workflow(creator: @owner, trigger_type: trigger, column: column)
    workflow.cards_needing_resync(as_of: Time.current)
  end

  def assert_card_found_for_workflow(card, trigger, column)
    resync_cards = get_resync_cards_for_trigger_on_column(trigger, column)
    assert resync_cards.any? { |resync_card| resync_card.id == card.id }
  end

  def refute_card_found_for_workflow(card, trigger, column)
    resync_cards = get_resync_cards_for_trigger_on_column(trigger, column)
    refute resync_cards.any? { |resync_card| resync_card.id == card.id }
  end
end
