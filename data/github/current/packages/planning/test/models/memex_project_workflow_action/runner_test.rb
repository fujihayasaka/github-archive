# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectWorkflowRunnerTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    # ensure Integration is created
    make_trusted_oauth_apps_owner
    Apps::Privileged::MemexAutomation.seed_database!
    Apps::Privileged::MemexAutomation.reload!
  end

  context "action is get_items action" do
    test "filters items that match the query `is:issue is:closed`" do
      owner = create(:user)
      repository = create(:repository, owner: owner)
      action = build_get_items_action(query: "is:issue is:closed", repository_id: repository.id, last_updater: owner)
      items = [
        create(:issue, repository: repository, state: "closed"),
        create(:issue, repository: repository, state: "open")
      ]

      output = MemexProjectWorkflowAction::Runner.run(action: action, input: items, actor: owner, tags: ["topic:github.memex_automation.v0.IssueCreateEvent"])

      assert_equal 1, output.count
      assert output.first.closed?
    end

    test "filters items that match the query `reason:completed`" do
      owner = create(:user)
      repository = create(:repository, owner: owner)
      action = build_get_items_action(query: "reason:completed", repository_id: repository.id, last_updater: owner)
      items = [
        create(:issue, repository: repository, state: "closed", state_reason: :not_planned),
        create(:issue, repository: repository, state: "closed")
      ]

      output = MemexProjectWorkflowAction::Runner.run(action: action, input: items, actor: owner, tags: ["topic:github.memex_automation.v0.IssueCreateEvent"])

      assert_equal 1, output.count
      assert output.first.closed?
      assert output.first.state_reason.nil?
    end

    test "filters items that match the query `reason:\"not planned\"`" do
      owner = create(:user)
      repository = create(:repository, owner: owner)
      action = build_get_items_action(query: "is:issue is:closed reason:\"not planned\"", repository_id: repository.id, last_updater: owner)
      items = [
        create(:issue, repository: repository, state: "closed"),
        create(:issue, repository: repository, state: "closed", state_reason: :not_planned)
      ]

      output = MemexProjectWorkflowAction::Runner.run(action: action, input: items, actor: owner, tags: ["topic:github.memex_automation.v0.IssueCreateEvent"])

      assert_equal 1, output.count
      assert output.first.closed?
      assert output.first.state_reason_not_planned?
    end

    test "filters items that match the query `reason:reopened`" do
      owner = create(:user)
      repository = create(:repository, owner: owner)
      action = build_get_items_action(query: "reason:reopened", repository_id: repository.id, last_updater: owner)
      items = [
        create(:issue, repository: repository, state: "open"),
        create(:issue, repository: repository, state: "open", state_reason: :reopened)
      ]

      output = MemexProjectWorkflowAction::Runner.run(action: action, input: items, actor: owner, tags: ["topic:github.memex_automation.v0.IssueCreateEvent"])

      assert_equal 1, output.count
      assert output.first.open?
      assert output.first.state_reason_reopened?
    end

    test "filters items that match the query `is:pr`" do
      owner = create(:user)
      repository = create(:repository, owner: owner)
      action = build_get_items_action(query: "is:pr", repository_id: repository.id, last_updater: owner)
      items = [
        create(:issue, repository: repository, state: "open"),
        create(:pull_request, :disable_disk_access, repository: repository, user: owner)
      ]
      output = MemexProjectWorkflowAction::Runner.run(action: action, input: items, actor: owner, tags: ["topic:github.memex_automation.v0.IssueCreateEvent"])

      assert_equal 1, output.count
      assert output.first.pull_request?
    end

    test "filters items that match the query `is:merged`" do
      owner = create(:user)
      repository = create(:repository, owner: owner)
      action = build_get_items_action(query: "is:merged", repository_id: repository.id, last_updater: owner)
      items = [
        create(:issue, repository: repository, state: "open"),
        create(:pull_request, :disable_disk_access, repository: repository, user: owner, merged_at: Time.now)
      ]
      output = MemexProjectWorkflowAction::Runner.run(action: action, input: items, actor: owner, tags: ["topic:github.memex_automation.v0.IssueCreateEvent"])

      assert_equal 1, output.count
      assert output.first.pull_request?
    end
  end

  context "action is add_project_item" do
    test "adds input items to the project" do
      owner = create(:user)
      repo = create(:repository, owner: owner)
      project = create(:memex_project, owner: owner)
      workflow = create(:memex_project_workflow, memex_project: project)
      action = MemexProjectWorkflowAction.new(
        arguments: {},
        action_type: :add_project_item,
        workflow: workflow
      )
      items = [
        create(:issue, repository: repo),
        create(:issue, repository: repo)
      ]
      output = MemexProjectWorkflowAction::Runner.run(action: action, input: items, actor: owner)

      assert_equal 2, output.count
      output.each do |item|
        assert item.is_a?(MemexProjectItem)
        assert_equal "Issue", item.content_type
      end
      assert_equal 2, project.memex_project_items.count
    end
  end

  context "action is get_project_items" do
    test "find items in project" do
      user = create(:user)
      org = create(:organization)
      repo = create(:repository, owner: org)
      project = create(:memex_project, owner: org)
      issue1 = create(:issue, repository: repo, state: "opened")
      issue2 = create(:issue, repository: repo, state: "opened")
      issue3 = create(:issue, repository: repo, state: "opened")
      pull1 = create(:pull_request, :disable_disk_access, repository: repo, user: user)

      workflow = create(:memex_project_workflow, memex_project: project)
      action = MemexProjectWorkflowAction.new(
        arguments: {},
        action_type: :get_project_items,
        workflow: workflow
      )
      workflow.actions << action

      output = MemexProjectWorkflowAction::Runner.run(
        action: action,
        input: [
          create(:memex_project_item, content_type: "Issue", content_id: issue1.id, memex_project: project),
          create(:memex_project_item, content_type: "Issue", content_id: issue2.id, memex_project: project),
          create(:memex_project_item, content_type: "PullRequest", content_id: pull1.id, memex_project: project),
        ],
        actor: user
      )

      assert_equal 3, output.count
      assert output.all? { |item| item.is_a?(MemexProjectItem) }
      assert_equal %w[Issue Issue PullRequest], output.map(&:content_type)
    end

    test "find filtered items in project with `is` and `reason` keywords" do
      user = create(:user)
      org = create(:organization)
      repo = create(:repository, owner: org)
      project = create(:memex_project, owner: org)
      issue1 = create(:issue, repository: repo, state: "opened")
      issue2 = create(:issue, repository: repo, state: "closed", state_reason: :not_planned)
      issue3 = create(:issue, repository: repo, state: "closed")
      pull1 = create(:pull_request, :disable_disk_access, repository: repo, user: user)

      expected = create(:memex_project_item, content_type: "Issue", content_id: issue2.id, memex_project: project)

      workflow = create(:memex_project_workflow, memex_project: project)
      action = MemexProjectWorkflowAction.new(
        arguments: { "query" => "is:closed reason:\"not planned\"" },
        action_type: :get_project_items,
        workflow: workflow
      )
      workflow.actions << action

      output = MemexProjectWorkflowAction::Runner.run(
        action: action,
        input: [
          create(:memex_project_item, content_type: "Issue", content_id: issue1.id, memex_project: project),
          create(:memex_project_item, content_type: "Issue", content_id: issue3.id, memex_project: project),
          create(:memex_project_item, content_type: "PullRequest", content_id: pull1.id, memex_project: project),
          expected,
        ],
        actor: user
      )

      assert_equal 1, output.count
      assert output.first.is_a?(MemexProjectItem)
      assert output.first.id == expected.id
    end

    test "find filtered items in project with `last-updated` keyword" do
      user = create(:user)
      org = create(:organization)
      repo = create(:repository, owner: org)
      project1 = create(:memex_project, title: "p1", owner: org)
      issue = create(:issue, repository: repo, state: "closed", updated_at: 4.days.ago)
      item = create(:memex_project_item, memex_project: project1, updated_at: 4.days.ago, content_type: "Issue", content_id: issue.id,)

      expected = [item]

      workflow = create(:memex_project_workflow, memex_project: project1)
      action = MemexProjectWorkflowAction.new(
        arguments: { "query" => "last-updated:1day" },
        action_type: :get_project_items,
        workflow: workflow
      )
      workflow.actions << action

      output = MemexProjectWorkflowAction::Runner.run(
        action: action,
        input: [
          item,
        ],
        actor: user
      )

      assert_equal 1, output.count
      assert_equal expected, output
    end

    test "find filtered items in project with `last-updated` keyword when `updated_at` differ between MemexItem and MemexItem content" do
      user = create(:user)
      org = create(:organization)
      repo = create(:repository, owner: org)
      project1 = create(:memex_project, title: "p1", owner: org)
      issue = create(:issue, repository: repo, state: "closed", updated_at: 4.days.ago)
      item = create(:memex_project_item, memex_project: project1, updated_at: 1.minute.ago, content_type: "Issue", content_id: issue.id,)

      expected = []

      workflow = create(:memex_project_workflow, memex_project: project1)
      action = MemexProjectWorkflowAction.new(
        arguments: { "query" => "last-updated:1day" },
        action_type: :get_project_items,
        workflow: workflow
      )
      workflow.actions << action

      output = MemexProjectWorkflowAction::Runner.run(
        action: action,
        input: [
          item,
        ],
        actor: user
      )

      assert_equal 0, output.count
      assert_equal expected, output
    end

    test "find filtered item in project with `last-updated` keyword when the same content is updated at different times for different projects" do
      user = create(:user)
      org = create(:organization)
      repo = create(:repository, owner: org)
      project1 = create(:memex_project, title: "p1", owner: org)
      project2 = create(:memex_project, title: "p2", owner: org)
      issue = create(:issue, repository: repo, state: "closed", updated_at: 4.days.ago)
      item1 = create(:memex_project_item, memex_project: project1, updated_at: 4.days.ago, content_type: "Issue", content_id: issue.id,)
      item2 = create(:memex_project_item, memex_project: project2, updated_at: 1.minute.ago, content_type: "Issue", content_id: issue.id,)

      expected = [item1]
      expected_negated = [item2]

      workflow = create(:memex_project_workflow, memex_project: project1)
      action = MemexProjectWorkflowAction.new(
        arguments: { "query" => "last-updated:1day" },
        action_type: :get_project_items,
        workflow: workflow
      )
      workflow.actions << action

      output = MemexProjectWorkflowAction::Runner.run(
        action: action,
        input: [
          item1,
          item2,
        ],
        actor: user
      )

      workflow_negated = create(:memex_project_workflow, :skip_validations, memex_project: project1, name: "negated query workflow")
      action_negated = MemexProjectWorkflowAction.new(
        arguments: { "query" => "-last-updated:1day" },
        action_type: :get_project_items,
        workflow: workflow
      )
      workflow_negated.actions << action_negated

      output_negated = MemexProjectWorkflowAction::Runner.run(
        action: action_negated,
        input: [
          item1,
          item2,
        ],
        actor: user
      )

      assert_equal 1, output.count
      assert_equal expected, output

      assert_equal 1, output_negated.count
      assert_equal expected_negated, output_negated
    end

    test "find filtered items in project with `-last-updated` keyword" do
      user = create(:user)
      org = create(:organization)
      repo = create(:repository, owner: org)
      project1 = create(:memex_project, title: "p1", owner: org)
      issue = create(:issue, repository: repo, state: "closed", updated_at: 2.days.ago)
      item = create(:memex_project_item, memex_project: project1, updated_at: 2.days.ago, content_type: "Issue", content_id: issue.id,)

      expected = [item]

      workflow = create(:memex_project_workflow, memex_project: project1)
      action = MemexProjectWorkflowAction.new(
        arguments: { "query" => "-last-updated:6days" },
        action_type: :get_project_items,
        workflow: workflow
      )
      workflow.actions << action

      output = MemexProjectWorkflowAction::Runner.run(
        action: action,
        input: [
          item,
        ],
        actor: user
      )

      assert_equal 1, output.count
      assert_equal expected, output
    end

    test "find filtered items in project with `-last-updated` keyword when `updated_at` differ between MemexItem and MemexItem content" do
      user = create(:user)
      org = create(:organization)
      repo = create(:repository, owner: org)
      project1 = create(:memex_project, title: "p1", owner: org)
      issue = create(:issue, repository: repo, state: "closed", updated_at: 4.days.ago)
      item = create(:memex_project_item, memex_project: project1, updated_at: 7.days.ago, content_type: "Issue", content_id: issue.id,)

      expected = [item]

      workflow = create(:memex_project_workflow, memex_project: project1)
      action = MemexProjectWorkflowAction.new(
        arguments: { "query" => "-last-updated:6days" },
        action_type: :get_project_items,
        workflow: workflow
      )
      workflow.actions << action

      output = MemexProjectWorkflowAction::Runner.run(
        action: action,
        input: [
          item,
        ],
        actor: user
      )

      assert_equal 1, output.count
      assert_equal expected, output
    end

    test "find filtered item in project with `-last-updated` keyword when the same content is updated at different times for different projects" do
      user = create(:user)
      org = create(:organization)
      repo = create(:repository, owner: org)
      project1 = create(:memex_project, title: "p1", owner: org)
      project2 = create(:memex_project, title: "p2", owner: org)
      issue = create(:issue, repository: repo, state: "closed", updated_at: 4.days.ago)
      item1 = create(:memex_project_item, memex_project: project1, updated_at: 4.days.ago, content_type: "Issue", content_id: issue.id,)
      item2 = create(:memex_project_item, memex_project: project2, updated_at: 7.days.ago, content_type: "Issue", content_id: issue.id,)

      expected = [item1, item2]

      workflow = create(:memex_project_workflow, memex_project: project1)
      action = MemexProjectWorkflowAction.new(
        arguments: { "query" => "-last-updated:6days" },
        action_type: :get_project_items,
        workflow: workflow
      )
      workflow.actions << action

      output = MemexProjectWorkflowAction::Runner.run(
        action: action,
        input: [
          item1,
          item2,
        ],
        actor: user
      )

      assert_equal 2, output.count
      assert_equal expected, output
    end
  end

  private

  def build_get_items_action(query:, repository_id:, last_updater:)
    project = create(:memex_project, owner: last_updater)
    workflow = create(:memex_project_workflow, memex_project: project)
    action = MemexProjectWorkflowAction.new(
      arguments: { "query" => query, "repositoryId" => repository_id },
      action_type: :get_items,
      workflow: workflow,
      last_updater: last_updater
    )
    workflow.actions << action
    action
  end
end
