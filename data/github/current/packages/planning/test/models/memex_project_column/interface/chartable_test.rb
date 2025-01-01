# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/planning"

class MemexProjectColumnInterfaceChartableTest < GitHub::TestCase
  include MemexHelpers

  Chartable = MemexProjectColumn::Interface::Chartable

  setup do
    GitHub.flipper[:issue_types].enable
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context "charting" do
    MemexHelpers.for_each_field_subclass.each do |class_name|

      context "for the #{class_name} field type" do
        test "provides basic, ungrouped current state chart data" do
          test_case = load_test_case(class_name)
          populate_elasticsearch_index!(test_case.items)

          chart_options = Chartable::Options.new(
            x_axis: Chartable::Options::XAxis.new(
              data_source: Chartable::Options::XAxisDataSource.new(
                field_object_or_id: test_case.field,
              )
            )
          )

          query = Search::Queries::MemexProjectItemQuery.insights_query(
            project: test_case.project,
            viewer: test_case.viewer,
            chart_options:,
            source_fields: ["database_id"],
          )
          response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

          actual_x_axis_values = response.chart_data&.x_axis&.values
          actual_counts = response.chart_data&.data_series&.first&.data

          assert_equal test_case.expected_chart_data.x_axis.values, actual_x_axis_values
          assert test_case.expected_chart_data.data_series.first
          assert_equal test_case.expected_chart_data.data_series.first&.data, actual_counts
        end
      end
    end
  end

  sig { params(class_name: String).returns(Planning::MemexProjectColumn::ChartableTestCase) }
  private def load_test_case(class_name)
    test_case = load_field_test_case(class_name, :setup_chartable_test) do |test_case|
      assert test_case.expected_chart_data.x_axis.values.length > 1, "Test case for #{class_name} must define more than one expected x_axis value"
      assert test_case.expected_chart_data.x_axis.values.one? { _1 == Chartable::MISSING_VALUE_KEY }, "Test case for #{class_name} must include a \"no value\" x_axis value"
    end

    skip("No test case defined for #{class_name}") unless test_case

    test_case
  end
end
