# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/planning"

class MemexProjectColumnInterfaceSliceableTest < GitHub::TestCase
  include MemexHelpers

  setup do
    enable_feature_flag(:issue_types)
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context "slicing" do
    MemexHelpers.for_each_field_subclass.each do |class_name|

      context "for the #{class_name} field type" do
        test "serializes metadata correctly across multiple slices", es_8_only: true do
          test_case = load_test_case(class_name)
          populate_elasticsearch_index!(test_case.items)

          query = Search::Queries::MemexProjectItemQuery.new(
            project: test_case.project,
            viewer: test_case.viewer,
            slice_by: test_case.field.id,
            include_slice_metadata: true,
          )

          response = query.execute

          assert_equal test_case.non_empty_expected_slices.size, response.slices&.size

          test_case.non_empty_expected_slices.zip(response.slices).each do |(expected, actual)|
            assert_equal expected[:value], actual["slice_value"]

            if expected[:metadata].nil?
              assert_nil actual["metadata"]
            else
              assert_equal expected[:metadata].stringify_keys, actual["metadata"]&.to_hash&.transform_keys { |key| key.to_s.camelize(:lower) }
            end
          end
        end

        test "includes metadata for slices that don't match the filter", es_8_only: true do
          test_case = load_test_case(class_name)
          populate_elasticsearch_index!(test_case.items)

          query = Search::Queries::MemexProjectItemQuery.new(
            project: test_case.project,
            viewer: test_case.viewer,
            slice_by: test_case.field.id,
            include_slice_metadata: true,
            include_empty_slices: true,
            query: "this is gibberish that does not match anything",
          )

          response = query.execute

          assert_equal 0, response.total
          assert_equal test_case.expected_slices.size, response.slices&.size

          test_case.expected_slices.zip(response.slices).each do |(expected, actual)|
            assert_equal 0, actual["total_count"]
            assert_equal expected[:value], actual["slice_value"]
            if expected[:metadata].nil?
              assert_nil actual["metadata"]
            else
              assert_equal expected[:metadata].stringify_keys, actual["metadata"]&.to_hash&.transform_keys { |key| key.to_s.camelize(:lower) }
            end
          end
        end

        test "includes metadata for all known slices even when empty", es_8_only: true do
          test_case = load_test_case(class_name)
          skip("#{class_name} doesn't have known slices") unless test_case.field.known_slices?

          query = Search::Queries::MemexProjectItemQuery.new(
            project: test_case.project,
            viewer: test_case.viewer,
            slice_by: test_case.field.id,
            include_slice_metadata: true,
            include_empty_slices: true,
          )

          response = query.execute

          assert_equal 0, response.total
          assert_equal test_case.expected_slices.size, response.slices&.size

          test_case.expected_slices.zip(response.slices).each do |(expected, actual)|
            assert_equal 0, actual["total_count"]
            assert_equal expected[:value], actual["slice_value"]
            if expected[:metadata].nil?
              assert_nil actual["metadata"]
            else
              assert_equal expected[:metadata].stringify_keys, actual["metadata"]&.to_hash&.transform_keys { |key| key.to_s.camelize(:lower) }
            end
          end
        end
      end
    end
  end

  private def load_test_case(class_name)
    test_case = load_field_test_case(class_name, :setup_sliceable_test) do |test_case|
      assert test_case.expected_slices.length > 1, "Test case for #{class_name} must define more than one expected slice"
      assert test_case.expected_slices.one? { _1[:value] == MemexProjectColumn::Interface::Sliceable::MISSING_VALUE_GROUP_KEY }, "Test case for #{class_name} must include a \"no value\" slice"
    end

    skip("No test case defined for #{class_name}") unless test_case

    test_case
  end
end
