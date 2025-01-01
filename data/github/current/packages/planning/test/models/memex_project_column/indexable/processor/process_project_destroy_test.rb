# typed: true
# frozen_string_literal: true

require "test_helper"

class ProcessProjectDestroyTest < GitHub::TestCase
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

  teardown do
    teardown_search
  end

  context "#subscriptions" do
    test "invoked when a project is destroyed" do
      assert_consumes(processor, "github.memex.v0.ProjectDestroy") do
        @memex.destroy
      end
    end
  end

  context "#message validation" do
    test "passes validation when project_id is present" do
      message = project_destroy_message
      assert processor.new(message).valid_message?
    end

    test "does not pass validation when project_id is absent" do
      message = project_destroy_message(project: nil)
      refute processor.new(message).valid_message?
    end
  end

  context "#matching elasticsearch documents" do
    test "passes through the match gate no matter what since we'll just do a noop delete if needed" do
      message = project_destroy_message
      assert processor.new(message).matching_elasticsearch_documents?
    end
  end

  context "#canonical data present" do
    test "passes through the canonical data gate in all circumstances because we trust the event can't be fired for an item still present" do
      message = project_destroy_message
      assert processor.new(message).canonical_data_present?
    end
  end

  context "#update" do
    test "deletes documents for the given project from the index, leaving others intact", es_8_only: true do
      matching_items = [@item, create(:memex_project_item, memex_project: @memex)]
      non_matching_items = [create(:memex_project_item)]
      populate_elasticsearch_index!(matching_items + non_matching_items)
      message = project_destroy_message
      response = processor.new(message).update(es_client)

      assert_equal 2, response.deleted
      assert_empty response.failures
      refute matching_items.any? { get_doc(_1.id)["found"] }
      assert non_matching_items.all? { get_doc(_1.id)["found"] }
    end
  end

  test "provides correct project ids for resyncing on failure" do
    project_ids = processor.new(project_destroy_message).project_ids_to_resync_on_failure
    assert_equal [@memex.id], project_ids
  end

  test "provides correct updated models" do
    assert_empty processor.new(project_destroy_message).updated_models
  end

  private def processor
    MemexProjectColumn::Interface::Indexable::Processor::ProcessProjectDestroy
  end

  private def process_messages!
    run_processor(Projects::DenormalizationProcessor.new, allowed_primary_query_count: 0)
  end

  private def project_destroy_message(project: @memex)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        memex_project: project.present? ? Hydro::EntitySerializer.memex_project(project) : nil,
        request_context: Hydro::EntitySerializer.request_context({}),
      },
      schema: "hydro.schemas.github.memex.v0.ProjectDestroy"
    )
  end
end
