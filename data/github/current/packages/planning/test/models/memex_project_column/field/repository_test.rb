# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnRepositoryTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @issue = create(:issue)
    @owner_org = create(:organization)
    @memex = create(:memex_project, owner: @owner_org)
    @item = create(:memex_project_item, content: @issue, memex_project: @memex)
    @repository_field = @item.memex_project.columns.find(&:repository?)&.to_field

    @draft_issue = create(:draft_issue)
    @draft_item = create(:memex_project_item, memex_project: @item.memex_project, content: @draft_issue)

    @items = []
    @repositories = []
    repository_names = %w[arepository brepository crepository]

    3.times do |n|
      @repositories << create(:repository, name: repository_names[n], owner: @owner_org)
      issue = create(:issue, repository: @repositories[n])
      @items << create(:memex_project_item, content: issue, memex_project: @memex)
    end
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
          dynamic: "strict",
          properties: {
            id: { type: "long" },
            owner_id: { type: "long" },
            owner_type: { type: "keyword" },
            full_name: {
              type: "text",
              fields: {
                keyword: { type: "keyword" }
              },
              copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS
            }
          }
        },
        @repository_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads repository data" do
      @repository_field.preload_elasticsearch_document_data([@item])
      assert_query_count(0, ignore_feature_flags: true) do
        @repository_field.elasticsearch_document(@item)
      end
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing a repository" do
      repository_metadata = {
        id: @issue.repository.id,
        owner_id: @issue.repository.owner_id,
        owner_type: @issue.repository.owner.type,
        full_name: @issue.repository.full_name
      }

      assert_equal(
        repository_metadata,
        @repository_field.elasticsearch_document(@item).to_hash
      )
    end

    test "returns nil for a draft issue" do
      assert_nil @repository_field.elasticsearch_document(@draft_item)
    end
  end

  context "#seed_elasticsearch_document" do
    test "generates a valid repository value" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(require_non_nil_value: true)
      repository_value_name = @repository_field.seed_elasticsearch_document(context).to_hash[:full_name]
      refute_nil repository_value_name
      assert_equal(repository_value_name.split("/").length, 2)
    end
  end

  context "#sorting repositories" do
    test "ascending order" do
      populate_elasticsearch_index!(@items)
      repository_column = @memex.find_column_by_name_or_id(MemexProjectColumn::REPOSITORY_COLUMN_NAME)

      sort_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
        sort: [repository_column.to_field.sort_fragment(direction: "asc")]
      )

      sorted_values = sort_query.execute.results.map do |i|
        i["sort"].first
      end

      assert_equal [@repositories[0].nwo, @repositories[1].nwo, @repositories[2].nwo], sorted_values
    end

    test "descending order" do
      populate_elasticsearch_index!(@items)
      repository_column = @memex.find_column_by_name_or_id(MemexProjectColumn::REPOSITORY_COLUMN_NAME)

      sort_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
        sort: [repository_column.to_field.sort_fragment(direction: "desc")]
      )

      sorted_values = sort_query.execute.results.map do |i|
        i["sort"].first
      end

      assert_equal [@repositories[2].nwo, @repositories[1].nwo, @repositories[0].nwo], sorted_values
    end
  end

  context "#existence_fragment" do
    test "returns the expected query fragment hash for 'no:repository' query" do
      expected_query_fragment = {
        nested: {
          path: "field_values",
          query: {
            exists: { field: "field_values.repository_value.full_name" }
          }
        }
      }

      assert_equal expected_query_fragment, @repository_field.existence_fragment
    end
  end

  context "#query_fragment" do
    test "returns expected results for a query matching a repository name" do
      repository_name = @issue.repository.name

      expected_query_fragment = {
        bool: {
          should: [
            {
              nested: {
                path: "field_values",
                query: {
                  term: {
                    "field_values.repository_value.full_name.keyword" => {
                      value: repository_name,
                      case_insensitive: true,
                    }
                  }
                }
              }
            }
          ],
          minimum_should_match: 1
        }
      }
      context = Search::Memex::Context.new(memex_project: @memex, viewer: @issue.assignees.first)
      query_fragment = @repository_field.query_fragment(values: [repository_name], is_negated: false, context:)

      assert_equal expected_query_fragment, query_fragment
    end

    test "returns the expected query fragment hash for a negated repository query" do
      repository_name = @issue.repository.name

      expected_query_fragment = {
        bool: {
          must_not: [
            {
              nested: {
                path: "field_values",
                query: {
                  term: {
                    "field_values.repository_value.full_name.keyword" => {
                      value: repository_name,
                      case_insensitive: true,
                    }
                  }
                }
              }
            }
          ]
        }
      }
      context = Search::Memex::Context.new(memex_project: @memex, viewer: @issue.assignees.first)
      query_fragment = @repository_field.query_fragment(values: [repository_name], is_negated: true, context:)

      assert_equal expected_query_fragment, query_fragment
    end

    test "returns the expected query fragment hash for a wildcard repository query" do
      repository_name = "#{@issue.repository.name}*"

      expected_query_fragment = {
        bool: {
          must_not: [
            {
              nested: {
                path: "field_values",
                query: {
                  wildcard: {
                    "field_values.repository_value.full_name.keyword" => {
                      value: repository_name,
                      case_insensitive: true,
                    }
                  }
                }
              }
            }
          ]
        }
      }
      context = Search::Memex::Context.new(memex_project: @memex, viewer: @issue.assignees.first)
      query_fragment = @repository_field.query_fragment(values: [repository_name], is_negated: true, context:)

      assert_equal expected_query_fragment, query_fragment
    end
  end

  context "query behaviour" do
    test "wildcard queries match correct documents", es_8_only: true do
      items = [
        new_item("wildcard-test-two"),
        new_item("wildcard-test-one"),
        new_item("never-queried"),
        new_item("test"),
        new_item("one"),
      ]

      populate_elasticsearch_index!(items)

      test_cases = {
        # We expect that wild* will match the 2 items that start with "wildcard" but nothing else
        "#{@repository_field.query_slug}:#{@owner_org.display_login}/wild*" => [items[1].id, items[0].id],
        # The same query as above should work case-insensitively.
        "#{@repository_field.query_slug}:#{@owner_org.display_login}/WILD*" => [items[1].id, items[0].id],
        # We expect that *es* will match the 3 items with the "test" value
        "#{@repository_field.query_slug}:#{@owner_org.display_login}/*es*" => [items[0].id, items[1].id, items[3].id],
        # We expect that *one will match the 2 items with the "one" value, including the one with no other characters
        "#{@repository_field.query_slug}:#{@owner_org.display_login}/*one" => [items[1].id, items[4].id],
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
      populate_elasticsearch_index!([@item])

      [@issue.repository.full_name, @issue.repository.full_name.upcase].each do |qualifier_value|
        query = "#{@repository_field.query_slug}:#{qualifier_value}"
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

  def new_item(repository_name)
    repo = create(:repository, name: repository_name, owner: @owner_org)
    issue = create(:issue, repository: repo)
    create(:memex_project_item, content: issue, memex_project: @memex)
  end
end
