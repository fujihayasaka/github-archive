# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueTitleValueUpdateTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @repo = create(:repository, owner: @actor)
    @user = create(:user)
    @repo.add_member(@user)
    @project = create(:memex_project, owner: @actor, title: "test project")
    @open_issue = create(:issue, repository: @repo,  state: "open")
    @closed_issue = create(:issue, repository: @repo,  state: "closed")
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
    @title_field = @project.columns.find(&:title?).to_field
    @project_items = [
      create(:memex_project_item, content: @open_issue, memex_project: @project),
      create(:memex_project_item, content: @pull, memex_project: @project),
      create(:memex_project_item, content: @closed_issue, memex_project: @project)
    ]
  end

  setup do
    setup_search
  end

  context "#subscriptions" do
    test "invoked on issue title change" do
      assert_consumes(MemexProjectColumn::Indexable::Processor::IssueTitleValueUpdate, "github.v2.IssueUpdate") do
        @open_issue.update!(title: "An updated title")
      end
    end
  end

  context "#valid_message?" do
    test "returns true when the update includes a title change" do
      initial_title = @open_issue.title
      new_title = "An updated title"
      message = value_update_message(issue: @open_issue, new_value: new_title, previous_value: initial_title)

      assert MemexProjectColumn::Indexable::Processor::IssueTitleValueUpdate.new(message).valid_message?
    end

    test "returns false when the update does not include a title change" do
      initial_title = @open_issue.title
      message = value_update_message(issue: @open_issue, new_value: initial_title, previous_value: initial_title)

      refute MemexProjectColumn::Indexable::Processor::IssueTitleValueUpdate.new(message).valid_message?
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when there is at least one memex project item document in elastic search matching the issue" do
      populate_elasticsearch_index!(@project_items)

      initial_title = @open_issue.title
      new_title = "An updated title"
      message = value_update_message(issue: @open_issue, new_value: new_title, previous_value: initial_title)

      assert MemexProjectColumn::Indexable::Processor::IssueTitleValueUpdate.new(message).matching_elasticsearch_documents?
    end

    test "returns true when there is at least one memex project item document in elastic search matching a pull request" do
      populate_elasticsearch_index!(@project_items)

      initial_title = @pull.title
      new_title = "An updated title"
      message = value_update_message(issue: @pull.issue, pull: @pull, new_value: new_title, previous_value: initial_title)

      assert MemexProjectColumn::Indexable::Processor::IssueTitleValueUpdate.new(message).matching_elasticsearch_documents?
    end

    test "returns false when there are no memex project item documents in elastic search matching the issue" do
      populate_elasticsearch_index!(@project_items)

      another_issue = create(:issue, repository: @repo,  state: "open")

      initial_title = another_issue.title
      new_title = "An updated title"
      message = value_update_message(issue: another_issue, new_value: new_title, previous_value: initial_title)

      refute MemexProjectColumn::Indexable::Processor::IssueTitleValueUpdate.new(message).matching_elasticsearch_documents?
    end
  end

  context "#update" do
    # NOTE: when a pull request title is changed by a user, what actually is happening under the hood is we are
    # updating the underlying issue title. Therefore this catches both issue and pull request title changes.
    test "updates project item doc field_values when an issue title changes" do
      item_in_another_project = create(:memex_project_item, content: @open_issue)
      populate_elasticsearch_index!(@project_items + [item_in_another_project])

      initial_title = @open_issue.title
      new_title = "An updated title"
      @open_issue.update!(title: new_title)
      @open_issue.instrument_hydro_update_event(previous_title: initial_title, actor: @actor)
      message = value_update_message(issue: @open_issue, new_value: new_title, previous_value: initial_title)

      MemexProjectColumn::Indexable::Processor::IssueTitleValueUpdate.new(message).update(es_client)
      index.refresh

      # both items now have updated titles
      item_in_this_project_title = field_value(get_doc(@project_items[0].id), @title_field)
      item_in_another_project_title = field_value(get_doc(item_in_another_project.id), item_in_another_project.memex_project.columns.find(&:title?).to_field)

      assert_equal new_title, item_in_this_project_title
      assert_equal new_title, item_in_another_project_title
    end

    test "updates titles across projects" do
      item_in_another_project = create(:memex_project_item, content: @open_issue)
      populate_elasticsearch_index!(@project_items + [item_in_another_project])

      initial_title = @open_issue.title
      new_title = "An updated title"
      @open_issue.update!(title: new_title)
      @open_issue.instrument_hydro_update_event(previous_title: initial_title, actor: @actor)
      message = value_update_message(issue: @open_issue, new_value: new_title, previous_value: initial_title)

      response = MemexProjectColumn::Indexable::Processor::IssueTitleValueUpdate.new(message).update(es_client)
      index.refresh

      assert_equal 2, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.first&.update&.result
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.second&.update&.result

      # both items now have updated titles
      item_in_this_project_title = field_value(get_doc(@project_items[0].id), @title_field)
      item_in_another_project_title = field_value(get_doc(item_in_another_project.id), item_in_another_project.memex_project.columns.find(&:title?).to_field)

      assert_equal new_title, item_in_this_project_title
      assert_equal new_title, item_in_another_project_title
    end

    test "noops when the issue title already exists in the index" do
      project_item = create(:memex_project_item, memex_project: @project)
      initial_title = project_item.issue.title
      populate_elasticsearch_index!([project_item])

      message = value_update_message(issue: project_item.issue, new_value: initial_title, previous_value: initial_title)
      response = MemexProjectColumn::Indexable::Processor::IssueTitleValueUpdate.new(message).update(es_client)

      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop, response.items.first&.update&.result
    end

    test "raises canonical data missing error if content is no longer present during update", es_8_only: true do
      message = value_update_message(issue: @open_issue, new_value: "foo")
      @open_issue.destroy!
      assert_raises(MemexProjectColumn::Indexable::CanonicalDataMissingError) do
        MemexProjectColumn::Indexable::Processor::IssueTitleValueUpdate.new(message).update(es_client)
      end
    end

    test "provides correct project ids for resyncing on failure" do
      issue = create(:issue, repository: @repo, state: "open")
      create(:memex_project_item, memex_project: @project, content: issue)
      project_2 = create(:memex_project)
      create(:memex_project_item, memex_project: project_2, content: issue)
      issue.assignee = @actor

      message = value_update_message(issue: issue, new_value: "foo")
      processor = MemexProjectColumn::Indexable::Processor::IssueTitleValueUpdate.new(message)
      assert_equal [@project.id, project_2.id].sort, processor.project_ids_to_resync_on_failure.sort
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
