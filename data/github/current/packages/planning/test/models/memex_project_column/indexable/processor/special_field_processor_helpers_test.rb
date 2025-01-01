# typed: true
# frozen_string_literal: true

require "test_helper"

class SpecialFieldProcessorHelpersTest < GitHub::TestCase
  include HydroTestHelpers
  include MemexHelpers
  include ProjectsProcessorTestHelpers

  class TestProcessorWithSpecialHelpers < TestProcessor
    include MemexProjectColumn::Interface::Indexable::Processor::SpecialFieldProcessorHelpers
  end

  setup do
    setup_search
  end

  teardown do
    teardown_search
  end

  test "multiple pages of project ids are returned from elasticsearch", es_8_only: true do
    content = create(:issue)
    unrelated_content = create(:issue)
    items = [
      create(:memex_project_item, content:),
      create(:memex_project_item, content:),
    ]
    unrelated_item = create(:memex_project_item, content: unrelated_content)
    populate_elasticsearch_index!(items + [unrelated_item])

    # This schema is 100% arbitrary -- it just needs to be a valid schema
    message = build_message({}, schema: "github.v1.TeamRename")
    processor = TestProcessorWithSpecialHelpers.new(message)
    MemexProjectColumn::Interface::Indexable::Processor::SpecialFieldProcessorHelpers.stub_const(:BATCH_SIZE, 1) do
      expected_project_ids = items.map(&:memex_project_id)
      indexed_project_ids = processor.project_ids_from_elasticsearch(query: { term: { "content.id": content.id } })
      assert_equal expected_project_ids.sort, indexed_project_ids.sort
    end
  end
end
