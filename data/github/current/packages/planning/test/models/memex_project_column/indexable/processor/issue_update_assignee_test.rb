# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueUpdateAssigneeTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @repo = create(:repository, owner: @actor)
    @user = create(:user)
    @repo.add_member(@user)
    @project = create(:memex_project, owner: @actor, title: "test project")
    @assignees_field = @project.columns.find(&:assignees?).to_field
  end

  setup do
    setup_search
  end

  teardown do
    teardown_search
  end

  context "#subscriptions" do
    test "invoked on update assignee event" do
      issue = create(:assigned_issue, repository: @repo)
      project_item = create(:memex_project_item, content: issue, memex_project: @project)
      reset_hydro

      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateAssignee, "github.v1.IssueUpdateAssignee") do
        issue.update!(assignees: [issue.assignee, @user])
      end
    end
  end

  context "#update" do
    test "updates with new assignee" do
      issue = create(:assigned_issue, repository: @repo)
      project_item = create(:memex_project_item, content: issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      doc = get_doc(project_item.id)
      expected_document = @assignees_field.elasticsearch_field_value(project_item).to_hash
      actual_document = field(doc, @assignees_field.id).deep_symbolize_keys
      assert_equal expected_document, actual_document

      assignees = [issue.assignee, @user]
      issue.assignees = assignees
      issue.save!
      message = issue_update_assignee_message(issue: issue, assignees: assignees)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateAssignee.new(message)
      response = processor.update(es_client)

      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.first&.update&.result
      doc = get_doc(project_item.id)
      field_value = field_value(doc, @assignees_field)
      assignees.each do |assignee|
        assert field_value.find { _1["id"] == assignee.id }, "Field value does not include assignee #{assignee.id}"
      end
    end

    test "updates when assignee removed" do
      issue = create(:assigned_issue, repository: @repo)
      issue_assignee = issue.assignee
      assignees = [issue_assignee, @user]
      issue.assignees = assignees
      issue.save!
      project_item = create(:memex_project_item, content: issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      issue.assignees = [@user]
      issue.save!
      message = issue_update_assignee_message(issue: issue, assignees: [@user])
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateAssignee.new(message)
      response = processor.update(es_client)

      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.first&.update&.result
      doc = get_doc(project_item.id)
      field_value = field_value(doc, @assignees_field)
      refute field_value.find { _1["id"] == issue_assignee.id }
      assert field_value.find { _1["id"] == @user.id }
    end

    test "removes field when all assignees deleted" do
      issue = create(:assigned_issue, repository: @repo)
      project_item = create(:memex_project_item, content: issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      issue.assignees = []
      issue.save!
      message = issue_update_assignee_message(issue: issue, assignees: [])
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateAssignee.new(message)
      response = processor.update(es_client)

      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.first&.update&.result
      doc = get_doc(project_item.id)
      refute field(doc, @assignees_field.id)
    end


    test "noops when matching value already found in any order" do
      issue = create(:issue, repository: @repo)
      issue.assignees = [@actor, @user]
      issue.save!
      project_item = create(:memex_project_item, content: issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      assignees = [@user, @actor]
      message = issue_update_assignee_message(issue: issue, assignees: assignees)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateAssignee.new(message)
      response = processor.update(es_client)
      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop, response.items.first&.update&.result

      message = issue_update_assignee_message(issue: issue, assignees: assignees.reverse)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateAssignee.new(message)
      response = processor.update(es_client)
      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop, response.items.first&.update&.result
    end
  end

  test "provides correct project ids for resyncing on failure" do
    issue = create(:issue, repository: @repo, state: "open")
    create(:memex_project_item, memex_project: @project, content: issue)
    project_2 = create(:memex_project)
    create(:memex_project_item, memex_project: project_2, content: issue)
    issue.assignee = @actor

    message = issue_update_assignee_message(issue: issue, assignees: issue.assignees)
    processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateAssignee.new(message)
    assert_equal [@project.id, project_2.id].sort, processor.project_ids_to_resync_on_failure.sort
  end

  test "provides correct project ids for resyncing pull request on failure" do
    pull = create(:pull_request, :disable_disk_access, repository: @repo)
    create(:memex_project_item, memex_project: @project, content: pull)
    project_2 = create(:memex_project)
    create(:memex_project_item, memex_project: project_2, content: pull)
    pull.issue.assignee = @actor

    message = issue_update_assignee_message(issue: pull.issue, assignees: pull.issue.assignees, pull: pull)
    processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateAssignee.new(message)
    assert_equal [@project.id, project_2.id].sort, processor.project_ids_to_resync_on_failure.sort
  end

  test "provides correct updated models" do
    issue = create(:issue, repository: @repo, state: "open")
    item_1 = create(:memex_project_item, memex_project: @project, content: issue)
    project_2 = create(:memex_project)
    item_2 = create(:memex_project_item, memex_project: project_2, content: issue)
    issue.assignee = @actor

    message = issue_update_assignee_message(issue: issue, assignees: issue.assignees)
    processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateAssignee.new(message)
    assert_same_elements [issue, item_1, item_2], processor.updated_models
  end

  def issue_update_assignee_message(issue:, assignees:, pull: nil)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        repository: Hydro::EntitySerializer.repository(@repo),
        issue: Hydro::EntitySerializer.issue(issue),
        pull_request: Hydro::EntitySerializer.pull_request(pull),
        assignees: Hydro::EntitySerializer.users(assignees),
        action: "issue.events.assigned"
      },
      schema: "github.v1.IssueUpdateAssignee"
    )
  end
end
