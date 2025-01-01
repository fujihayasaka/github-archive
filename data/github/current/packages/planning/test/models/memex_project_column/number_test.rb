# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnNumberTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @user = create(:verified_user)
    @item = create(:memex_project_item)
    @memex = @item.memex_project
    @number_field = create(:memex_project_column, data_type: :number, memex_project: @memex).to_field
    @number_value = create(:number_memex_project_column_value, memex_project_item: @item, column: @number_field)
  end

  setup do
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context ".elasticsearch_mapping" do
    test "returns the correct float configuration" do
      assert_equal(
        {
          type: "float",
          copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS
        },
        @number_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#execute" do
    test "returns matching results for a query that filters by number column value" do
      # arrange
      item_to_find = create(:memex_project_item, memex_project: @memex)
      extra_item_1 = create(:memex_project_item, memex_project: @memex)
      extra_item_2 = create(:memex_project_item, memex_project: @memex)
      extra_item_3 = create(:memex_project_item, memex_project: @memex)

      value_to_find = 10

      number_column = create(:memex_project_column, data_type: :number, name: "Number Column", memex_project: @memex)
      create(:number_memex_project_column_value,
        memex_project_item: item_to_find,
        column: number_column,
        value: value_to_find
      )
      create(:number_memex_project_column_value,
        memex_project_item: extra_item_1,
        column: number_column,
        value: 1
      )
      create(:number_memex_project_column_value,
        memex_project_item: extra_item_2,
        column: number_column,
        value: 100 # making sure that a match for 10 doesn't march a 100
      )
      create(:number_memex_project_column_value,
        memex_project_item: extra_item_3,
        column: number_column,
        value: 1000 # making sure that a match for 10 doesn't march a 1000
      )

      populate_elasticsearch_index!([item_to_find, extra_item_1, extra_item_2, extra_item_3])

      # act
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "number-column:#{value_to_find}",
        source_fields: true,
      ).execute

      # assert
      assert_equal 1, response.total
      assert_equal value_to_find, field_value(number_column.to_field, response.results.first)
    end

    test "returns matching results for an OR query on number column value" do
      # arrange
      item_1 = create(:memex_project_item, memex_project: @memex)
      item_2 = create(:memex_project_item, memex_project: @memex)
      item_3 = create(:memex_project_item, memex_project: @memex)

      number_column = create(:memex_project_column, data_type: :number, name: "Number field", memex_project: @memex)
      create(:number_memex_project_column_value,
        memex_project_item: item_1,
        column: number_column,
        value: 1
      )
      create(:number_memex_project_column_value,
        memex_project_item: item_2,
        column: number_column,
        value: 2
      )
      create(:number_memex_project_column_value,
        memex_project_item: item_3,
        column: number_column,
        value: 10
      )

      populate_elasticsearch_index!([item_1, item_2, item_3])

      # act
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "number-field:1,2",
        source_fields: true,
      ).execute

      # assert
      assert_equal 2, response.total
      found_values = [
        field_value(number_column.to_field, response.results.first),
        field_value(number_column.to_field, response.results.second)
      ]
      assert_includes found_values, 1
      assert_includes found_values, 2
    end

    test "returns matching results for a query that filters by negative number" do
      # arrange
      item_1 = create(:memex_project_item, memex_project: @memex)
      item_2 = create(:memex_project_item, memex_project: @memex)
      item_3 = create(:memex_project_item, memex_project: @memex)

      value_to_exclude = 10
      number_column = create(:memex_project_column, data_type: :number, name: "Number field", memex_project: @memex)
      create(:number_memex_project_column_value,
        memex_project_item: item_1,
        column: number_column,
        value: value_to_exclude
      )
      create(:number_memex_project_column_value,
        memex_project_item: item_2,
        column: number_column,
        value: 1234 # value that doesnt match the negative filter
      )
      create(:number_memex_project_column_value,
        memex_project_item: item_3,
        column: number_column,
        value: value_to_exclude
      )
      populate_elasticsearch_index!([item_1, item_2, item_3])

      # act
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "-number-field:#{value_to_exclude}",
        source_fields: true,
      ).execute

      # assert
      assert_equal 1, response.total
      refute_equal value_to_exclude, field_value(number_column.to_field, response.results.first)
    end

    test "returns matching results for filter on empty number values" do
      # arrange
      item_1 = create(:memex_project_item, memex_project: @memex)
      item_2 = create(:memex_project_item, memex_project: @memex)

      number_column = create(:memex_project_column, data_type: :number, name: "Number field", memex_project: @memex)
      create(:number_memex_project_column_value,
        memex_project_item: item_1,
        column: number_column,
        value: 1
      )

      populate_elasticsearch_index!([item_1, item_2])

      # act
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "no:number-field"
      ).execute

      # assert
      assert_equal 1, response.total
      refute response.results.first.dig("_source", "field_values")
    end

    test "returns matching results for a greater-than (>) query" do
      items = [1, 10, 100].map do |value|
        item = create(:memex_project_item, memex_project: @memex)
        create(:number_memex_project_column_value,
          memex_project_item: item,
          column: @number_field,
          value: value
        )
        item
      end
      populate_elasticsearch_index!(items)

      query = "#{@number_field.name_slug}:>10"
      expected_item_id = items[2].id

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: query,
      ).execute

      assert_equal 1, response.total
      assert_equal expected_item_id, response.results.first["_source"]["database_id"]
    end

    test "returns matching results for a less-than (<) query" do
      items = [1, 10, 100].map do |value|
        item = create(:memex_project_item, memex_project: @memex)
        create(:number_memex_project_column_value,
          memex_project_item: item,
          column: @number_field,
          value: value
        )
        item
      end
      populate_elasticsearch_index!(items)

      query = "#{@number_field.name_slug}:<10"
      expected_item_id = items[0].id

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: query,
      ).execute

      assert_equal 1, response.total
      assert_equal expected_item_id, response.results.first["_source"]["database_id"]
    end

    test "returns matching results for a greater-than-or-equal-to (both >= and n..*) query" do
      items = [1, 10, 100].map do |value|
        item = create(:memex_project_item, memex_project: @memex)
        create(:number_memex_project_column_value,
          memex_project_item: item,
          column: @number_field,
          value: value
        )
        item
      end
      populate_elasticsearch_index!(items)

      expected_item_ids = T.must(items[1..2]).map(&:id)

      query = "#{@number_field.name_slug}:>=10"
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: query,
      ).execute

      assert_equal expected_item_ids.size, response.total
      assert_equal expected_item_ids, response.results.map { |result| result["_source"]["database_id"] }

      query = "#{@number_field.name_slug}:10..*"
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: query,
      ).execute

      assert_equal expected_item_ids.size, response.total
      assert_equal expected_item_ids, response.results.map { |result| result["_source"]["database_id"] }
    end

    test "returns matching results for a less-than-or-equal-to (both <= and *..n) query" do
      items = [1, 10, 100].map do |value|
        item = create(:memex_project_item, memex_project: @memex)
        create(:number_memex_project_column_value,
          memex_project_item: item,
          column: @number_field,
          value: value
        )
        item
      end
      populate_elasticsearch_index!(items)

      expected_item_ids = T.must(items[0..1]).map(&:id)

      query = "#{@number_field.name_slug}:<=10"
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: query,
      ).execute

      assert_equal expected_item_ids.size, response.total
      assert_equal expected_item_ids, response.results.map { |result| result["_source"]["database_id"] }

      query = "#{@number_field.name_slug}:*..10"
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: query,
      ).execute

      assert_equal expected_item_ids.size, response.total
      assert_equal expected_item_ids, response.results.map { |result| result["_source"]["database_id"] }
    end

    test "returns matching results for a range (n..n) query" do
      items = [1, 10, 100].map do |value|
        item = create(:memex_project_item, memex_project: @memex)
        create(:number_memex_project_column_value,
          memex_project_item: item,
          column: @number_field,
          value: value
        )
        item
      end
      populate_elasticsearch_index!(items)

      expected_item_ids = items.map(&:id)

      query = "#{@number_field.name_slug}:1..100"
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: query,
      ).execute

      assert_equal expected_item_ids.size, response.total
      assert_equal expected_item_ids, response.results.map { |result| result["_source"]["database_id"] }

      query = "#{@number_field.name_slug}:2..99"
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: query,
      ).execute

      assert_equal 1, response.total
      assert_equal [items[1].id], response.results.map { |result| result["_source"]["database_id"] }
    end
  end

  context "#seed_elasticsearch_document" do
    test "returns an arbitrary number" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(require_non_nil_value: true)
      refute_nil @number_field.seed_elasticsearch_document(context)
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads number data" do
      @number_field.preload_elasticsearch_document_data([@item])
      assert_no_queries { @number_field.elasticsearch_document(@item) }
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing the numeric value" do
      refute_nil @number_value.json_value

      assert_equal(
        @number_value.json_value["value"],
        @number_field.elasticsearch_document(@item)
      )
    end
  end

  context "#graphql_value" do
    test "null returns null" do
      assert_nil @number_field.graphql_value(nil)
    end

    test "_noValue returns null" do
      assert_nil @number_field.graphql_value("_noValue")
    end

    test "string returns a parsed float" do
      stored_value = "123.456"

      assert_equal stored_value.to_f, @number_field.graphql_value(stored_value)
    end
  end

  context "#graphql_title" do
    test "null returns default empty group title" do
      assert_equal "No #{@number_field.name}", @number_field.graphql_title(nil)
    end

    test "_noValue returns default empty group title" do
      assert_equal "No #{@number_field.name}", @number_field.graphql_title("_noValue")
    end

    test "empty string returns default empty group title" do
      assert_equal "No #{@number_field.name}", @number_field.graphql_title("")
    end

    test "strips trailing zeros" do
      value = "123.40"

      assert_equal "123.4", @number_field.graphql_title(value)
    end

    test "strips decimal point and insignificant digits" do
      value = "123.0"

      assert_equal "123", @number_field.graphql_title(value)
    end
  end

  private

  sig { params(field: MemexProjectColumn::Field, document: T::Hash[T.untyped, T.untyped]).returns(T.untyped) }
  def field_value(field, document)
    document.dig("_source", "field_values").find { |f| f["field_id"] == field.id }&.fetch(field.class.value_name.to_s)
  end
end
