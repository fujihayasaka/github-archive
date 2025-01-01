# typed: true
# frozen_string_literal: true

require "test_helper"

class ProcessProjectItemDeleteTest < GitHub::TestCase
  include MemexHelpers
  include ProjectsProcessorTestHelpers
  include HydroTestHelpers

  fixtures do
    @actor = create(:verified_user)
    @repo = create(:repository, owner: @actor, has_discussions: true)
    @memex = create(:memex_project, owner: @actor, title: "My Memex Project")
    @item = create(:memex_project_item, memex_project: @memex)
  end

  setup do
    setup_search
  end

  context "#subscriptions" do
    test "invoked when a project item is deleted" do
      assert_consumes(processor, "github.memex.v0.ProjectItemDestroy") do
        @item.destroy
      end
    end
  end

  context "#message validation" do
    test "passes validation when both item_id and project_id are present" do
      message = project_item_delete_message
      assert processor.new(message).valid_message?
    end

    test "passes validation when a project has been deleted but the id is still available via the item payload" do
      message = project_item_delete_message(project: nil)
      assert processor.new(message).valid_message?
    end

    test "does not pass validation when item_id is absent" do
      message = project_item_delete_message(item: {})
      refute processor.new(message).valid_message?
    end
  end

  context "#matching elasticsearch documents" do
    test "passes through the match gate no matter what since we'll just do a noop delete if needed" do
      message = project_item_delete_message
      assert processor.new(message).matching_elasticsearch_documents?
    end
  end

  context "#canonical data present" do
    test "passes through the canonical data gate in all circumstances because we trust the event can't be fired for an item still present" do
      message = project_item_delete_message
      assert processor.new(message).canonical_data_present?
    end
  end

  context "#update" do
    test "deletes the document from the index when found", es_8_only: true do
      populate_elasticsearch_index!([@item])
      message = project_item_delete_message
      response = processor.new(message).update(es_client)
      assert_equal Elastomer::Interfaces::Api::Delete::Response::Result::Deleted, response.result
      refute get_doc(@item.id)["found"]
    end

    test "returns not found when no matching document found", es_8_only: true do
      response = processor.new(project_item_delete_message).update(es_client)
      assert_equal Elastomer::Interfaces::Api::Delete::Response::Result::NotFound, response.result
    end
  end

  test "provides correct project ids for resyncing on failure" do
    project_ids = processor.new(project_item_delete_message).project_ids_to_resync_on_failure
    assert_equal [@memex.id], project_ids
  end

  private def processor
    MemexProjectColumn::Indexable::Processor::ProcessProjectItemDelete
  end

  private def process_messages!
    run_processor(Projects::DenormalizationProcessor.new, allowed_primary_query_count: 0)
  end

  private def project_item_delete_message(item: @item, project: @memex)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        memex_project: project.present? ? Hydro::EntitySerializer.memex_project(project) : nil,
        memex_project_item: item.present? ? Hydro::EntitySerializer.memex_project_item(item) : nil,
        request_context: Hydro::EntitySerializer.request_context({}),
      },
      schema: "hydro.schemas.github.memex.v0.ProjectItemDestroy"
    )
  end
end
