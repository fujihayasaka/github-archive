# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/planning"

class MemexProjectColumnInterfaceSummableTest < GitHub::TestCase
  include MemexHelpers

  setup do
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context "field_metric_options#sum" do
    MemexHelpers.for_each_field_subclass(:summable?).each do |class_name|
      context "for the #{class_name.demodulize} field type" do
        test "sub-aggregates all groups for single-level grouping", es_8_only: true do
          test_case = load_test_case(class_name)
          project = test_case.field.memex_project
          grouped_on_field = project.columns.find(&:status?).to_field
          option = grouped_on_field.settings["options"][0]

          items = create_list(:memex_project_item, 3, memex_project: project)
          items.each_with_index do |item, index|
            create(
              :memex_project_column_value,
              memex_project_item: item,
              memex_project_column: test_case.field,
              value: test_case.field_value,
            )
            create(
              :memex_project_column_value,
              memex_project_item: item,
              memex_project_column: grouped_on_field,
              value: option["id"],
            ) unless index == 0 # skip the first item to test 'no value' group
          end
          populate_elasticsearch_index!(items)
          query = Search::Queries::MemexProjectItemQuery.new(
            project: project,
            viewer: project.owner,
            grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
              field_object_or_id: grouped_on_field,
              field_metric_options: MemexProjectColumn::Interface::Groupable::FieldMetricOptions.new(
                sum: [test_case.field],
              ),
            ),
          )
          result = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
          assert result.primary_groups.nodes.length > 1
          result.primary_groups.nodes.each do |group|
            item_count = group.total_count.value
            assert item_count > 0
            assert_equal [test_case.field.id], group.field_metrics.map { _1.field_id }
            assert_equal [test_case.field_value * item_count], group.field_metrics.map { _1.value }
          end
        end

        test "sub-aggregates primary and secondary groups for multi-level grouping", es_8_only: true do
          test_case = load_test_case(class_name)
          project = test_case.field.memex_project
          grouped_on_field = project.columns.find(&:status?).to_field
          option = grouped_on_field.settings["options"][0]

          items = create_list(:memex_project_item, 3, memex_project: project)
          items.each_with_index do |item, index|
            create(
              :memex_project_column_value,
              memex_project_item: item,
              memex_project_column: test_case.field,
              value: test_case.field_value,
            )
            create(
              :memex_project_column_value,
              memex_project_item: item,
              memex_project_column: grouped_on_field,
              value: option["id"],
            ) unless index == 0 # skip the first item to test 'no value' group
          end
          populate_elasticsearch_index!(items)

          field_metric_options = MemexProjectColumn::Interface::Groupable::FieldMetricOptions.new(
            sum: [test_case.field],
          )
          grouping_options = MemexProjectColumn::Interface::Groupable::Options.new(
            field_object_or_id: grouped_on_field,
            field_metric_options:,
            secondary_grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
              field_object_or_id: grouped_on_field,
              field_metric_options:,
            ),
          )
          query = Search::Queries::MemexProjectItemQuery.new(
            project: project,
            viewer: project.owner,
            grouping_options:,
          )
          result = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
          assert result.primary_groups.nodes.length > 1
          result.primary_groups.nodes.each do |group|
            item_count = group.total_count.value
            assert item_count > 0
            assert_equal [test_case.field.id], group.field_metrics.map { _1.field_id }
            assert_equal [test_case.field_value * item_count], group.field_metrics.map { _1.value }
          end
          secondary_groups = result.secondary_groups&.nodes || []
          assert secondary_groups.length > 1
          secondary_groups.each do |group|
            item_count = group.total_count.value
            assert item_count > 0
            assert_equal [test_case.field.id], group.field_metrics.map { _1.field_id }
            assert_equal [test_case.field_value * item_count], group.field_metrics.map { _1.value }
          end
        end
      end
    end
  end

  private def load_test_case(class_name)
    test_case = load_field_test_case(class_name, :setup_summable_test)

    skip("No test case defined for #{class_name}") unless test_case

    test_case
  end
end
