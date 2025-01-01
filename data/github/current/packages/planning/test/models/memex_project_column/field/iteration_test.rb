# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnIterationTest < GitHub::TestCase
  include MemexHelpers
  fixtures do
    @memex = create(:memex_project)
    @iteration_field = create(:iteration_memex_column_with_completed_iterations, upcoming: 10, memex_project: @memex).to_field
    @iteration_options = @iteration_field.settings.dig("configuration", "iterations")
    @completed_iteration_options = @iteration_field.settings.dig("configuration", "completed_iterations")
    @all_iteration_options = (@completed_iteration_options + @iteration_options).sort_by { |i| i["start_date"] }
    @issue = create(:issue)
    @item = create(:memex_project_item, content: @issue, memex_project: @memex)
    @iteration_value = create(:memex_project_column_value, memex_project_item: @item, memex_project_column: @iteration_field, value: @iteration_options.first["id"])
  end

  setup do
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context ".elasticsearch_mapping" do
    test "returns the correct nested multi-field configuration" do
      assert_equal @iteration_field.class.elasticsearch_mapping.to_hash,
        {
          dynamic: "strict",
          properties: {
            id: { type: "keyword" },
            title: {
              type: "text",
              fields: {
                keyword: { type: "keyword" }
              },
              copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS
            },
            start_date: { type: "date", format: "strict_date_optional_time" },
            duration:  { type: "integer" },
          }
        }
    end
  end

  context "#existence_fragment" do
    test "returns the expected query fragment hash for 'no:iteration' query" do
      expected_query_fragment = {
        nested: {
          path: "field_values",
          query: {
            bool: {
              filter: [
                { term: { "field_values.field_id": @iteration_field.id } },
                { exists: { field: "field_values.iteration_value" } }
              ]
            }
          }
        }
      }

      assert_equal expected_query_fragment, @iteration_field.existence_fragment
    end
  end

  context "#query_fragment" do
    test "returns expected results for a query matching an iteration" do
      search_string = @iteration_options.first["title"]
      iteration_id = @iteration_options.first["id"]

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
                            value: @iteration_field.id
                          }
                        }
                      },
                      {
                        term: {
                          "field_values.iteration_value.id": iteration_id
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
      query_fragment = @iteration_field.query_fragment(values: [search_string], is_negated: false, context:)

      assert_equal expected_query_fragment, query_fragment
    end

    test "returns the expected query fragment hash for a negated query" do
      search_string = @iteration_options.first["title"]
      iteration_id = @iteration_options.first["id"]
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
                            value: @iteration_field.id
                          }
                        }
                      },
                      {
                        term: {
                          "field_values.iteration_value.id": iteration_id
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
      query_fragment = @iteration_field.query_fragment(values: [search_string], is_negated: true, context:)

      assert_equal expected_query_fragment, query_fragment
    end

    test "returns the expected query fragment hash for a keyword query" do
      sorted_iterations = @completed_iteration_options + @iteration_options
      supported_keywords = ["@previous", "@current", "@next"]

      supported_keywords.each_with_index do |keyword, i|
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
                              value: @iteration_field.id
                            }
                          }
                        },
                        {
                          term: {
                            "field_values.iteration_value.id": sorted_iterations[i]["id"]
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
        query_fragment = @iteration_field.query_fragment(values: [keyword], is_negated: false, context:)
        assert_equal expected_query_fragment, query_fragment
      end
    end

    test "returns the expected query fragment hash for a macro range query" do
      supported_comparisons = {
        "<": "lt",
        "<=": "lte",
        ">": "gt",
        ">=": "gte"
      }

      sorted_iterations = @completed_iteration_options + @iteration_options

      supported_comparisons.each do |symbol, query_key|
        supported_keywords = ["#{symbol}@previous", "#{symbol}@current", "#{symbol}@next"]

        supported_keywords.each_with_index do |keyword, i|
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
                                value: @iteration_field.id
                              }
                            }
                          },
                          {
                            range: {
                              "field_values.iteration_value.start_date": {
                                "#{query_key}": sorted_iterations[i]["start_date"]
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
          query_fragment = @iteration_field.query_fragment(values: [keyword], is_negated: false, context:)
          assert_equal expected_query_fragment, query_fragment
        end
      end
    end
  end

  test "returns the expected items for a macro query with an inequality comparison" do
    sorted_iterations = @completed_iteration_options + @iteration_options
    previous_iteration = sorted_iterations[0]
    current_iteration = sorted_iterations[1]
    next_iteration = sorted_iterations[2]

    previous_item = new_item_with_iteration(previous_iteration["id"])
    current_item = new_item_with_iteration(current_iteration["id"])
    next_item = new_item_with_iteration(next_iteration["id"])

    macros = ["@previous", "@current", "@next"]

    # expected results for each equality comparison in the format:
    # inequality comparison => array of expected items for each supported macro in the order: @previous, @current, @next
    expectations = {
      "<": [[], [previous_item], [previous_item, current_item]],
      "<=": [[previous_item], [previous_item, current_item], [previous_item, current_item, next_item]],
      ">": [[current_item, next_item], [next_item], []],
      ">=": [[previous_item, current_item, next_item], [current_item, next_item], [next_item]],
    }

    populate_elasticsearch_index!([previous_item, current_item, next_item])

    macros.each_with_index do |macro, i|
      expectations.each do |symbol, expected_items|
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: "#{@iteration_field.name_slug}:#{symbol}#{macro}",
        )
        response = query.execute
        assert_equal expected_items[i].map(&:id), response.results.map { |r| r.dig("_source", "database_id") }
      end
    end
  end

  test "queries for multiple values" do
    sorted_iterations = @completed_iteration_options + @iteration_options
    previous_iteration = sorted_iterations[0]
    current_iteration = sorted_iterations[1]
    next_iteration = sorted_iterations[2]

    previous_item = new_item_with_iteration(previous_iteration["id"])
    current_item = new_item_with_iteration(current_iteration["id"])
    next_item = new_item_with_iteration(next_iteration["id"])

    populate_elasticsearch_index!([previous_item, current_item, next_item])

    query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @user,
      query: "#{@iteration_field.name_slug}:@previous,@current",
    )
    response = query.execute
    assert_equal [previous_item, current_item].map(&:id), response.results.map { _1.dig("_source", "database_id") }
  end

  test "returns only the 3 most recent completed iterations when no filters are applied and include empty groups is true", es_8_only: true do
    field = create(:iteration_memex_column_with_completed_iterations, name: "#{@iteration_field.name}2", completed: 5, memex_project: @memex).to_field
    iteration_options = field.settings.dig("configuration", "iterations").sort_by { _1["start_date"] }
    completed_iteration_options = field.settings.dig("configuration", "completed_iterations").sort_by { _1["start_date"] }
    all_iterations = completed_iteration_options + iteration_options
    previous_3_iterations = completed_iteration_options.last(3)

    # Expect to include the 3 most recently completed iterations plus the current and all future iterations, sorted by start date
    included_iterations = previous_3_iterations + iteration_options
    excluded_iterations = all_iterations - included_iterations

    # Make sure there are actually some iterations to include and exclude
    assert included_iterations.size.positive?
    assert excluded_iterations.size.positive?

    # Create one item for each iteration, some we expect to see included and some we don't
    included_items = included_iterations.map { new_item_with_iteration(_1["id"], field) }
    excluded_items = excluded_iterations.map { new_item_with_iteration(_1["id"], field) }

    populate_elasticsearch_index!(included_items + excluded_items)

    query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @user,
      grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(field_object_or_id: field, include_empty_groups: true),
    )
    response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)

    expected_groups = included_iterations.map { _1["title"] }
    assert_equal expected_groups, response.primary_groups.nodes.map { _1.group_value }

    # Make sure we're including only items matching the Iteration default group filtering.
    # Verifying the overall response total ensures that the filter is applied to the main Elasticsearch query.
    assert_equal included_items.map { _1.id }, response.model_ids
    assert_equal included_items.size, response.total
  end

  test "returns only groups with items when include empty groups is false", es_8_only: true do
    populate_elasticsearch_index!([@item])
    query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @user,
      grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(field_object_or_id: @iteration_field, include_empty_groups: false),
    )
    response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
    expected_groups = [@iteration_options.first["title"]]
    assert_equal expected_groups, response.primary_groups.nodes.map { _1.group_value }
  end

  test "returns expected items when a filter is applied", es_8_only: true do
    selected_iteration = @iteration_options.second
    item = new_item_with_iteration(selected_iteration["id"])
    populate_elasticsearch_index!([item])
    query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @user,
      grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(field_object_or_id: @iteration_field),
      query: "#{@iteration_field.query_slug}:@next"
    )
    response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
    expected_groups = [selected_iteration["title"]]
    assert_equal expected_groups, response.primary_groups.nodes.map { _1.group_value }
  end

  context "grouping" do
    test "returns expected groups when complex filters are applied", es_8_only: true do
      field = create(
        :iteration_memex_column_with_completed_iterations,
        name: "#{@iteration_field.name}2",
        completed: 5,
        upcoming: 5,
        memex_project: @memex
      ).to_field
      items = field.settings_all_iterations.map { new_item_with_iteration(_1["id"], field) }
      populate_elasticsearch_index!(items)
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(field_object_or_id: field, include_empty_groups: true),
        query: "#{field.query_slug}:@previous..@next+2"
      )
      response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)
      previous = field.settings_completed_iterations.sort_by { _1["start_date"] }.last
      next_plus_2 = field.settings_iterations.sort_by { _1["start_date"] }[0..3]
      expected_groups = ([previous] + next_plus_2).map { _1["title"] }
      assert_equal expected_groups, T.must(response.primary_groups).nodes.map { _1.group_value }
    end

    test "returns expected groups when filters exceed configured iterations", es_8_only: true do
      field = create(
        :iteration_memex_column_with_completed_iterations,
        name: "#{@iteration_field.name}2",
        completed: 5,
        upcoming: 5,
        memex_project: @memex
      ).to_field
      items = field.settings_all_iterations.map { new_item_with_iteration(_1["id"], field) }
      populate_elasticsearch_index!(items)
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
          field_object_or_id: field,
          include_empty_groups: true,
          groups_page_size: 25
        ),
        query: "#{field.query_slug}:<@current+100"
      )
      response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)

      configuration = field.settings.dig("configuration")
      all_iterations = (configuration.dig("iterations") + configuration.dig("completed_iterations")).sort_by { |i| i["start_date"] }
      expected_groups = all_iterations.map { _1["title"] }
      assert_equal expected_groups, T.must(response.primary_groups).nodes.map { _1.group_value }
    end

    test "returns expected groups when filters precede configured iterations", es_8_only: true do
      field = create(
        :iteration_memex_column_with_completed_iterations,
        name: "#{@iteration_field.name}2",
        completed: 5,
        upcoming: 5,
        memex_project: @memex
      ).to_field
      items = field.settings_all_iterations.map { new_item_with_iteration(_1["id"], field) }
      populate_elasticsearch_index!(items)
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
          field_object_or_id: field,
          include_empty_groups: true,
          groups_page_size: 25
        ),
        query: "#{field.query_slug}:@previous-20..@current-2"
      )
      response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)

      configuration = field.settings.dig("configuration")
      completed_iterations = configuration.dig("completed_iterations").sort_by { |i| i["start_date"] }
      expected_groups = (completed_iterations.slice(0, completed_iterations.length - 1)).map { _1["title"] }
      assert_equal expected_groups, T.must(response.primary_groups).nodes.map { _1.group_value }
    end

    test "returns no groups when filter excludes all configured iterations by range", es_8_only: true do
      field = create(
        :iteration_memex_column_with_completed_iterations,
        name: "#{@iteration_field.name}2",
        completed: 5,
        upcoming: 5,
        memex_project: @memex
      ).to_field
      items = field.settings_all_iterations.map { new_item_with_iteration(_1["id"], field) }
      populate_elasticsearch_index!(items)
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
          field_object_or_id: field,
          include_empty_groups: true,
          groups_page_size: 25
        ),
        query: "#{field.query_slug}:>@current+20"
      )
      response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)

      expected_groups = []
      assert_equal expected_groups, T.must(response.primary_groups).nodes.map { _1.group_value }
    end

    test "returns no groups when filter by iteration title matches no iterations", es_8_only: true do
      field = create(
        :iteration_memex_column_with_completed_iterations,
        name: "#{@iteration_field.name}2",
        completed: 5,
        upcoming: 5,
        memex_project: @memex
      ).to_field
      items = field.settings_all_iterations.map { new_item_with_iteration(_1["id"], field) }
      populate_elasticsearch_index!(items)
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        grouping_options: MemexProjectColumn::Interface::Groupable::Options.new(
          field_object_or_id: field,
          include_empty_groups: true,
          groups_page_size: 25
        ),
        query: "#{field.query_slug}:NonExistentIteration"
      )
      response = T.cast(query.execute, Search::Responses::GroupedMemexProjectItemResponse)

      expected_groups = []
      assert_equal expected_groups, T.must(response.primary_groups).nodes.map { _1.group_value }
    end
  end

  context "slice by" do
    test "sorts by ascending iteration start date with non-zero counts" do
      # 1 completed and 10 current/future iterations should be configured, in ascending start date
      assert_equal 11, @all_iteration_options.size

      items = @all_iteration_options.values_at(0, 4, 7, 2, 6).map { |iteration| new_item_with_iteration(iteration["id"]) }
      items += @all_iteration_options.values_at(0, 2, 7).map { |iteration| new_item_with_iteration(iteration["id"]) }
      items += @all_iteration_options.values_at(2).map { |iteration| new_item_with_iteration(iteration["id"]) }
      items << create(:memex_project_item, memex_project: @memex)
      populate_elasticsearch_index!(items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        slice_by: @iteration_field.id,
      ).execute

      # Order with non-zero slice counts, excluding empty slice values by default.
      expected_slice_values = @all_iteration_options.values_at(0, 2, 4, 6, 7).map { _1["title"] }
      expected_slice_values << MemexProjectColumn::Interface::Groupable::MISSING_VALUE_GROUP_KEY
      expected_slice_counts = [2, 3, 1, 1, 2, 1]
      assert_equal expected_slice_values, response.slices&.map { _1["slice_value"] }
      assert_equal expected_slice_counts, response.slices&.map { _1["total_count"] }
    end

    test "sorts by ascending iteration start date with non-zero counts first, then empty iteration values when include_empty_slices" do
      # 1 completed and 10 current/future iterations should be configured, in ascending start date
      assert_equal 11, @all_iteration_options.size

      items = @all_iteration_options.values_at(0, 4, 7, 2, 6).map { |iteration| new_item_with_iteration(iteration["id"]) }
      items += @all_iteration_options.values_at(0, 2, 7).map { |iteration| new_item_with_iteration(iteration["id"]) }
      items += @all_iteration_options.values_at(2).map { |iteration| new_item_with_iteration(iteration["id"]) }
      items << create(:memex_project_item, memex_project: @memex)
      populate_elasticsearch_index!(items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        slice_by: @iteration_field.id,
        include_empty_slices: true,
      ).execute

      # Order with non-zero slice counts first, then empty slice counts since include_empty_slices.
      expected_slice_values = @all_iteration_options.values_at(0, 2, 4, 6, 7).map { _1["title"] }
      expected_slice_values << MemexProjectColumn::Interface::Groupable::MISSING_VALUE_GROUP_KEY
      expected_slice_values += @all_iteration_options.values_at(1, 3, 5, 8, 9, 10).map { _1["title"] }
      expected_slice_counts = [2, 3, 1, 1, 2, 1, 0, 0, 0, 0, 0, 0]
      assert_equal expected_slice_values, response.slices&.map { _1["slice_value"] }
      assert_equal expected_slice_counts, response.slices&.map { _1["total_count"] }
    end
  end

  context "#seed_elasticsearch_document" do
    test "picks one of the iteration options" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(require_non_nil_value: true)
      assert_includes(
        @iteration_options.map { |o| o["title"] },
        @iteration_field.seed_elasticsearch_document(context).title
      )
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads iteration data" do
      @iteration_field.preload_elasticsearch_document_data([@item])
      assert_no_queries { @iteration_field.elasticsearch_document(@item) }
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing the iteration" do
      assert_equal(
        @iteration_options.first.deep_symbolize_keys.slice(:id, :title, :start_date, :duration),
        @iteration_field.elasticsearch_document(@item).to_hash
      )
    end

    test "returns nil when no iteration is set" do
      @iteration_value.destroy!
      assert_nil @iteration_field.elasticsearch_document(@item)
    end

    test "returns a fragment containing a completed iteration" do
      item = new_item_with_iteration(@completed_iteration_options.first["id"])

      assert_equal(
        @completed_iteration_options.first.deep_symbolize_keys.slice(:id, :title, :start_date, :duration),
        @iteration_field.elasticsearch_document(item).to_hash
      )
    end

    test "raises an error if the iteration option has been deleted from the list of completed iterations" do
      completed_iteration_options = @iteration_field.settings.dig("configuration", "completed_iterations")
      item = new_item_with_iteration(completed_iteration_options.first["id"])
      removed_completed_iteration = completed_iteration_options.shift

      e = assert_raises(MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError) do
        @iteration_field.elasticsearch_document(item)
      end
      assert_equal "value for iteration id: #{removed_completed_iteration["id"]} not found", e.message
    end

    test "raises an error if the iteration option has been deleted from the list of settings iterations" do
      iteration_options = @iteration_field.settings.dig("configuration", "iterations")
      item = new_item_with_iteration(iteration_options.first["id"])
      removed_iteration = iteration_options.shift

      e = assert_raises(MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError) do
        @iteration_field.elasticsearch_document(item)
      end
      assert_equal "value for iteration id: #{removed_iteration["id"]} not found", e.message
    end
  end

  context "#range" do
    test "returns a range query" do
      iteration_1_title      = @iteration_options[0]["title"]
      iteration_1_start_date = @iteration_options[0]["start_date"]
      iteration_2_title      = @iteration_options[1]["title"]
      iteration_2_start_date = @iteration_options[1]["start_date"]
      search_string          = "#{iteration_1_title}..#{iteration_2_title}"
      expected_range_clause  = { gte: iteration_1_start_date, lte: iteration_2_start_date }

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
                            value: @iteration_field.id
                          }
                        }
                      },
                      {
                        range: {
                          "field_values.iteration_value.start_date": expected_range_clause
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
      query_fragment = @iteration_field.query_fragment(values: [search_string], is_negated: false, context:)

      assert_equal expected_query_fragment, query_fragment
    end
  end

  context "sorting iteration" do
    test "ascending order" do
      iteration_1, iteration_2, iteration_3 = @iteration_field.settings_all_iterations

      # add iterations in random order to help validate that we're not sorting by creation order
      items = [
        new_item_with_iteration(iteration_3["id"]),
        new_item_with_iteration(iteration_2["id"]),
        new_item_with_iteration(iteration_1["id"]),
        new_item_with_iteration(iteration_2["id"])
      ]

      populate_elasticsearch_index!(items)

      expected_asc_order = [
        date_str_to_ms(iteration_1["start_date"]),
        date_str_to_ms(iteration_2["start_date"]),
        date_str_to_ms(iteration_2["start_date"]),
        date_str_to_ms(iteration_3["start_date"])
      ]

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
        sort: [@iteration_field.sort_fragment(direction: "asc")]
      ).execute

      actual_asc_order = response.results.map do |i|
        # "sort"=>[1703721600000, "-Infinity", 414]
        i["sort"].first
      end

      assert_equal expected_asc_order, actual_asc_order
    end

    test "descending order" do
      iteration_1, iteration_2, iteration_3 = @iteration_field.settings_all_iterations

      # add iterations in random order to help validate that we're not sorting by creation order
      items = [
        new_item_with_iteration(iteration_2["id"]),
        new_item_with_iteration(iteration_1["id"]),
        new_item_with_iteration(iteration_2["id"]),
        new_item_with_iteration(iteration_3["id"])
      ]

      populate_elasticsearch_index!(items)

      expected_desc_order = [
        date_str_to_ms(iteration_3["start_date"]),
        date_str_to_ms(iteration_2["start_date"]),
        date_str_to_ms(iteration_2["start_date"]),
        date_str_to_ms(iteration_1["start_date"])
      ]

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
        sort: [@iteration_field.sort_fragment(direction: "desc")]
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      actual_desc_order = response.results.map do |i|
        # "sort"=>[1703721600000, "-Infinity", 414]
        i["sort"].first
      end

      assert_equal expected_desc_order, actual_desc_order
    end
  end

  context "#graphql_value" do
    test "null returns null" do
      assert_nil @iteration_field.graphql_value(nil)
    end

    test "_noValue returns null" do
      assert_nil @iteration_field.graphql_value("_noValue")
    end

    test "option title returns corresponding option identifier" do
      # Make sure we have something to test
      refute_empty @iteration_options

      option = @iteration_options.first

      assert_equal option["id"], @iteration_field.graphql_value(option["title"])
    end
  end

  context "#graphql_title" do
    test "null returns default empty group title" do
      assert_equal "No #{@iteration_field.name}", @iteration_field.graphql_title(nil)
    end

    test "empty string returns default empty group title" do
      assert_equal "No #{@iteration_field.name}", @iteration_field.graphql_title("")
    end

    test "_noValue returns default empty group title" do
      assert_equal "No #{@iteration_field.name}", @iteration_field.graphql_title("_noValue")
    end

    test "present value" do
      value = "Option 1"

      assert_equal value, @iteration_field.graphql_title(value)
    end
  end

  private def new_item_with_iteration(iteration_id, field = @iteration_field)
    item      = create(:memex_project_item, memex_project: @memex)
    iteration = create(
      :iteration_memex_project_column_value,
      memex_project_item: item,
      column: field,
      value: iteration_id,
      json_value: { id: iteration_id }
    )

    item
  end
end
