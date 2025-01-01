# typed: true
# frozen_string_literal: true

require "test_helper"

class SetFieldProcessorTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers

  setup do
    # ensure Integration is created
    make_trusted_oauth_apps_owner
    Apps::Privileged::MemexAutomation.seed_database!
    Apps::Privileged::MemexAutomation.reload!

    @tags = [
      "queue:test_queue",
      "topic:TestTopic"
    ]

    @actor = create(:user)
  end

  context "closed => set_field" do
    test "triggers column update for 1 issue" do
      Timecop.freeze do
        workflow = create_workflow
        project = workflow.memex_project
        project_item = create_item(project: project)
        status_column = project_status_column(project)
        column_value = create_status_column_value(project_item, status_column)

        run_workflows(
          workflow: workflow,
          content_type: project_item.content_type,
          project_items: [project_item],
          trigger_type: :closed
        )
        assert column_value.reload.value == done_option_id(status_column)

        assert_hydro_published({
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(Apps::Privileged::MemexAutomation.bot),
          project_column: Hydro::EntitySerializer.memex_project_column(status_column),
          project_item: Hydro::EntitySerializer.memex_project_item(project_item),
          project: Hydro::EntitySerializer.memex_project(project),
          value: done_option_id(status_column),
          previous_value: todo_option_id(status_column)
        }, schema: "github.memex.v0.MemexProjectColumnValueUpdate")
      end
    end

    test "triggers column update for 1 pull request" do
      workflow = create_workflow
      project = workflow.memex_project
      project_item = create_item(project: project, pull: true)
      status_column = project_status_column(project)
      column_value = create_status_column_value(project_item, status_column)

      run_workflows(
        workflow: workflow,
        content_type: project_item.content_type,
        project_items: [project_item],
        trigger_type: :closed
      )
      assert column_value.reload.value == done_option_id(status_column)
    end

    test "triggers column update for multiple items" do
      records = []
      workflow = create_workflow
      project = workflow.memex_project
      status_column = project_status_column(project)

      3.times do
        project_item = create_item(project: project)
        records.push(
          project_item: project_item,
          status_column: status_column,
          column_value: create_status_column_value(project_item, status_column)
        )
      end
      project_items = records.map { |record| record[:project_item] }

      assert_max_query_count_per_table({
        # This memex_projects query isn't issued in our runner code. It fires
        # as part of post-update instrumentation when column values are
        # updated.
        # 1 SELECT + 3 UPDATES
        memex_projects: 4,
        # There should only one query to get columns, because we get them in
        # a single batch.
        memex_project_columns: 1,
        # These are the queries for our 3 items that actually update the column
        # value to the new column option id.
        # 1 SELECT + 3 UPDATES
        memex_project_column_values: 4,
        # We should not be SELECT querying project items at all since they get passed
        # in on instantiation.
        # 3 UPDATES
        memex_project_items: 3,
        # We issue 1 query to find all workflows for our collection of
        # project ids.
        memex_project_workflows: 1,
        # We issue 1 query to find all actions related to our collection of
        # project ids.
        memex_project_workflow_actions: 1
      }, backtrace_lines: 1) do

        run_workflows(
          workflow: workflow,
          content_type: project_items.first.content_type,
          project_items: project_items,
          trigger_type: :closed
        )
      end

      records.each do |record|
        assert record[:column_value].reload.value == done_option_id(record[:status_column])
      end
    end


    test "column value writes are throttled" do
      batch_size = 2
      MemexProjectColumnValue.expects(:throttle).yields.times(batch_size)
      project_items = T.let([], T::Array[MemexProjectItem])

      workflow = create_workflow
      project = workflow.memex_project
      status_column = project_status_column(project)

      4.times do
        project_item = create_item(project: project)
        create_status_column_value(project_item, status_column)
        project_items << project_item
      end

      MemexProjectWorkflow::SetFieldProcessor.stub_const(:BATCH_SIZE, batch_size) do
        run_workflows(
          workflow: workflow,
          content_type: T.must(project_items.first).content_type,
          project_items: project_items,
          trigger_type: :closed
        )
      end
    end
  end

  context "item_added => set_field" do
    test "triggers column update for 1 issue with no status column value" do
      project = create(:memex_project)
      workflow = create_workflow(project, ["Issue"], :item_added)
      project_item = create_item(project: project)
      status_column = project_status_column(project)

      column_value = MemexProjectColumnValue.find_by(memex_project_item_id: project_item.id, memex_project_column_id: status_column.id)
      assert_nil column_value

      run_workflows(
        workflow: workflow,
        content_type: project_item.content_type,
        project_items: [project_item],
        trigger_type: :item_added
      )

      column_value = MemexProjectColumnValue.find_by(memex_project_item_id: project_item.id, memex_project_column_id: status_column.id)
      assert column_value&.value == todo_option_id(status_column)
    end

    test "does nothing for 1 issue with existing column value" do
      project = create(:memex_project)
      workflow = create_workflow(project, ["Issue"], :item_added)
      project_item = create_item(project: project)
      status_column = project_status_column(project)

      default_status_value = status_column.settings["options"].first["id"]
      column_value = create(:memex_project_column_value, column: status_column, value: default_status_value, item: project_item)

      run_workflows(
        workflow: workflow,
        content_type: project_item.content_type,
        project_items: [project_item],
        trigger_type: :item_added
      )
      assert column_value.reload.value == default_status_value

      assert_dogstats_increment(
        1,
        MemexHydroProjectAutomation::Instrumentation::SetFieldProcessor::METRIC_SKIPPED,
        tags: ["trigger_type:item_added", "reason:#{MemexHydroProjectAutomation::Instrumentation::SetFieldProcessor::REASON_COLUMN_VALUE_EXISTS}"]
      )
    end

    context "string trigger type" do
      test "does nothing for 1 issue with existing column value" do
        project = create(:memex_project)
        workflow = create_workflow(project, ["Issue"], :item_added)
        project_item = create_item(project: project)
        status_column = project_status_column(project)

        default_status_value = status_column.settings["options"].first["id"]
        column_value = create(:memex_project_column_value, column: status_column, value: default_status_value, item: project_item)

        run_workflows(
          workflow: workflow,
          content_type: project_item.content_type,
          project_items: [project_item],
          trigger_type: "item_added"
        )
        assert column_value.reload.value == default_status_value

        assert_dogstats_increment(
          1,
          MemexHydroProjectAutomation::Instrumentation::SetFieldProcessor::METRIC_SKIPPED,
          tags: ["trigger_type:item_added", "reason:#{MemexHydroProjectAutomation::Instrumentation::SetFieldProcessor::REASON_COLUMN_VALUE_EXISTS}"]
        )
      end
    end
  end

  context "review_approved => set_field" do
    test "on a protected branch, review_approved workflow requires approval counts to be met before updating the status" do
      approval_user1 = create(:verified_user)
      approval_user2 = create(:verified_user)

      repository = create_repository_with_write_members(@actor, approval_user1, approval_user2)
      base_ref, head_ref = create_refs_with_commit_difference(repository)

      create(
        :protected_branch,
        repository: repository,
        name: base_ref.name,
        pull_request_reviews_enforcement_level: :everyone,
        required_approving_review_count: 2
      )

      pr = create_pull_request(repository, @actor, base_ref, head_ref)
      project = create_project_with_default_workflow(enabled_triggers: ["review_approved"])
      workflow = project.workflows.find_by(trigger_type: "review_approved")
      status_column = project_status_column(project)
      expected_id = status_option_id_from_name(status_column, "In Progress")

      project_item = create(:memex_project_item, memex_project: project, content: pr)
      column_value = create_status_column_value(project_item, status_column)

      pr.reviews.create!(user: approval_user1, head_sha: pr.head_sha).tap { |r| r.approve! }

      project_item.reload
      run_workflows(
        workflow: workflow,
        content_type: project_item.content_type,
        project_items: [project_item],
        trigger_type: :review_approved
      )

      refute_equal expected_id, column_value.reload.value

      assert_dogstats_increment(
        1,
        MemexHydroProjectAutomation::Instrumentation::SetFieldProcessor::METRIC_SKIPPED,
        tags: ["trigger_type:review_approved", "reason:#{MemexHydroProjectAutomation::Instrumentation::SetFieldProcessor::REASON_REVIEWS_NOT_FULLFILED}"]
      )

      pr.reviews.create!(user: approval_user2, head_sha: pr.head_sha).tap { |r| r.approve! }

      project_item.reload
      run_workflows(
        workflow: workflow,
        content_type: project_item.content_type,
        project_items: [project_item],
        trigger_type: :review_approved
      )

      assert_equal expected_id, column_value.reload.value
    end

    test "on a non-protected branch, PR status is updated already after one approving review" do
      approval_user = create(:verified_user)

      repository = create_repository_with_write_members(@actor, approval_user)
      base_ref, head_ref = create_refs_with_commit_difference(repository)

      pr = create_pull_request(repository, @actor, base_ref, head_ref)
      project = create_project_with_default_workflow(enabled_triggers: ["review_approved"])
      status_column = project_status_column(project)
      expected_id = status_option_id_from_name(status_column, "In Progress")

      project_item = create(:memex_project_item, memex_project: project, content: pr)
      column_value = create_status_column_value(project_item, status_column)

      pr.reviews.create!(user: approval_user, head_sha: pr.head_sha).tap { |r| r.approve! }

      run_workflows(
        workflow: project.workflows.find_by(trigger_type: "review_approved"),
        content_type: project_item.content_type,
        project_items: [project_item],
        trigger_type: :review_approved
      )

      assert_equal expected_id, column_value.reload.value
    end

    test "when a PR is already merged, review_approved workflow does not update the PR status" do
      approval_user = create(:verified_user)

      repository = create_repository_with_write_members(@actor, approval_user)
      base_ref, head_ref = create_refs_with_commit_difference(repository)

      pr = create_pull_request(repository, @actor, base_ref, head_ref)
      project = create_project_with_default_workflow(enabled_triggers: ["review_approved"])
      status_column = project_status_column(project)
      expected_id_if_workflow_ran = status_option_id_from_name(status_column, "In Progress")

      project_item = create(:memex_project_item, memex_project: project, content: pr)
      column_value = create_status_column_value(project_item, status_column)
      previous_value = column_value.value

      pr.reviews.create!(user: approval_user, head_sha: pr.head_sha).tap { |r| r.approve! }
      pr.merge
      project_item.reload

      run_workflows(
        workflow: project.workflows.find_by(trigger_type: "review_approved"),
        content_type: project_item.content_type,
        project_items: [project_item],
        trigger_type: :review_approved
      )

      refute_equal expected_id_if_workflow_ran, column_value.reload.value
      assert_equal previous_value, column_value.reload.value

      assert_dogstats_increment(
        1,
        MemexHydroProjectAutomation::Instrumentation::SetFieldProcessor::METRIC_SKIPPED,
        tags: ["trigger_type:review_approved", "reason:#{MemexHydroProjectAutomation::Instrumentation::SetFieldProcessor::REASON_PULL_REQUEST_MERGED}"]
      )
    end
  end

  private

  def create_workflow(project = create(:memex_project), content_types = %w[Issue PullRequest], trigger_type = :closed, name = "Closed Workflow")
    create(:memex_project_workflow, memex_project: project, enabled: true, content_types: content_types, trigger_type: trigger_type, name: name)
  end

  def create_item(project: create(:memex_project), pull: false)
    content = pull ? create(:pull_request, :disable_disk_access) : create(:issue)
    create(:memex_project_item, memex_project: project, content: content)
  end

  def project_status_column(project)
    project.status_column
  end

  def todo_option_id(status_column)
    status_option_id_from_name(status_column, "Todo")
  end

  def done_option_id(status_column)
    status_option_id_from_name(status_column, "Done")
  end

  def status_option_id_from_name(status_column, name)
    status_column
      .settings["options"]
      .find { |option| option["name"] == name }&.dig("id")
  end

  def create_status_column_value(project_item, status_column)
    default_status_value = status_column.settings["options"].first["id"]
    create(:memex_project_column_value, column: status_column, value: default_status_value, item: project_item)
  end

  def run_workflows(**kwargs)
    MemexProjectWorkflow::SetFieldProcessor.run(
      input: kwargs[:project_items],
      trigger_type: kwargs[:trigger_type],
      action: kwargs[:workflow].actions.first,
      actor: @actor,
      tags: @tags
    )
  end

  def create_repository_with_write_members(owner, *users)
    create(:repository, owner: owner).tap do |repo|
      users.each { |u| repo.add_member(u, action: :write) }
      example_repo(:simple, repo)
    end
  end

  def create_refs_with_commit_difference(repository, commit_count: 1)
    base_ref = repository.heads.find_or_build(repository.default_branch)
    head_ref = repository.heads.create("test-branch", base_ref.target, @actor).tap do |ref|
      commit_count.times do |i|
        ref.append_commit({ message: "some changes #{i}", committer: @actor }, @actor) do |files|
          files.add("file00#{i}", "foo-#{i}")
        end
      end
    end
    [base_ref, head_ref]
  end

  def create_pull_request(repository, creator, base_ref, head_ref)
    create(
      :pull_request,
      repository: repository,
      base_repository: repository,
      base_user: creator,
      base_ref: base_ref.name,
      head_repository: repository,
      head_user: creator,
      head_ref: head_ref.name,
      user: creator,
      base_sha: repository.heads[base_ref.name].sha,
      head_sha: repository.heads[head_ref.name].sha,
    ). tap { |pull| pull.create_merge_commit }
  end

  def create_project_with_default_workflow(enabled_triggers: [])
    create(:memex_project, :with_default_workflows, owner: @actor).tap do |p|
      enabled_triggers.each do |trigger_type|
        p.workflows.find_by(trigger_type: trigger_type)&.update!(enabled: true)
      end
    end
  end
end
