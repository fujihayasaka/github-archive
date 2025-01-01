# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnTextTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @memex = create(:memex_project)
    @issue = create(:issue)
    @item = create(:memex_project_item, content: @issue, memex_project: @memex)
    @text_field = create(:memex_project_column, data_type: :text, memex_project: @memex).to_field
    @text_value = create(:text_memex_project_column_value, memex_project_item: @item, column: @text_field)
  end

  setup do
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context ".elasticsearch_mapping" do
    test "returns the correct multi-field configuration" do
      assert_equal(
        {
          type: "text",
          fields: {
            keyword: { type: "keyword" }
          },
          copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS
        },
        @text_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads text data" do
      @text_field.preload_elasticsearch_document_data([@item])
      assert_no_queries { @text_field.elasticsearch_document(@item) }
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing the raw text value" do
      refute_empty @text_value.json_value["raw"]

      assert_equal(
        @text_value.json_value["raw"],
        @text_field.elasticsearch_document(@item)
      )
    end
  end

  context "#seed_elasticsearch_document" do
    test "generates a string" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(require_non_nil_value: true)
      assert_predicate @text_field.seed_elasticsearch_document(context), :present?
    end
  end

  context "#query_fragment" do
    test "returns the expected query fragment hash" do
      expected_query_fragment = {
        bool: {
          should: [
            {
              nested: {
                path: "field_values",
                query: {
                  bool: {
                    must: [
                      {
                        term: {
                          "field_values.field_id": {
                            value: @text_field.id
                          }
                        }
                      },
                      {
                        term: {
                          "field_values.text_value.keyword" => {
                            value: @text_value.value,
                            case_insensitive: true,
                          }
                        }
                      },
                    ]
                  }
                }
              }
            }
          ],
          minimum_should_match: 1
        }
      }
      context = Search::Memex::Context.new(memex_project: @item.memex_project, viewer: @item.creator)
      query_fragment = @text_field.query_fragment(values: [@text_value.value], is_negated: false, context:)

      assert_equal expected_query_fragment, query_fragment
    end

    test "returns the expected query fragment hash for a negated query" do
      expected_query_fragment = {
        bool: {
          must_not: [
            {
              nested: {
                path: "field_values",
                query: {
                  bool: {
                    must: [
                      {
                        term: {
                          "field_values.field_id": {
                            value: @text_field.id
                          }
                        }
                      },
                      {
                        term: {
                          "field_values.text_value.keyword" => {
                            value: @text_value.value,
                            case_insensitive: true,
                          }
                        }
                      },
                    ]
                  }
                }
              }
            }
          ]
        }
      }
      context = Search::Memex::Context.new(memex_project: @item.memex_project, viewer: @item.creator)
      query_fragment = @text_field.query_fragment(values: [@text_value.value], is_negated: true, context:)

      assert_equal expected_query_fragment, query_fragment
    end
  end

  context "#existence_fragment" do
    test "returns the expected query fragment hash for 'no:title' query" do
      expected_query_fragment = {
        nested: {
          path: "field_values",
          query: {
            bool: {
              must: [
                {
                  term: {
                    "field_values.field_id": {
                      value: @text_field.id
                    },
                  }
                },
                exists: {
                  field: "field_values.text_value.keyword"
                },
              ]
            }
          }
        }
      }

      assert_equal expected_query_fragment, @text_field.existence_fragment
    end
  end

  context "query behaviour" do
    test "filters on exact, case-insensitive match without a wildcard", es_8_only: true do
      items = [
        new_item("abc def ghi"),
        new_item("def ghi"),
        new_item("abc def"),
        new_item("def"),
      ]

      populate_elasticsearch_index!(items)

      test_cases = {
        "#{@text_field.name_slug}:\"abc def ghi\"" => [items[0].id],
        "#{@text_field.name_slug}:\"abc DEF ghi\"" => [items[0].id],
        "#{@text_field.name_slug}:\"def ghi\"" => [items[1].id],
        "#{@text_field.name_slug}:\"dEf gHi\"" => [items[1].id],
        "#{@text_field.name_slug}:def" => [items[3].id],
        "#{@text_field.name_slug}:DEF" => [items[3].id],
        "#{@text_field.name_slug}:abc" => [],
      }

      test_cases.each do |query, expected_result_ids|
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: query
        )
        response = query.execute
        actual_result_ids = response.results.map { |result| result["_source"]["database_id"] }
        assert_same_elements expected_result_ids, actual_result_ids, "Query that failed: #{query}"
      end
    end

    test "wildcard queries match correct documents", es_8_only: true do
      items = [
        new_item("wildcard test two"),
        new_item("wildcard test one"),
        new_item,
        new_item("test"),
        new_item("one"),
      ]

      populate_elasticsearch_index!(items)

      test_cases = {
        # We expect that wild* will match the 2 items that start with "wildcard" but nothing else
        "#{@text_field.name_slug}:wild*" => [items[1].id, items[0].id],
        # The above query should also work case-insensitively.
        "#{@text_field.name_slug}:WILD*" => [items[1].id, items[0].id],
        # We expect that *es* will match the 3 items with the "test" value
        "#{@text_field.name_slug}:*es*" => [items[0].id, items[1].id, items[3].id],
        # We expect that *one will match the 2 items with the "one" value, including the one with no other characters
        "#{@text_field.name_slug}:*one" => [items[1].id, items[4].id],
        # We expect that * will match all 4 non-empty items
        "#{@text_field.name_slug}:*" => [items[0].id, items[1].id, items[3].id, items[4].id],
      }

      test_cases.each do |query, expected_result_ids|
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: query
        )
        response = query.execute
        actual_result_ids = response.results.map { |result| result["_source"]["database_id"] }
        assert_same_elements expected_result_ids, actual_result_ids, "Query that failed: #{query}"
      end
    end
  end

  test "sorts by text value" do
    sample_text_values_unsorted = ["foo ants", "bar", "apple zest", "jack"]
    sample_text_values_sorted_asc = ["apple zest", "bar", "foo ants", "jack"]
    sample_text_values_sorted_desc = ["jack", "foo ants", "bar", "apple zest"]

    items = sample_text_values_unsorted.map { |value| new_item(value) }
    populate_elasticsearch_index!(items)

    # Test ascending
    sorted_asc_query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex,
      viewer: @user,
      query: "",
      sort: [@text_field.sort_fragment(direction: "asc")]
    )
    sorted_response_values = sorted_asc_query.execute.results.map { |i| i["sort"].first }
    assert_equal sample_text_values_sorted_asc, sorted_response_values

    # Test descending
    sorted_desc_query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex,
      viewer: @user,
      query: "",
      sort: [@text_field.sort_fragment(direction: "desc")]
    )
    sorted_response_values = sorted_desc_query.execute.results.map { |i| i["sort"].first }
    assert_equal sample_text_values_sorted_desc, sorted_response_values
  end

  context "#graphql_value" do
    test "null returns empty string" do
      assert_equal "", @text_field.graphql_value(nil)
    end

    test "_noValue returns empty string" do
      assert_equal "", @text_field.graphql_value("_noValue")
    end

    test "string returns string" do
      value = "abc123"

      assert_equal value, @text_field.graphql_value(value)
    end
  end

  context "#graphql_title" do
    test "null returns default empty group title" do
      assert_equal "No #{@text_field.name}", @text_field.graphql_title(nil)
    end

    test "empty string returns default empty group title" do
      assert_equal "No #{@text_field.name}", @text_field.graphql_title("")
    end

    test "_noValue returns default empty group title" do
      assert_equal "No #{@text_field.name}", @text_field.graphql_title("_noValue")
    end

    test "present string" do
      value = "abc123"

      assert_equal value, @text_field.graphql_title(value)
    end
  end

  def new_item(text_value = nil)
    item = create(:memex_project_item, memex_project: @memex)
    create(:text_memex_project_column_value, memex_project_item: item, column: @text_field, value: text_value) if text_value
    item
  end
end
