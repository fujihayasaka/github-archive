# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnSingleSelectTest < GitHub::TestCase
  include MemexHelpers
  fixtures do
    @memex = create(:memex_project)
    @single_select_field = create(:single_select_memex_column, memex_project: @memex).to_field
    @single_select_options = @single_select_field.settings["options"]
    @issue = create(:assigned_issue)
    @item = create(:memex_project_item, content: @issue, memex_project: @memex)
    @status_field = @item.memex_project.status_column.to_field
  end

  setup do
    setup_search
  end

  teardown do
    teardown_search
  end

  context ".elasticsearch_mapping" do
    test "returns the correct multi-field configuration" do
      assert_equal(
        {
          dynamic: "strict",
          properties: {
            id: { type: "keyword" },
            name: {
              type: "text",
              fields: {
                keyword: { type: "keyword" }
              },
              copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS
            },
          }
        },
        @status_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#seed_elasticsearch_document" do
    test "picks one of the single select options" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(require_non_nil_value: true)
      assert_includes(
        @single_select_options.map { |o| o["name"] },
        @single_select_field.seed_elasticsearch_document(context).name
      )
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads single select data" do
      @single_select_field.preload_elasticsearch_document_data([@item])
      assert_no_queries { @single_select_field.elasticsearch_document(@item) }
    end
  end

  context "#elasticsearch_document" do
    test "returns the value for status field" do
      @item.set_column_value(@status_field, @status_field.settings["options"].first["id"], @memex.owner)

      refute_nil @status_field.settings["options"].first["name"]
      assert_equal(
        @status_field.settings["options"].first["name"],
        @status_field.elasticsearch_document(@item).name
      )
    end

    test "returns a the value for single_select field" do
      create(
        :single_select_memex_project_column_value,
        value: @single_select_options[0]["id"],
        memex_project_column: @single_select_field,
        memex_project_item: @item
      )

      refute_nil @single_select_field.settings["options"].first["name"]
      assert_equal(
        @single_select_field.settings["options"].first["name"],
        @single_select_field.elasticsearch_document(@item).name
      )
    end

    test "returns nil for the missing value for single_select field" do
      assert_nil @item.column_value(@single_select_field, require_prefilled_associations: false)
      assert_nil(
        @single_select_field.elasticsearch_document(@item)
      )
    end
  end

  context "#query_fragment" do
    test "returns the expected query fragment hash" do
      search_string = @single_select_field.settings["options"][0]["name"]
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
                            value: @single_select_field.id
                          }
                        }
                      },
                      {
                        term: {
                          "field_values.single_select_value.name.keyword" => {
                            value: search_string,
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
      context = Search::Memex::Context.new(memex_project: @memex, viewer: @issue.assignees.first)
      query_fragment = @single_select_field.query_fragment(values: [search_string], is_negated: false, context:)

      assert_equal expected_query_fragment, query_fragment
    end

    test "returns the expected query fragment hash for a negated query" do
      search_string = @single_select_field.settings["options"][0]["name"]
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
                            value: @single_select_field.id
                          }
                        }
                      },
                      {
                        term: {
                          "field_values.single_select_value.name.keyword" => {
                            value: search_string,
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
      context = Search::Memex::Context.new(memex_project: @memex, viewer: @issue.assignees.first)
      query_fragment = @single_select_field.query_fragment(values: [search_string], is_negated: true, context:)

      assert_equal expected_query_fragment, query_fragment
    end
  end

  context "#existence_fragment" do
    test "returns the expected query fragment hash for 'no:estimate' query" do
      expected_query_fragment = {
        nested: {
          path: "field_values",
          query: {
            bool: {
              filter: [
                {
                  term: {
                    "field_values.field_id": {
                      value: @single_select_field.id
                    },
                  }
                },
                exists: {
                  field: "field_values.single_select_value"
                },
              ]
            }
          }
        }
      }

      assert_equal expected_query_fragment, @single_select_field.existence_fragment
    end
  end

  context "#graphql_value" do
    test "null returns null" do
      assert_nil @single_select_field.graphql_value(nil)
    end

    test "_noValue returns null" do
      assert_nil @single_select_field.graphql_value("_noValue")
    end

    test "option name returns corresponding option identifier" do
      # Make sure we have something to test
      refute_empty @single_select_options

      option = @single_select_options.first

      assert_equal option["id"], @single_select_field.graphql_value(option["name"])
    end
  end

  context "#graphql_title" do
    test "null returns default empty group title" do
      assert_equal "No #{@single_select_field.name}", @single_select_field.graphql_title(nil)
    end

    test "empty string returns default empty group title" do
      assert_equal "No #{@single_select_field.name}", @single_select_field.graphql_title("")
    end

    test "_noValue returns default empty group title" do
      assert_equal "No #{@single_select_field.name}", @single_select_field.graphql_title("_noValue")
    end

    test "present value" do
      value = "Option 1"

      assert_equal value, @single_select_field.graphql_title(value)
    end
  end

  context "query behaviour" do
    test "matches when double spaces are part of the value" do
      sample_matching_query_value = "test  double spaces"
      sample_non_matching_query_value = "test double spaces"
      totally_different_query_value = "only single spaces here"
      @status_field.settings["options"].first["name"] = sample_matching_query_value
      @status_field.settings["options"].second["name"] = sample_non_matching_query_value
      @status_field.settings["options"].third["name"] = totally_different_query_value
      @status_field.save!

      @item.set_column_value(@status_field, @status_field.settings["options"].first["id"], @memex.owner)

      non_matching_item = create(:memex_project_item, memex_project: @memex)
      non_matching_item.set_column_value(@status_field, @status_field.settings["options"].second["id"], @memex.owner)

      second_non_matching_item = create(:memex_project_item, memex_project: @memex)
      second_non_matching_item.set_column_value(@status_field, @status_field.settings["options"].third["id"], @memex.owner)

      populate_elasticsearch_index!([@item, non_matching_item, second_non_matching_item])

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        query: "status:\"#{sample_matching_query_value}\"",
      )

      results = query.execute.results

      assert_equal 1, results.size
      assert_equal @item.id, results.first["_source"]["database_id"]
    end

    test "returns matching results for a case-insensitive query", es_8_only: true  do
      option = @status_field.settings["options"].first
      @item.set_column_value(@status_field, option["id"], @memex.owner)

      populate_elasticsearch_index!([@item])

      [option["name"], option["name"].upcase].each do |qualifier_value|
        query = "status:#{qualifier_value}"
        results = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          query:
        ).execute

        assert_equal 1, results.size, "Could not find item matching query '#{query}'"
        assert_equal @item.id, results.first.dig("_source", "database_id")
      end
    end

    test "wildcard queries match correct documents", es_8_only: true do
      # Change name to smedium to test sm*
      @single_select_field.settings["options"].second["name"] = "smedium"
      @single_select_field.save!

      items = [
        new_item("aaaaaaaa"), # small
        new_item("bbbbbbbb"), # smedium
        new_item,
        new_item("cccccccc"), # large
        new_item("dddddddd"), # xlarge
      ]

      populate_elasticsearch_index!(items)

      test_cases = {
        # We expect that sm* will match small and smedium
        "#{@single_select_field.name_slug}:sm*" => [items[0].id, items[1].id],
        # We expect that *ge will match large and xlarge but nothing else
        "#{@single_select_field.name_slug}:*ge" => [items[3].id, items[4].id],
        # The above query should also work case-insensitively.
        "#{@single_select_field.name_slug}:*GE" => [items[3].id, items[4].id],
        # We expect that *a* will match the 3 items with "a" in the name
        "#{@single_select_field.name_slug}:*a*" => [items[0].id, items[3].id, items[4].id],
        # We expect that * will match all 4 non-empty items
        "#{@single_select_field.name_slug}:*" => [items[0].id, items[1].id, items[3].id, items[4].id],
      }

      test_cases.each do |query_string, expected_result_ids|
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: query_string
        )
        response = query.execute
        actual_result_ids = response.results.map { |result| result["_source"]["database_id"] }
        assert_same_elements expected_result_ids, actual_result_ids, "Query that failed: #{query_string}"
      end
    end
  end

  def new_item(value = nil)
    item = create(:memex_project_item, memex_project: @memex)
    create(:single_select_memex_project_column_value, memex_project_item: item, column: @single_select_field, value: value) if value
    item
  end
end
