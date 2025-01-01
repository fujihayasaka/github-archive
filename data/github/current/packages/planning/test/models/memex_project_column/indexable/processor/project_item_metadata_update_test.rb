# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectItemMetadataUpdateTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:verified_user)
    @repo = create(:repository, owner: @actor, has_discussions: true)
    @memex = create(:memex_project, owner: @actor, title: "My Memex Project")
    @issue = create(:issue, repository: @repo,  state: "open")
    @item = create(:memex_project_item, content: @issue, memex_project: @memex)
  end

  setup do
    setup_search
    @index = Elastomer::Indexes::MemexProjectItems.new
  end

  context "#subscriptions" do
    test "invoked when a project item is updated" do
      assert_consumes(MemexProjectColumn::Indexable::Processor::ProjectItemMetadataUpdate, "github.memex.v0.ProjectItemMetadataUpdate") do
        @item.archive!
      end
    end

    test "invoked in response to a priority update on a project item" do
      project = create(:memex_project, owner: @actor, title: "test project")
      item_one = build(:memex_project_item, memex_project: project, repository: @repo)
      item_two = build(:memex_project_item, memex_project: project, repository: @repo)

      project.prioritize!(
        item: item_one,
        position: GitHub::Prioritizable::SBT::Position.from_options(position: :top),
        association: :memex_project_items,
      )

      project.prioritize!(
        item: item_two,
        position: GitHub::Prioritizable::SBT::Position.from_options(position: :bottom),
        association: :memex_project_items,
      )

      reset_hydro

      assert_consumes(MemexProjectColumn::Indexable::Processor::ProjectItemMetadataUpdate, "github.memex.v0.ProjectItemMetadataUpdate") do
        project.prioritize!(
          item: item_two,
          position: GitHub::Prioritizable::SBT::Position.from_options({ before: item_one }),
          association: :memex_project_items,
        )
      end
    end
  end

  context "#message validation" do
    test "passes validation when both item_id and project_id are present" do
      message = project_item_metadata_update_message
      assert processor.new(message).valid_message?
    end

    test "does not pass validation when item_id is absent" do
      message = project_item_metadata_update_message(item: {})
      refute processor.new(message).valid_message?
    end

    test "does not pass validation when project_id is absent" do
      message = project_item_metadata_update_message(project: nil)
      refute processor.new(message).valid_message?
    end
  end

  context "#matching elasticsearch documents" do
    test "matches when the document exists" do
      populate_elasticsearch_index!([@item])
      message = project_item_metadata_update_message
      assert processor.new(message).matching_elasticsearch_documents?
    end

    test "does not match when the document does not exist" do
      message = project_item_metadata_update_message
      refute processor.new(message).matching_elasticsearch_documents?
    end
  end

  context "#canonical data present" do
    test "returns true when the model exists" do
      message = project_item_metadata_update_message
      assert processor.new(message).canonical_data_present?
    end

    test "returns false when the model no longer exists" do
      populate_elasticsearch_index!([@item])
      message = project_item_metadata_update_message
      @item.destroy!
      refute processor.new(message).canonical_data_present?
    end
  end

  context "#update" do
    test "updates when archived_at changed", es_8_only: true do
      populate_elasticsearch_index!([@item])
      refute get_doc(@item.id)["_source"]["archived_at"]

      @item.archive!
      process_messages!

      @index.refresh
      assert_equal @item.archived_at.iso8601.to_s, get_doc(@item.id)["_source"]["archived_at"]
    end

    test "updates when priority changed", es_8_only: true do
      populate_elasticsearch_index!([@item])
      refute get_doc(@item.id)["_source"]["virtual_priority"]

      reset_hydro
      @item.update(priority_numerator: 1, priority_denominator: 1)
      @item.reload
      process_messages!

      @index.refresh
      assert_equal @item.stringified_virtual_priority, get_doc(@item.id)["_source"]["virtual_priority"]
    end

    test "no-ops when values are unchanged", es_8_only: true do
      populate_elasticsearch_index!([@item])
      version = get_doc(@item.id)["_version"]

      reset_hydro
      response = processor.new(project_item_metadata_update_message).update(es_client)
      assert_equal version, response._version
      assert response.result == Elastomer::Interfaces::Api::Update::Response::Result::Noop
    end
  end

  test "provides correct project ids for resyncing on failure" do
    project_ids = processor.new(project_item_metadata_update_message).project_ids_to_resync_on_failure
    assert_equal [@memex.id], project_ids
  end

  test "provides correct updated models" do
    assert_equal [@item], processor.new(project_item_metadata_update_message).updated_models
  end

  private def get_doc(item_id)
    @index.docs.get(type: "memex_project_item", routing: item_id, id: item_id)
  end

  private def processor
    MemexProjectColumn::Indexable::Processor::ProjectItemMetadataUpdate
  end

  private def process_messages!
    run_processor(Projects::DenormalizationProcessor.new, allowed_primary_query_count: 0)
  end

  private def project_item_metadata_update_message(item: @item, project: @memex)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        memex_project: project.present? ? Hydro::EntitySerializer.memex_project(project) : nil,
        memex_project_item: item.present? ? Hydro::EntitySerializer.memex_project_item(item) : nil,
        request_context: Hydro::EntitySerializer.request_context({}),
        previous_values: "{}",
      },
      schema: "hydro.schemas.github.memex.v0.ProjectItemMetadataUpdate"
    )
  end
end
