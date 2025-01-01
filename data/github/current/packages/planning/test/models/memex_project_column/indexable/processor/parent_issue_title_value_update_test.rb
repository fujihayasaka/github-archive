# typed: true
# frozen_string_literal: true

require "test_helper"

class ParentIssueTitleValueUpdateTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @repo = create(:repository, owner: @actor)
    @user = create(:user)
    @repo.add_member(@user)
    @project = create(:memex_project, owner: @actor, title: "test project")
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
    @parent = create(:issue, repository: @repo, title: "parent")
    @child1 = create(:issue, repository: @repo, title: "child1")
    @child2 = create(:issue, repository: @repo, title: "child2")
    @parent.add_sub_issue!(@child1, @actor.id)
    @parent.add_sub_issue!(@child2, @actor.id)
    @parent_issue_field = @project.columns.find(&:parent_issue?).to_field
    @irrelevant_issue = create(:issue, repository: @repo)
    @project_items = [
      create(:memex_project_item, content: @child1, memex_project: @project),
      create(:memex_project_item, content: @child2, memex_project: @project),
      create(:memex_project_item, content: @pull, memex_project: @project),
      create(:memex_project_item, content: @irrelevant_issue, memex_project: @project)
    ]
  end

  setup do
    setup_search
  end

  context "#subscriptions" do
    test "invoked on issue title change" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::ParentIssueTitleValueUpdate, "github.v2.IssueUpdate") do
        @parent.update!(title: "An updated title")
      end
    end
  end

  context "#valid_message?" do
    test "returns true when the update includes a title change" do
      initial_title = @parent.title
      new_title = "An updated title"
      message = value_update_message(issue: @parent, new_value: new_title, previous_value: initial_title)

      assert MemexProjectColumn::Interface::Indexable::Processor::ParentIssueTitleValueUpdate.new(message).valid_message?
    end

    test "returns false when the update does not include a title change" do
      initial_title = @parent.title
      message = value_update_message(issue: @parent, new_value: initial_title, previous_value: initial_title)

      refute MemexProjectColumn::Interface::Indexable::Processor::ParentIssueTitleValueUpdate.new(message).valid_message?
    end

    test "returns false when the update is a pull request" do
      initial_title = @pull.title
      new_title = "An updated title"
      message = value_update_message(issue: @pull.issue, pull: @pull, new_value: initial_title, previous_value: new_title)

      refute MemexProjectColumn::Interface::Indexable::Processor::ParentIssueTitleValueUpdate.new(message).valid_message?
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when there is at least one memex project item document in elastic search matching the issue" do
      populate_elasticsearch_index!(@project_items)

      initial_title = @parent.title
      new_title = "An updated title"
      message = value_update_message(issue: @parent, new_value: new_title, previous_value: initial_title)

      assert MemexProjectColumn::Interface::Indexable::Processor::ParentIssueTitleValueUpdate.new(message).matching_elasticsearch_documents?
    end

    test "returns false when there are no memex project item documents in elastic search matching the issue" do
      populate_elasticsearch_index!(@project_items)

      another_issue = create(:issue, repository: @repo, title: "another parent")
      another_child = create(:issue, repository: @repo)
      another_issue.add_sub_issue!(another_child, @actor.id)

      initial_title = another_issue.title
      new_title = "An updated title"
      message = value_update_message(issue: another_issue, new_value: new_title, previous_value: initial_title)

      refute MemexProjectColumn::Interface::Indexable::Processor::ParentIssueTitleValueUpdate.new(message).matching_elasticsearch_documents?
    end
  end

  context "#update" do
    test "updates project item doc field_values when it's parent title changes" do
      item_in_another_project = create(:memex_project_item, content: @child1)
      populate_elasticsearch_index!(@project_items + [item_in_another_project])

      initial_title = @parent.title
      new_title = "An updated title"
      @parent.update!(title: new_title)
      @parent.instrument_hydro_update_event(previous_title: initial_title, actor: @actor)
      message = value_update_message(issue: @parent, new_value: new_title, previous_value: initial_title)

      response = MemexProjectColumn::Interface::Indexable::Processor::ParentIssueTitleValueUpdate.new(message).update(es_client)
      index.refresh

      assert_equal 3, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.first&.update&.result
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.second&.update&.result
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.third&.update&.result

      # both items now have parents updated titles
      item_in_this_project_parent = field_value(get_doc(@project_items[0].id), @parent_issue_field)
      item2_in_this_project_parent = field_value(get_doc(@project_items[1].id), @parent_issue_field)
      item_in_another_project_parent = field_value(get_doc(item_in_another_project.id), item_in_another_project.memex_project.columns.find(&:parent_issue?).to_field)

      assert_equal new_title, item_in_this_project_parent["title"]
      assert_equal new_title, item2_in_this_project_parent["title"]
      assert_equal new_title, item_in_another_project_parent["title"]
    end

    test "noops when the issue title already exists in the index" do
      project_item = @project_items.first
      initial_title = @parent.title
      populate_elasticsearch_index!([project_item])

      message = value_update_message(issue: @parent, new_value: initial_title, previous_value: initial_title)
      response = MemexProjectColumn::Interface::Indexable::Processor::ParentIssueTitleValueUpdate.new(message).update(es_client)

      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop, response.items.first&.update&.result
    end

    test "provides correct project ids for resyncing on failure" do
      parent = create(:issue, repository: @repo, state: "open")
      issue = create(:issue, repository: @repo, state: "open")
      parent.add_sub_issue!(issue, @actor.id)
      create(:memex_project_item, memex_project: @project, content: issue)
      project_2 = create(:memex_project)
      create(:memex_project_item, memex_project: project_2, content: issue)
      issue.assignee = @actor

      message = value_update_message(issue: parent, new_value: "foo")
      processor = MemexProjectColumn::Interface::Indexable::Processor::ParentIssueTitleValueUpdate.new(message)
      assert_equal [@project.id, project_2.id].sort, processor.project_ids_to_resync_on_failure.sort
    end

    test "provides correct updated models" do
      parent = create(:issue, repository: @repo, state: "open")
      issue = create(:issue, repository: @repo, state: "open")
      parent.add_sub_issue!(issue, @actor.id)
      item_1 = create(:memex_project_item, memex_project: @project, content: issue)
      project_2 = create(:memex_project)
      item_2 = create(:memex_project_item, memex_project: project_2, content: issue)
      issue.assignee = @actor

      message = value_update_message(issue: parent, new_value: "foo")
      processor = MemexProjectColumn::Interface::Indexable::Processor::ParentIssueTitleValueUpdate.new(message)
      assert_same_elements [parent, item_1, item_2], processor.updated_models
    end
  end

  private

  def value_update_message(issue:, new_value:, previous_value: nil, pull: nil)
    build_message(
      {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(@actor),
        repository: Hydro::EntitySerializer.repository(@repo),
        repository_owner: Hydro::EntitySerializer.repository_owner(@repo.owner),
        issue: Hydro::EntitySerializer.issue(issue),
        pull_request: Hydro::EntitySerializer.pull_request(pull),
        previous_title: previous_value,
        current_title: new_value,
      },
      schema: "github.v2.IssueUpdate"
    )
  end
end
