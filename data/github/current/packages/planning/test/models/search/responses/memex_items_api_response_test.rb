# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchResponsesMemexItemsApiResponseTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @owner = create(:verified_user)
    @repo = create(:public_repository)
    @memex = create(:memex_project, owner: @owner)

    @issue = create(:issue, repository: @repo)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
  end

  setup do
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context ".build" do
    test "returns a MemexItemsApiResponse with archived items" do
      unarchived_items = create_list(:memex_project_item, 3, memex_project: @memex)
      archived_items = create_list(:memex_project_item, 2, :archived, memex_project: @memex)
      populate_elasticsearch_index!(unarchived_items + archived_items)

      response = Search::Responses::MemexItemsApiResponse.build(
        query: Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @owner,
          items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
          sort: [{ archived_at: "desc" }],
        ),
        serializer: ->(response) { item_serializer(response.models) },
      )
      response = T.cast(response, Search::Responses::FlatMemexItemsApiResponse)

      assert_equal 2, response.total_count.value
      assert_equal 2, response.nodes.size
      refute_empty response.nodes.map { |node| node[:archived] }.compact
      assert_same_elements archived_items.map(&:id), response.nodes.map { |node| node[:id] }
    end

    test "returns a MemexItemsApiResponse with unarchived items" do
      unarchived_items = create_list(:memex_project_item, 3, memex_project: @memex)
      archived_items = create_list(:memex_project_item, 2, :archived, memex_project: @memex)
      populate_elasticsearch_index!(unarchived_items + archived_items)

      response = Search::Responses::MemexItemsApiResponse.build(
        query: Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @owner,
        ),
        serializer: ->(response) { item_serializer(response.models) },
      )
      response = T.cast(response, Search::Responses::FlatMemexItemsApiResponse)

      assert_equal 3, response.total_count.value
      assert_equal 3, response.nodes.size
      assert_empty response.nodes.map { |node| node[:archived] }.compact
      assert_same_elements unarchived_items.map(&:id), response.nodes.map { |node| node[:id] }
    end

    test "returns a MemexItemsApiResponse with grouped items", es_8_only: true do
      items = create_list(:memex_project_item, 3, memex_project: @memex)
      populate_elasticsearch_index!(items)

      response = Search::Responses::MemexItemsApiResponse.build(
        query: Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @owner,
          grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
            field_object_or_id: @memex.status_column.to_field
          )
        ),
        serializer: ->(response) { item_serializer(response.models) },
      )

      response = T.cast(response, Search::Responses::GroupedMemexItemsApiResponse)
      assert_equal 3, response.total_count.value
      assert_nil response.groups.start_cursor
      assert_equal 1, response.groups.nodes.size
      refute response.groups.has_next_page
      refute_nil response.groups.end_cursor
      group = response.groups.nodes.first
      assert_equal "_noValue", group&.group_value
      assert_nil group&.group_metadata

      # assert that items id are the same as the items within nodes in grouped items
      response_items = response.grouped_items.map(&:nodes)
      response_items_id = response_items.flatten(1).map { |i| i[:id] }
      assert_same_elements items.map(&:id), response_items_id
    end

    test "returns a MemexItemsApiResponse with group and slice metadata", es_8_only: true do
      talune = create(:user, login: "talune")
      monalisa = create(:user, login: "monalisa")
      issue = create(:issue, mannequin_assignees: [talune, monalisa])
      item = create(:memex_project_item, memex_project: @memex, content: issue)
      populate_elasticsearch_index!([item])

      assignees_field = @memex.columns.find(&:assignees?)&.to_field

      response = Search::Responses::MemexItemsApiResponse.build(
        query: Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @owner,
          grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
            field_object_or_id: assignees_field,
            include_group_metadata: true,
          ),
          slice_by: assignees_field.id,
          include_slice_metadata: true,
        ),
        serializer: ->(response) { item_serializer(response.models) },
      )
      response = T.cast(response, Search::Responses::GroupedMemexItemsApiResponse)

      assert_equal 1, response.total_count.value
      assert_equal 2, response.groups.nodes.size
      expected_metadata = [talune.memex_column_hash, monalisa.memex_column_hash].map(&:stringify_keys)
      received_group_metadata = response.groups.nodes.map(&:group_metadata)
      assert_equal 2, received_group_metadata.size
      assert_same_elements expected_metadata, received_group_metadata
      received_slice_metadata = response.slices&.map { |s| s.to_hash.dig(:sliceMetadata) }
      assert_equal 2, received_slice_metadata&.size
      assert_same_elements expected_metadata, received_slice_metadata
    end

    test "does not suppress pagination errors" do
      assert_raises Search::Queries::CursorPagination::ParameterError do
        Search::Responses::MemexItemsApiResponse.build(
          query: Search::Queries::MemexProjectItemQuery.new(
            project: @memex,
            viewer: @owner,
            first: 100,
            last: 100,
          ),
          serializer: ->(response) { item_serializer(response.models) },
        )
      end
    end
  end

  context ".build_csv" do
    test "returns a MemexItemsApiResponse with unarchived items" do
      # unarchived items, is the only scope that is supported for CSVs
      unarchived_items = [
        create(:memex_project_item, memex_project: @memex, content: @issue),
        create(:memex_project_item, memex_project: @memex, content: @pull),
      ]

      populate_elasticsearch_index!(unarchived_items)

      response = Search::Responses::MemexItemsApiResponse.build_csv(
        query: Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @owner,
        ),
        serializer: ->(response) { item_csv_serializer(response.models) },
      )
      response = T.cast(response, Search::Responses::MemexItemsCsvApiResponse)

      assert_equal unarchived_items.size, response.total_count.value
      assert_equal unarchived_items.size, response.rows.size
    end

    test "does not supress pagination errors" do
      assert_raises Search::Queries::CursorPagination::ParameterError do
        Search::Responses::MemexItemsApiResponse.build_csv(
          query: Search::Queries::MemexProjectItemQuery.new(
            project: @memex,
            viewer: @owner,
            first: 100,
            last: 100,
          ),
          serializer: ->(response) { item_csv_serializer(response.models) },
        )
      end
    end
  end

  def item_serializer(items)
    MemexProjectItemSerializer.new(viewer: @owner, memex: @memex, items: items, columns: []).result.items
  end

  def item_csv_serializer(items)
    visible_columns = @memex.default_view.visible_columns
    prefilled_result = MemexProjectItemPrefiller.new(
      items,
      columns: visible_columns,
      read_denormalized_title: true,
      title_column: @memex.columns.find(&:title?),
    ).prefill
    refute_nil prefilled_result
    prefilled_result

    MemexProjectItemCsvSerializer.new(
      viewer: @owner,
      memex: @memex,
      items: items,
      columns: visible_columns,
      prefilled_associations: prefilled_result,
    )
    .result
    .csv_rows
  end
end
