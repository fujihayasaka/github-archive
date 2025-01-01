# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/planning"

class MemexProjectColumnInterfaceGroupableTest < GitHub::TestCase
  include MemexHelpers

  LOADED_TEST_CASES = {}

  setup do
    setup_search
  end

  fixtures do
    enable_feature_flag(:issue_types)
    # This changes the metadata for assignees in all-features-enabled tests, so let's disable it before any test cases
    # are created
    disable_feature_flag(:private_avatars)
    # These must get loaded in fixtures, otherwise the activerecord models created during the tests will be cleaned
    # up before the next tests are run
    MemexHelpers.for_each_field_subclass.each do |class_name|
      LOADED_TEST_CASES[class_name] ||= load_test_case(class_name, preloading: true)
    end
  end

  teardown_once do
    teardown_search
  end

  context "grouping" do
    MemexHelpers.for_each_field_subclass.each do |class_name|

      context "for the #{class_name.demodulize} field type" do
        test "groups items correctly across multiple groups", es_8_only: true do
          test_case = load_test_case(class_name)
          populate_elasticsearch_index!(test_case.items)

          query = Search::Queries::MemexProjectItemQuery.new(
            project: test_case.project,
            viewer: test_case.viewer,
            grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(field_object_or_id: test_case.field),
            source_fields: ["database_id"],
          )
          response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
          primary_groups = response.primary_groups

          test_case.non_empty_expected_groups.zip(primary_groups.nodes).each do |(expected, actual)|
            actual = T.cast(actual, MemexProjectColumn::Interface::Groupable::Group)
            assert_equal expected[:items].length, actual.total_count.value
            actual_items = response.grouped_items.find { _1.group_id == actual.group_id }
            assert_same_elements expected[:items].map(&:id), actual_items&.paginated_items&.map { _1["_id"].to_i }
          end
        end

        test "serializes metadata correctly across multiple groups", es_8_only: true do
          test_case = load_test_case(class_name)
          populate_elasticsearch_index!(test_case.items)

          query = Search::Queries::MemexProjectItemQuery.new(
            project: test_case.project,
            viewer: test_case.viewer,
            grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
              field_object_or_id: test_case.field,
              include_group_metadata: true
            ),
          )

          response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
          primary_groups = response.primary_groups

          assert_equal test_case.non_empty_expected_groups.size, primary_groups.nodes.size

          test_case.non_empty_expected_groups.zip(primary_groups.nodes).each do |(expected, actual)|
            assert_equal expected[:value], actual.group_value

            if expected[:metadata].nil?
              assert_nil actual.group_metadata
            else
              assert_equal expected[:metadata].stringify_keys, actual.group_metadata
            end
          end
        end

        test "serializes metadata even when no items are requested", es_8_only: true do
          test_case = load_test_case(class_name)
          populate_elasticsearch_index!(test_case.items)

          query = Search::Queries::MemexProjectItemQuery.new(
            project: test_case.project,
            viewer: test_case.viewer,
            grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
              field_object_or_id: test_case.field,
              include_group_metadata: true,
              grouped_items_page_size: 0,
            ),
          )

          response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
          primary_groups = response.primary_groups

          assert_equal(
            test_case.non_empty_expected_groups.find_all { _1[:metadata] }.length,
            primary_groups.nodes.count(&:group_metadata)
          )
        end

        test "serializes metadata when all :source_fields are requested", es_8_only: true do
          test_case = load_test_case(class_name)
          populate_elasticsearch_index!(test_case.items)

          query = Search::Queries::MemexProjectItemQuery.new(
            project: test_case.project,
            viewer: test_case.viewer,
            source_fields: true,
            grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
              field_object_or_id: test_case.field,
              include_group_metadata: true,
            ),
          )
          response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
          primary_groups = response.primary_groups

          assert_equal(
            test_case.non_empty_expected_groups.find_all { _1[:metadata] }.length,
            primary_groups.nodes.count(&:group_metadata)
          )
        end

        test "includes metadata for all known groups even when empty", es_8_only: true do
          test_case = load_test_case(class_name)
          skip("#{class_name} doesn't have known groups") unless test_case.field.static_groups?

          query = Search::Queries::MemexProjectItemQuery.new(
            project: test_case.project,
            viewer: test_case.viewer,
            grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
              field_object_or_id: test_case.field,
              include_group_metadata: true,
              include_empty_groups: true,
            ),
          )

          response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
          primary_groups = response.primary_groups

          assert_equal(
            test_case.expected_groups.find_all { _1[:metadata] }.length,
            primary_groups.nodes.count(&:group_metadata)
          )
        end

        test "filters primary and secondary static group values by query_slug", es_8_only: true do
          test_case = load_test_case(class_name)
          skip("#{class_name} doesn't have known groups") unless test_case.field.static_groups?
          skip("#{class_name} still needs to implement functionality for this test") if test_case.skip&.include?(:static_group_filtering)

          test_value = test_case.field.static_group_values.first
          query = Search::Queries::MemexProjectItemQuery.new(
            project: test_case.project,
            viewer: test_case.viewer,
            grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
              field_object_or_id: test_case.field,
              include_empty_groups: true,
              secondary_grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
                field_object_or_id: test_case.field,
                include_empty_groups: true,
              )
            ),
            query: "#{test_case.field.query_slug}:\"#{test_value}\""
          )

          assert test_value
          assert test_case.expected_groups.length > 1

          grouped_response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
          primary_groups = grouped_response.primary_groups
          assert_equal 1, primary_groups.nodes.length, "failed for #{class_name}"
          assert_equal test_case.field.static_group_values.first, primary_groups.nodes.first&.group_value

          secondary_groups = grouped_response.secondary_groups
          assert_equal 1, secondary_groups&.nodes&.length, "failed for #{class_name}"
          assert_equal test_case.field.static_group_values.first, secondary_groups&.nodes&.first&.group_value
        end

        test "queries Elasticsearch with a page size large enough to retrieve all known groups", es_8_only: true do
          test_case = load_test_case(class_name)
          skip("#{class_name} doesn't have known groups") unless test_case.field.static_groups?

          group_by_key_symbol = test_case.field.group_by_key.to_s.to_sym
          options = MemexProjectColumn::Interface::Groupable::Options.new(
            field_object_or_id: test_case.field,
            include_empty_groups: false
          )
          elasticsearch_group_size_argument = MemexProjectColumn::Interface::Groupable.stub_const(:DEFAULT_GROUPS_PAGE_SIZE, 0) do
            test_case
              .field
              .group_by_fragment(sort: [], source_fields: [], options:).to_hash
              .dig(group_by_key_symbol, :aggs, :values, :aggs, :groups, :composite, :size)
          end

          assert elasticsearch_group_size_argument >= test_case.field.static_group_values.length + 1
        end

        test "paginates correctly even when including known empty groups", es_8_only: true do
          test_case = load_test_case(class_name)
          skip("#{class_name} doesn't have known groups") unless test_case.field.static_groups?

          populate_elasticsearch_index!(test_case.items)

          cursor = T.let(nil, T.nilable(String))

          test_case.expected_groups.each_with_index do |expected_group, index|
            query = Search::Queries::MemexProjectItemQuery.new(
              project: test_case.project,
              viewer: test_case.viewer,
              grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
                field_object_or_id: test_case.field,
                groups_page_size: 1,
                include_empty_groups: true,
                cursor:,
              ),
            )
            response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
            primary_groups = response.primary_groups

            assert_equal 1, primary_groups.nodes.length
            assert_equal expected_group[:value], primary_groups.nodes.first&.group_value

            # We should have a previous page for every response except the first one
            assert_equal index != 0, primary_groups.has_previous_page

            # We should have a next page for every response except the last one
            assert_equal index != test_case.expected_groups.length - 1, primary_groups.has_next_page

            cursor = primary_groups.end_cursor
          end
        end

        test "includes field metrics for known empty groups when asked", es_8_only: true do
          test_case = load_test_case(class_name)
          skip("#{class_name} doesn't have known groups") unless test_case.field.static_groups?

          summable_field = create(:number_memex_column, memex_project: test_case.project).to_field

          query = Search::Queries::MemexProjectItemQuery.new(
            project: test_case.project,
            viewer: test_case.viewer,
            grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
              field_object_or_id: test_case.field,
              include_empty_groups: true,
              field_metric_options: MemexProjectColumn::Interface::Groupable::FieldMetricOptions.new(
                sum: [summable_field]
              )
            ),
          )
          response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
          primary_groups = response.primary_groups

          assert primary_groups.nodes.count > 0
          primary_groups.nodes.each do |group|
            assert_same_elements [[summable_field.id, 0]], group.field_metrics.map { [_1.field_id, _1.value] }
          end
        end

        test "places the 'no value' group last by default", es_8_only: true do
          test_case = load_test_case(class_name)
          skip("#{class_name} doesn't have known groups") unless test_case.field.static_groups?
          populate_elasticsearch_index!(test_case.items)

          query = Search::Queries::MemexProjectItemQuery.new(
            project: test_case.project,
            viewer: test_case.viewer,
            grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(field_object_or_id: test_case.field),
          )

          response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
          primary_groups = response.primary_groups
          assert_equal MemexProjectColumn::Interface::Groupable::MISSING_VALUE_GROUP_KEY, primary_groups.nodes.last&.group_value
        end

        test "places the 'no value' group first when asked", es_8_only: true do
          test_case = load_test_case(class_name)
          skip("#{class_name} doesn't have known groups") unless test_case.field.static_groups?
          populate_elasticsearch_index!(test_case.items)

          query = Search::Queries::MemexProjectItemQuery.new(
            project: test_case.project,
            viewer: test_case.viewer,
            grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
              field_object_or_id: test_case.field,
              missing_value_group_order: MemexProjectColumn::Interface::Groupable::MissingValueGroupOrder::First,
            ),
          )

          response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
          primary_groups = response.primary_groups
          assert_equal MemexProjectColumn::Interface::Groupable::MISSING_VALUE_GROUP_KEY, primary_groups.nodes.first&.group_value
        end
      end
    end

    # Tests in this context exercise behaviour that is shared across all field types and guaranteed not to change
    # (or at least not likely to change) per field type (e.g. because the functionality is provided by a method in
    # `Groupable` that is marked as `sig(:final)`).
    #
    # As a result, the choice of field type used for each test should be considered arbitrary.
    context "for an arbitrary field" do
      context "#group_by_fragment" do
        test "raises an exception on Elasticsearch 5", es_5_only: true do
          test_case = load_test_case("Assignees")
          error = assert_raises(ArgumentError) { test_case.field.group_by_fragment(sort: [], source_fields: []) }
          assert_equal "Grouping by #{test_case.field.data_type} is only supported on Elasticsearch v8", error.message
        end
      end
    end

    test "group ids are encoded with `urlsafe_encode64`" do
      # We're choosing to explicitly test the implementation details of
      # how the group id is generated, because the client is working under the
      # assumption that a `:` won't exist in the server generated id.
      # As long as the implementation continues to use `urlsafe_encode64`
      # this assumption should hold, but if we use a different mechanism
      # for generating that id, that could possibly use a `:`, we want to see
      # a test failure so that we know to update the client code to use a
      # new separator.

      group = MemexProjectColumn::Interface::Groupable::Group.new(
        group_by_key: 123,
        group_value: "Text value",
      )
      cursor_identifier = Platform::ConnectionWrappers::CursorGenerator::CURSOR_IDENTIFIER
      v2_prefix = Platform::ConnectionWrappers::CursorGenerator::V2_PREFIX
      serialized_data = MessagePack.pack([123, "Text value"])

      encoded_group_id = (Base64.urlsafe_encode64("#{cursor_identifier}#{v2_prefix}#{serialized_data}"))

      assert_equal group.group_id, encoded_group_id
    end
  end

  private def load_test_case(class_name, preloading: false)
    return LOADED_TEST_CASES[class_name] if LOADED_TEST_CASES[class_name]
    test_case = load_field_test_case(class_name, :setup_groupable_test) do |test_case|
      assert test_case.expected_groups.length > 1, "Test case for #{class_name} must define more than one expected group"

      has_no_value_group = test_case.expected_groups.one? do
        _1[:value] == MemexProjectColumn::Interface::Groupable::MISSING_VALUE_GROUP_KEY && _1[:items].present?
      end
      assert has_no_value_group, "Test case for #{class_name} must include a \"no value\" group"

      if test_case.field.static_groups?
        has_empty_group = test_case.expected_groups.one? do
          _1[:value] != MemexProjectColumn::Interface::Groupable::MISSING_VALUE_GROUP_KEY && _1[:items].empty?
        end
        assert has_empty_group, "Test case for #{class_name} must include one empty group"
      end
    end

    skip("No test case defined for #{class_name}") unless test_case || preloading

    LOADED_TEST_CASES[class_name] = test_case

    test_case
  end
end
