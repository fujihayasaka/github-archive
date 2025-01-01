# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class IssueTriageJobTest < GitHub::TestCase
  include JobTestHelper
  include HydroTestHelpers
  include DogstatsTestHelpers

  setup do
    # This is necessary for JobStatus to work
    GitHub.cache.allow = /.*/
    GitHub.cache.clear
  end

  fixtures do
    enable_feature_flag(:issue_types)
    @user = create(:user)
    @collab = create(:user)
    @org = create(:organization, admin: @user).tap { |org| org.add_member(@collab) }
    @repo = create(:repository, owner: @org).tap { |repo| repo.add_member(@collab) }

    @milestone = create(:milestone, repository: @repo)

    @issue_type_1 = @org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])
    @issue_type_2 = @org.issue_types.find_by(name: IssueType::DEFAULTS.second[:name])
  end

  def perform(issues, current_user, params)
    status = JobStatus.create
    IssueTriageJob.perform_now(status.id, issues.map(&:id), current_user.id, params)
  end

  context "setting labels" do
    test "can set multiple labels" do
      issue = create(:issue, repository: @repo)
      assert_empty issue.labels

      label_one = create(:label, repository: @repo)
      label_two = create(:label, repository: @repo)

      perform([issue], @user, labels: { label_one.id.to_s => "1", label_two.id.to_s => "1" })
      assert_same_elements [label_one, label_two], issue.reload.labels
    end

    test "succeeds if label already exists" do
      issue = create(:issue, repository: @repo)
      label = create(:label, repository: @repo)
      issue.add_labels([label])
      assert_equal [label], issue.labels

      perform([issue], @user, labels: { label.id.to_s => "1" })
      assert_equal [label], issue.labels
    end

    test "deletes labels" do
      issue = create(:issue, repository: @repo)
      label_one = create(:label, repository: @repo)
      label_two = create(:label, repository: @repo)
      issue.add_labels([label_one, label_two])
      assert_same_elements [label_one, label_two], issue.reload.labels

      perform([issue], @user, labels: { label_two.id.to_s => "0" })
      assert_equal [label_one], issue.reload.labels
    end

    test "deleting a label that isn't attached to an issue" do
      issue = create(:issue, repository: @repo)
      label = create(:label, repository: @repo)
      assert_empty issue.labels

      perform([issue], @user, labels: { label.id.to_s => "0" })
      assert_empty issue.labels
    end

    test "reports percentage" do
      issue = create(:issue, repository: @repo)
      issue2 = create(:issue, repository: @repo)
      status = JobStatusSubscription.create({ user_id: @user.id, parent_global_relay_id: issue.repository.global_relay_id })

      JobStatusSubscription.any_instance.expects(:set_percentage).with(50)

      label_one = create(:label, repository: @repo)
      label_two = create(:label, repository: @repo)
      params = {
        labels: { label_one.id.to_s => "1", label_two.id.to_s => "1" }
      }
      IssueTriageJob.perform_now(status.id, [issue, issue2].map(&:id), @user.id, params)
    end

    test "reports percentage after retry" do
      issue = create(:issue, repository: @repo)
      issue2 = create(:issue, repository: @repo)
      issue3 = create(:issue, repository: @repo)
      issue4 = create(:issue, repository: @repo)
      status = JobStatusSubscription.create({ user_id: @user.id, parent_global_relay_id: issue.repository.global_relay_id, completed_item_ids: [issue, issue2].map(&:id) })

      # verify that the set percentage method is called with the value 75
      JobStatusSubscription.any_instance.expects(:set_percentage).with(75)

      label_one = create(:label, repository: @repo)
      label_two = create(:label, repository: @repo)
      params = {
        labels: { label_one.id.to_s => "1", label_two.id.to_s => "1" }
      }
      IssueTriageJob.perform_now(status.id, [issue, issue2, issue3, issue4].map(&:id), @user.id, params)
    end
  end

  context "setting assignees" do
    test "can set one assignee" do
      issue = create(:issue, repository: @repo)
      assert_empty issue.assignees

      perform([issue], @user, assignee: @user.id.to_s)

      assert_equal @user, issue.reload.assignee
    end

    test "can set multiple assignees" do
      issue = create(:issue, repository: @repo)
      assert_empty issue.assignees

      perform([issue], @user, assignees: { @user.id.to_s => "1", @collab.id.to_s => "1" })
      assert_same_elements [@user, @collab], issue.reload.assignees
    end

    test "can clear multiple assignees" do
      issue = create(:issue, repository: @repo)
      issue.assignees = [@user, @collab]
      issue.save!

      perform([issue], @user, clear_assignees: 1)
      assert_empty issue.reload.assignees
    end

    test "can unset multiple assignees" do
      issue = create(:issue, repository: @repo)
      issue.assignees = [@user, @collab]
      issue.save

      perform([issue], @user, assignees: { @user.id.to_s => "1", @collab.id.to_s => "0" })
      assert_same_elements [@user], issue.reload.assignees
    end
  end

  context "adding to projects" do
    test "can set one project" do
      issue = create(:issue, repository: @repo)
      memex = create(:memex_project, owner: @org)
      assert_empty issue.memex_project_ids

      perform([issue], @user, projects: { memex.id.to_s => "on" })

      assert_equal [memex.id], issue.reload.memex_project_ids
    end

    test "can add pr successfully" do
      pr = create(:pull_request, :disable_disk_access, repository: @repo)
      memex = create(:memex_project, owner: @org)
      assert_empty pr.issue.memex_project_ids

      perform([pr.issue], @user, projects: { memex.id.to_s => "on" })

      assert_equal [memex.id], pr.reload.memex_project_ids
    end

    test "can set multiple projects with instrumenting hydro " do
      issue = create(:issue, repository: @repo)
      memex1 = create(:memex_project, owner: @org)
      memex2 = create(:memex_project, owner: @org)
      assert_empty issue.memex_project_ids

      perform([issue], @user, projects: { memex1.id.to_s => "on", memex2.id.to_s => "on" })

      assert_equal [memex1.id, memex2.id], issue.reload.memex_project_ids

      with_hydro_publisher(GitHub.low_latency_hydro_publisher) do
        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@user),
          number_of_issues: 1,
          number_of_prs: 0,
          number_of_projects: 2,
          issue_ids: [issue.id],
          pr_ids: [],
          projects_ids: [memex1.id, memex2.id],
          added_from: "ISSUE_INDEX"
        }, schema: "github.v1.MemexBulkAddItems")
      end
    end

    test "sets remaining issues when one is over item limit " do
      issue = create(:issue, repository: @repo)
      memex = create(:memex_project, owner: @org)
      memex_at_limit = create(:memex_project, owner: @org)
      create(:memex_project_item, memex_project: memex_at_limit)
      create(:memex_project_item, memex_project: memex_at_limit)

      fake_limit = memex_at_limit.memex_project_items.count

      MemexProjectItem.stub_const(:PER_PAGE_LIMIT, fake_limit) do
        perform([issue], @user, projects: { memex.id.to_s => "on", memex_at_limit.id.to_s => "on" })
      end

      assert_equal [memex.id], issue.reload.memex_project_ids
      report = Failbot.reports.last
      assert_equal "Triaging issue #{issue.id} failed because the project #{memex_at_limit.id} exceeded the item limit of #{fake_limit}.", Failbot.exception_message_from_hash(report)

      # Ensure the job is not marked as failed
      assert_dogstats_increment("active_job.performed", tags: ["class:issue_triage_job", "result:succeeded"])
    end

    test "can remove multiple projects with instrumenting hydro " do
      issue = create(:issue, repository: @repo)
      memex = create(:memex_project, owner: @org)

      issue.add_to_memex_projects!({ memex.id.to_s => "on" }, issue, @user)

      assert_equal issue.memex_project_ids, [memex.id]

      perform_enqueued_jobs do # rubocop:disable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
        perform([issue], @user, projects: { memex.id.to_s => "off" })
      end

      assert_equal [], issue.reload.memex_project_ids
    end

    test "does not error adding a duplicate issue" do
      issue = create(:issue, repository: @repo)
      memex = create(:memex_project, owner: @org)

      add_to_project_hash = { memex.id.to_s => "on" }
      issue.add_to_memex_projects!(add_to_project_hash, issue, @user)

      assert_equal [memex.id], issue.reload.memex_project_ids

      perform([issue], @user, projects: add_to_project_hash)

      assert_equal [memex.id], issue.reload.memex_project_ids
    end

    test "does not error adding a duplicate pull request" do
      pr = create(:pull_request, :disable_disk_access, repository: @repo)
      memex = create(:memex_project, owner: @org)

      issue = pr.issue

      add_to_project_hash = { memex.id.to_s => "on" }
      issue.add_to_memex_projects!(add_to_project_hash, pr, @user)

      assert_equal [memex.id], pr.reload.memex_project_ids

      perform([issue], @user, projects: add_to_project_hash)

      assert_equal [memex.id], pr.reload.memex_project_ids
    end

    test "can add duplicate issue that is archived in memex project" do
      issue = create(:issue, repository: @repo)
      memex = create(:memex_project, owner: @org)
      memex_project_item = create(:memex_project_item, memex_project: memex, content: issue)
      add_to_project_hash = { memex.id.to_s => "on" }

      assert memex_project_item.archive!
      assert_predicate memex_project_item.reload, :archived?
      assert_includes issue.memex_project_items, memex_project_item
      assert_no_difference "MemexProjectItem.count" do
        perform([issue], @user, projects: add_to_project_hash)
      end
      refute_predicate memex_project_item.reload, :archived?
    end

    test "can add duplicate pull request that is archived in memex project" do
      pr = create(:pull_request, :disable_disk_access, repository: @repo)
      issue = pr.issue
      memex = create(:memex_project, owner: @org)
      memex_project_item = create(:memex_project_item, memex_project: memex, content: pr)
      add_to_project_hash = { memex.id.to_s => "on" }

      assert memex_project_item.archive!
      assert_predicate memex_project_item.reload, :archived?
      assert_includes pr.memex_project_items, memex_project_item
      assert_no_difference "MemexProjectItem.count" do
        perform([issue], @user, projects: add_to_project_hash)
      end
      refute_predicate memex_project_item.reload, :archived?
    end
  end

  context "assigning milestones" do
    test "can assign a milestone" do
      issue = create(:issue, repository: @repo)
      perform([issue], @user, milestone: @milestone.id.to_s)
      issue.reload

      assert_equal @milestone, issue.milestone
      assert_equal 1, issue.events.count

      ev = issue.events.first
      assert_equal ev.event, "milestoned"
      assert_equal @milestone.title, ev.milestone_title
    end

    test "can reassign a milestone" do
      issue = create(:issue, repository: @repo, milestone: @milestone)
      milestone2 = create(:milestone, repository: @repo)
      perform([issue], @user, milestone: milestone2.id.to_s)
      issue.reload

      assert_equal milestone2, issue.milestone
      assert_equal 3, issue.events.count

      ev = issue.events.first
      assert_equal ev.event, "milestoned"
      assert_equal @milestone.title, ev.milestone_title

      ev = issue.events.second
      assert_equal ev.event, "demilestoned"
      assert_equal @milestone.title, ev.milestone_title

      ev = issue.events.third
      assert_equal ev.event, "milestoned"
      assert_equal milestone2.title, ev.milestone_title
    end
  end

  context "setting issue type" do
    test "can set an issue type" do
      issue = create(:issue, repository: @repo)
      assert_nil issue.issue_type

      perform([issue], @user, issue_type: @issue_type_1.id.to_s)
      issue.reload

      assert_equal @issue_type_1, issue.issue_type

      with_hydro_publisher(GitHub.low_latency_hydro_publisher) do
        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(@repo),
          issue: Hydro::EntitySerializer.issue(issue),
          issue_type: Hydro::EntitySerializer.issue_type(@issue_type_1),
          action: "issue.typed"
        }, schema: "github.v1.IssueUpdateIssueType")

        assert_hydro_messages count: 1, schema: "github.v1.IssueUpdateIssueType"
      end
    end

    test "can override an issue type" do
      issue = create(:issue, repository: @repo, issue_type: @issue_type_2)
      assert_equal @issue_type_2, issue.issue_type

      perform([issue], @user, issue_type: @issue_type_1.id.to_s)
      issue.reload

      assert_equal @issue_type_1, issue.issue_type

      with_hydro_publisher(GitHub.low_latency_hydro_publisher) do
        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(@repo),
          issue: Hydro::EntitySerializer.issue(issue),
          issue_type: Hydro::EntitySerializer.issue_type(@issue_type_1),
          prev_issue_type: Hydro::EntitySerializer.issue_type(@issue_type_2),
          action: "issue.typed"
        }, schema: "github.v1.IssueUpdateIssueType")

        assert_hydro_messages count: 1, schema: "github.v1.IssueUpdateIssueType"
      end
    end

    test "can unset an issue type" do
      issue = create(:issue, repository: @repo, issue_type: @issue_type_2)
      assert_equal @issue_type_2, issue.issue_type

      perform([issue], @user, issue_type: "0")
      issue.reload

      assert_nil issue.issue_type

      with_hydro_publisher(GitHub.low_latency_hydro_publisher) do
        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(@repo),
          issue: Hydro::EntitySerializer.issue(issue),
          issue_type: Hydro::EntitySerializer.issue_type(@issue_type_2),
          action: "issue.untyped"
        }, schema: "github.v1.IssueUpdateIssueType")

        assert_hydro_messages count: 1, schema: "github.v1.IssueUpdateIssueType"
      end
    end
  end

  context "changing state" do
    test "can update the state reason" do
      issue = create(:issue, repository: @repo)
      assert issue.open?

      perform([issue], @user, state: "closed", state_reason: "not_planned")
      issue.reload
      assert issue.closed?
      assert issue.state_reason == "not_planned"
    end

    test "can remove the state reason" do
      issue = create(:issue, repository: @repo)
      issue.close(@collab, attributes: { state_reason: :not_planned })

      assert issue.closed?
      assert issue.state_reason == "not_planned"

      perform([issue], @user, state: "open")
      issue.reload
      assert issue.open?
      assert_equal issue.state_reason, "reopened"
    end

    test "does not error on already merged pull request" do
      Failbot.reports.clear
      pull_request = create(:pull_request, :merged, :disable_disk_access, repository: @repo)
      assert pull_request.closed?
      assert pull_request.merged?

      perform([pull_request.issue], @user, state: "closed")
      pull_request.reload
      assert pull_request.closed?
      assert_empty Failbot.reports
    end
  end

  context "Job meta properties" do
    test "retry conditions" do
      IssueTriageJob.any_instance.stubs(:perform).raises(Aqueduct::Worker::JobKilled)
      issue = create(:issue, repository: @repo)

      status = JobStatus.create
      assert_retry_on_dirty_exit job: IssueTriageJob, args: [status.id, issue[:id], @user.id, {}]
    end

    test "Only allows a single job per user" do
      status = JobStatus.create
      issue = create(:issue, repository: @repo)
      label_one = create(:label, repository: @repo)
      params = { labels: { label_one.id.to_s => "1" } }


      assert_enqueued_jobs 1 do
        IssueTriageJob.perform_later(status.id, [issue].map(&:id), @user.id, params)
        IssueTriageJob.perform_later(status.id, [issue].map(&:id), @user.id, params)
      end
    end

    test "Reports execution errors to job status" do
      issue = create(:issue, repository: @repo)
      status = JobStatusSubscription.create({ user_id: @user.id, parent_global_relay_id: issue.repository.global_relay_id })
      label_one = create(:label, repository: @repo)
      params = { labels: { label_one.id.to_s => "1" } }

      Issue.any_instance.stubs(:save).raises(GitHub::Prioritizable::Context::LockedForRebalance)
      IssueTriageJob.perform_now(status.id, [issue].map(&:id), @user.id, params)

      JobStatusSubscription.stubs(:add_execution_error).with(
        issue.global_relay_id,
        "Triaging issue #{issue.id} failed because milestone #{params[:milestone]} is locked for rebalance."
      )
    end

    test "Reports the percentage for jobs" do
      status = JobStatusSubscription.create({ user_id: @user.id, parent_global_relay_id: "repoId" })
      job = IssueTriageJob.new
      job.send(:set_percentage, status, 10, 10, 1, 1, nil)
    end

    test "Reports the percentage for jobs II" do
      status = JobStatusSubscription.create({ user_id: @user.id, parent_global_relay_id: "repoId" })
      job = IssueTriageJob.new
      JobStatusSubscription.any_instance.expects(:set_percentage).with(0).returns(nil).once
      job.send(:set_percentage, status, 0, 10, 0, 1, nil)
    end

    test "Reports the percentage for jobs III" do
      status = JobStatusSubscription.create({ user_id: @user.id, parent_global_relay_id: "repoId" })
      job = IssueTriageJob.new
      JobStatusSubscription.any_instance.expects(:set_percentage).never
      job.send(:set_percentage, status, 29, 100, 5, 1, nil)
    end
  end

  context "checking user permissions" do
    test "allows doesn't set parameters if user doesn't have access" do
      read_user = create(:collaborator, repository: @repo, action: :read)

      memex = create(:memex_project, owner: @org)
      label_one = create(:label, repository: @repo)
      issue = create(:issue, repository: @repo, user: read_user)

      assert_empty issue.labels
      assert_empty issue.assignees
      assert_empty issue.memex_project_ids
      assert_nil issue.milestone
      assert_nil issue.issue_type

      perform(
        [issue],
        read_user,
        labels: { label_one.id.to_s => "1" },
        projects: { memex.id.to_s => "on" },
        assignees: { @user.id.to_s => "1" },
        milestone: @milestone.id.to_s,
        issue_type: @issue_type_1.id.to_s
      )

      issue.reload
      assert_empty issue.labels
      assert_empty issue.assignees
      assert_empty issue.memex_project_ids
      assert_nil issue.milestone
      assert_nil issue.issue_type
    end

    test "sets partial parameters if user cannot label but can assign" do
      Issue.any_instance.stubs(:labelable_by?).returns(false)

      memex = create(:memex_project, owner: @org)
      label_one = create(:label, repository: @repo)
      issue = create(:issue, repository: @repo, user: @user)

      assert_empty issue.labels
      assert_empty issue.assignees
      assert_empty issue.memex_project_ids
      assert_nil issue.milestone
      assert_nil issue.issue_type

      perform(
        [issue],
        @user,
        labels: { label_one.id.to_s => "1" },
        projects: { memex.id.to_s => "on" },
        assignees: { @user.id.to_s => "1" },
        milestone: @milestone.id.to_s,
        issue_type: @issue_type_1.id.to_s
      )

      issue.reload
      assert_empty issue.labels
      assert_same_elements [@user], issue.assignees
      assert_equal @milestone, issue.milestone
      assert_equal @issue_type_1, issue.issue_type
      assert_same_elements [memex.id], issue.memex_project_ids
    end
  end
end
