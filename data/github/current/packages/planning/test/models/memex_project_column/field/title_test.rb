# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnTitleTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @memex = create(:memex_project)
    @item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex)
    @title_field = @item.memex_project.columns.find(&:title?).to_field
    @title_value = @item.content.memex_denormalized_title_value
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
        @title_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads title data" do
      @title_field.preload_elasticsearch_document_data([@item])
      assert_no_queries { @title_field.elasticsearch_document(@item) }
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing the title" do
      refute_nil @title_value[:title][:raw]
      assert_equal(
        @title_value[:title][:raw],
        @title_field.elasticsearch_document(@item)
      )
    end

    test "raises an error if the item's content (issue) repository has been deleted" do
      @item.content.repository.destroy
      @item.reload

      e = assert_raises(MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError) do
        @title_field.elasticsearch_document(@item)
      end
      assert_equal "repository for item_id: #{@item.id} does not exist", e.message
    end

    test "raises an error if the item's content (pull request) repository has been deleted" do
      pull_request = create(:pull_request, :disable_disk_access)
      item = create(:memex_project_item, content: pull_request)
      pr_title_field = item.memex_project.columns.find(&:title?).to_field

      item.content.repository.delete
      item.reload

      e = assert_raises(MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError) do
        pr_title_field.elasticsearch_document(item)
      end
      assert_equal "repository for item_id: #{item.id} does not exist", e.message
    end
  end

  context "#seed_elasticsearch_document" do
    test "generates a string" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new
      assert_predicate @title_field.seed_elasticsearch_document(context), :present?
    end
  end

  context "#query_fragment" do
    test "returns the expected query fragment hash" do
      title_string = @title_value.dig(:title, :raw)
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
                            value: @title_field.id
                          }
                        }
                      },
                      {
                        term: {
                          "field_values.title_value.keyword" => {
                            value: title_string,
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
      query_fragment = @title_field.query_fragment(values: [title_string], is_negated: false, context:)

      assert_equal expected_query_fragment, query_fragment
    end

    test "returns the expected query fragment hash for a negated query" do
      title_string = @title_value.dig(:title, :raw)
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
                            value: @title_field.id
                          }
                        }
                      },
                      {
                        term: {
                          "field_values.title_value.keyword" => {
                            value: title_string,
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
      query_fragment = @title_field.query_fragment(values: [title_string], is_negated: true, context:)

      assert_equal expected_query_fragment, query_fragment
    end
  end

  # data validation prevents issues from having no title, so this filter intentionally does nothing
  context "#existence_fragment" do
    test "returns the expected query fragment hash for 'no:title' query" do
      assert_empty @title_field.existence_fragment
    end
  end

  context "query behaviour" do
    test "wildcard queries match correct documents", es_8_only: true do
      items = [
        new_item("wildcard test two"),
        new_item("wildcard test one"),
        new_item("never queried"),
        new_item("test"),
        new_item("one"),
      ]

      populate_elasticsearch_index!(items)

      test_cases = {
        # We expect that wild* will match the 2 items that start with "wildcard" but nothing else
        "#{@title_field.name_slug}:wild*" => [items[1].id, items[0].id],
        # The above query should also work case-insensitively.
        "#{@title_field.name_slug}:WILD*" => [items[1].id, items[0].id],
        # We expect that *es* will match the 3 items with the "test" value
        "#{@title_field.name_slug}:*es*" => [items[0].id, items[1].id, items[3].id],
        # We expect that *one will match the 2 items with the "one" value, including the one with no other characters
        "#{@title_field.name_slug}:*one" => [items[1].id, items[4].id],
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

    test "returns results matching a case-insensitive query", es_8_only: true do
      title = @title_value.dig(:title, :raw)

      populate_elasticsearch_index!([@item])

      [title, title.upcase].each do |qualifier_value|
        query = "title:\"#{qualifier_value}\""
        results = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          query:
        ).execute

        assert_equal 1, results.size, "Could not find item matching query '#{query}'"
        assert_equal @item.id, results.first.dig("_source", "database_id")
      end
    end
  end

  def new_item(title_value = nil)
    issue = create(:issue, title: title_value)
    create(:memex_project_item, content: issue, memex_project: @memex)
  end
end
