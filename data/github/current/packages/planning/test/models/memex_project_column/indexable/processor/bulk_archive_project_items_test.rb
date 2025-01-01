# typed: true
# frozen_string_literal: true

require "test_helper"

class BulkArchiveProjectItemsTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:verified_user)
    @memex = create(:memex_project, owner: @actor, title: "My Memex Project")
    @items = create_list(:memex_project_item, 5, memex_project: @memex)
  end

  setup do
    setup_search
    @index = Elastomer::Indexes::MemexProjectItems.new
    GitHub.flipper[:memex_process_bulk_archive_events].enable
  end

  teardown do
    teardown_search
  end

  context "#subscriptions" do
    test "invoked when a batch of project items is archived" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::BulkArchiveProjectItems, "github.memex.v0.BulkArchiveProjectItems") do
        perform_enqueued_jobs(only: [MemexArchiveJob]) do
          @memex.archive_job(viewer: @actor, items: @items)
        end
      end
    end

    test "invoked when a batch of project items is unarchived" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::BulkArchiveProjectItems, "github.memex.v0.BulkArchiveProjectItems") do
        perform_enqueued_jobs(only: [MemexUnarchiveItemsJob]) do
          @memex.unarchive_project_items_later(viewer: @actor, item_ids: @items.map(&:id))
        end
      end
    end
  end

  context "#message validation" do
    test "skips validation when the feature flag is disabled" do
      GitHub.flipper[:memex_process_bulk_archive_events].disable
      message = bulk_archive_project_items_message
      refute processor.new(message).valid_message?
    end

    test "passes validation when both item_ids and project_id are present" do
      message = bulk_archive_project_items_message
      assert processor.new(message).valid_message?
    end

    test "does not pass validation when item_ids are empty" do
      message = bulk_archive_project_items_message(items: [])
      refute processor.new(message).valid_message?
    end

    test "does not pass validation when project_id is absent" do
      message = bulk_archive_project_items_message(project: nil)
      refute processor.new(message).valid_message?
    end
  end

  context "#matching elasticsearch documents" do
    test "matches when the documents exist" do
      populate_elasticsearch_index!(@items)
      message = bulk_archive_project_items_message
      assert processor.new(message).matching_elasticsearch_documents?
    end

    test "matches when some of the documents exist" do
      populate_elasticsearch_index!(@items[0..1])
      message = bulk_archive_project_items_message
      assert processor.new(message).matching_elasticsearch_documents?
    end

    test "does not match when the document does not exist" do
      # We skip populating the index here, which means there should be no docs to match against
      message = bulk_archive_project_items_message
      refute processor.new(message).matching_elasticsearch_documents?
    end
  end

  context "#canonical data present" do
    test "returns true when the models exist" do
      message = bulk_archive_project_items_message
      assert processor.new(message).canonical_data_present?
    end

    test "returns false when the model no longer exists" do
      item = @items.first
      populate_elasticsearch_index!([item])
      message = bulk_archive_project_items_message(items: [item])
      item.destroy!
      refute processor.new(message).canonical_data_present?
    end
  end

  context "#update" do
    test "updates archived_at when documents do not already reflect canonical state", es_8_only: true do
      populate_elasticsearch_index!(@items)
      # Leave 1 item unarchived to validate that it is not updated in the index
      archived_items = @items[0..-2]
      archived_items.each { _1.archive! }
      expected_ids_archived = archived_items.map(&:id)
      expected_ids_unarchived = [@items.last.id]

      docs_to_be_archived = get_all_docs.filter { expected_ids_archived.include?(_1["_id"].to_i) }
      refute docs_to_be_archived.any? { _1["_source"]["archived_at"].present? }

      processor.new(bulk_archive_project_items_message(items: archived_items)).update(es_client)
      docs = get_all_docs

      expected_docs_archived = docs.filter { expected_ids_archived.include?(_1["_id"].to_i) }
      expected_docs_unarchived = docs.filter { expected_ids_unarchived.include?(_1["_id"].to_i) }

      # Archived items should have archived_at set
      assert expected_docs_archived.all? { _1["_source"]["archived_at"].present? }
      # Unarchived item should not have archived_at set
      refute expected_docs_unarchived.all? { _1["_source"]["archived_at"].present? }
    end

    test "no-ops when values are unchanged", es_8_only: true do
      item = @items.first
      item.archive!
      populate_elasticsearch_index!([item])
      version = get_doc(item.id)["_version"]
      response = processor.new(bulk_archive_project_items_message(items: [item])).update(es_client)
      assert_equal 1, response.items.size
      update_response = response.items.first.update
      assert_equal version, update_response._version
      assert update_response.result == Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop
    end
  end

  test "provides correct project ids for resyncing on failure" do
    project_ids = processor.new(bulk_archive_project_items_message).project_ids_to_resync_on_failure
    assert_equal [@memex.id], project_ids
  end

  test "provides correct updated models" do
    assert_same_elements @items, processor.new(bulk_archive_project_items_message).updated_models
  end

  private def get_doc(item_id)
    @index.docs.get(type: "memex_project_item", routing: item_id, id: item_id)
  end

  private def get_all_docs
    @index.search_all({})["hits"]["hits"].sort_by { _1["_id"] }
  end

  private def processor
    MemexProjectColumn::Interface::Indexable::Processor::BulkArchiveProjectItems
  end

  private def bulk_archive_project_items_message(items: @items, project: @memex, bulk_action: :ARCHIVED)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        memex_project: project.present? ? Hydro::EntitySerializer.memex_project(project) : nil,
        memex_project_item_ids: items.present? ? items.map(&:id) : nil,
        bulk_action:,
        request_context: Hydro::EntitySerializer.request_context({}),
      },
      schema: "hydro.schemas.github.memex.v0.BulkArchiveProjectItems"
    )
  end
end
