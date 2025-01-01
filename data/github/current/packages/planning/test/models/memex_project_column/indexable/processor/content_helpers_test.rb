# typed: true
# frozen_string_literal: true

require "test_helper"

class ContentHelpersTest < GitHub::TestCase
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  class TestProcessorWithContentHelpers < TestProcessor
    include MemexProjectColumn::Interface::Indexable::Processor::ContentHelpers
    def content; end
  end

  context "#project_items_for_content" do
    test "returns project items for content" do
      message = build_message({}, schema: "github.v1.IssueClose")
      processor = TestProcessorWithContentHelpers.new(message)
      issue = create(:issue)
      3.times { create(:memex_project_item, content: issue) }

      processor.stubs(:content).returns(issue)
      assert_max_query_count_per_table({
        # One call to get the content
        issues: 1,
        # All project items related to the issue
        memex_project_items: 1,
      }) do
        # Fetch the project items for the content, and reverse the relationship to access the content off the items (as is
        # typical of elasticsearch_document implementations that many processors use). This should verify that we're not
        # causing N+1 queries.
        processor.project_items_for_content.each(&:content)
      end
    end

    test "raises CanonicalDataMissingError if content is no longer available when fetching project items" do
      message = build_message({}, schema: "github.v1.IssueClose")
      processor = TestProcessorWithContentHelpers.new(message)
      issue = create(:issue)
      create(:memex_project_item, content: issue)

      processor.stubs(:content).returns(nil)
      assert_raises MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError do
        processor.project_items_for_content
      end
    end
  end

  context "bulk_update_field_values_for_content" do
    test "updates with expected script" do
      issue = create(:assigned_issue)
      project_item = create(:memex_project_item, content: issue)
      field = project_item.memex_project.columns.find(&:assignees?).to_field

      message = build_message({}, schema: "github.v1.IssueClose")
      processor = TestProcessorWithContentHelpers.new(message)
      processor.stubs(:content).returns(issue)

      bulk_update = mock("stub")
      es_client.stubs(:bulk).yields(bulk_update).returns(sample_bulk_update_response)
      bulk_update.expects(:update).with(
        { script: field.elasticsearch_field_value_update_script(project_item).to_hash },
        has_entries({ _id: project_item.id, routing: project_item.memex_project_id, retry_on_conflict: 3 })
      )

      processor.bulk_update_field_values_for_content(es_client, field_class: field.class)
    end

    test "raises CanonicalDataMissingError if no project items are available" do
      issue = create(:assigned_issue)
      message = build_message({}, schema: "github.v1.IssueClose")
      processor = TestProcessorWithContentHelpers.new(message)
      processor.stubs(:content).returns(issue)
      assert_raises MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError do
        processor.bulk_update_field_values_for_content(es_client, field_class: MemexProjectColumn::Field::Assignees)
      end
    end

    test "raises CanonicalDataMissingError if columns aren't found" do
      issue = create(:assigned_issue)
      project_item = create(:memex_project_item, content: issue)
      message = build_message({}, schema: "github.v1.IssueClose")
      processor = TestProcessorWithContentHelpers.new(message)
      processor.stubs(:content).returns(issue)
      # No column will be found for issue types since issue types are a particular privilege that need to be
      # opted into. Once they're generally available this test may need to be updated to specifically delete the whole
      # project rather than relying on the column not being present by default.
      assert_raises MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError do
        processor.bulk_update_field_values_for_content(es_client, field_class: MemexProjectColumn::Field::IssueType)
      end
    end
  end
end
