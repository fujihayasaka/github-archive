# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnMilestoneTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @repo = create(:repository)
    @owner_org = create(:organization)
    @memex = create(:memex_project, owner: @owner_org)
    @milestone = create(:milestone, repository: @repo)
    @issue = create(:issue, milestone: @milestone, repository: @repo)
    @issue_item = create(:memex_project_item, content: @issue, memex_project: @memex)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo).tap { |pull| pull.issue.update!(milestone: @milestone) }
    @pull_item = create(:memex_project_item, memex_project: @memex, content: @pull)
    @draft_issue_item = @memex.build_draft_issue(creator: @issue.user, title: "An idea").tap(&:save!)
    @milestone_field = @memex.columns.find(&:milestone?)&.to_field

    @items = []
    @milestones = []
    milestone_titles = %w[amilestone bmilestone cmilestone]

    3.times do |n|
      repository = create(:repository, owner: @owner_org)
      @milestones << create(:milestone, title: milestone_titles[n], repository: repository)
      issue = create(:issue, milestone: @milestones[n], repository: repository)
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
            repository_id: { type: "long" },
            title: {
              type: "text",
              fields: { keyword: { type: "keyword" } },
              copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS
            }
          }
        },
        @milestone_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads milestone data" do
      @milestone_field.preload_elasticsearch_document_data([@issue_item])
      assert_no_queries { @milestone_field.elasticsearch_document(@issue_item) }
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing a milestone title for an issue item" do
      expected_milestone_metadata = { title: @issue.milestone&.title, repository_id: @issue.repository_id, id: @issue.milestone&.id }
      refute_nil expected_milestone_metadata

      assert_equal(
        expected_milestone_metadata,
        @milestone_field.elasticsearch_document(@issue_item).to_hash
      )
    end

    test "returns a fragment containing a milestone title for a pull request item" do
      expected_milestone_metadata = { title: @pull.milestone&.title, repository_id: @pull.repository_id, id: @pull.milestone&.id }
      refute_nil expected_milestone_metadata
      assert_equal(
        expected_milestone_metadata,
        @milestone_field.elasticsearch_document(@pull_item).to_hash
      )
    end

    test "returns nil for a draft issue item" do
      assert_nil @milestone_field.elasticsearch_document(@draft_issue_item)
    end
  end

  context "#seed_elasticsearch_document" do
    test "picks one of the milestone options from the context" do
      milestones = create_list(:milestone, 3)

      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(
        milestones: milestones,
        single_select_range: (1..1)
      )

      assert_includes(
        milestones.map(&:title),
        @milestone_field.seed_elasticsearch_document(context).title
      )
    end
  end

  context "#sorting milestones" do
    test "ascending order" do
      populate_elasticsearch_index!(@items)
      milestone_column = @memex.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)

      sort_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
        sort: [milestone_column.to_field.sort_fragment(direction: "asc")]
      )

      sorted_values = sort_query.execute.results.map do |i|
        i["sort"].first
      end

      assert_equal [@milestones[0].title, @milestones[1].title, @milestones[2].title], sorted_values
    end

    test "descending order" do
      populate_elasticsearch_index!(@items)
      milestone_column = @memex.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)

      sort_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
        sort: [milestone_column.to_field.sort_fragment(direction: "desc")]
      )

      sorted_values = sort_query.execute.results.map do |i|
        i["sort"].first
      end

      assert_equal [@milestones[2].title, @milestones[1].title, @milestones[0].title], sorted_values
    end
  end

  context "#existence_fragment" do
    test "returns the expected query fragment hash for 'no:milestone' query" do
      expected_query_fragment = {
        nested: {
          path: "field_values",
          query: {
            exists: { field: "field_values.milestone_value.title" }
          }
        }
      }

      assert_equal expected_query_fragment, @milestone_field.existence_fragment
    end
  end

  context "#query_fragment" do
    test "returns expected results for a query matching a milestone name" do
      milestone_title = @issue.milestone.title

      expected_query_fragment = {
        bool: {
          should: [
            {
              nested: {
                path: "field_values",
                query: {
                  term: {
                    "field_values.milestone_value.title.keyword" => {
                      value: milestone_title,
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
      query_fragment = @milestone_field.query_fragment(values: [milestone_title], is_negated: false, context:)

      assert_equal expected_query_fragment, query_fragment
    end

    test "returns the expected query fragment hash for a negated milestone query" do
      milestone_title = @issue.milestone.title

      expected_query_fragment = {
        bool: {
          must_not: [
            {
              nested: {
                path: "field_values",
                query: {
                  term: {
                    "field_values.milestone_value.title.keyword" => {
                      value: milestone_title,
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
      query_fragment = @milestone_field.query_fragment(values: [milestone_title], is_negated: true, context:)

      assert_equal expected_query_fragment, query_fragment
    end

    test "returns the expected query fragment hash for a wildcard milestone query" do
      milestone_title = "#{@issue.milestone.title}*"

      expected_query_fragment = {
        bool: {
          must_not: [
            {
              nested: {
                path: "field_values",
                query: {
                  wildcard: {
                    "field_values.milestone_value.title.keyword" => {
                      value: milestone_title,
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
      query_fragment = @milestone_field.query_fragment(values: [milestone_title], is_negated: true, context:)

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
        "#{@milestone_field.query_slug}:wild*" => [items[1].id, items[0].id],
        # We expect that the same query as above is case-insensitive.
        "#{@milestone_field.query_slug}:WILD*" => [items[1].id, items[0].id],
        # We expect that *es* will match the 3 items with the "test" value
        "#{@milestone_field.query_slug}:*es*" => [items[0].id, items[1].id, items[3].id],
        # We expect that *one will match the 2 items with the "one" value, including the one with no other characters
        "#{@milestone_field.query_slug}:*one" => [items[1].id, items[4].id],
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
      populate_elasticsearch_index!([@issue_item])

      [@milestone.title, @milestone.title.upcase].each do |qualifier_value|
        query = "#{@milestone_field.query_slug}:\"#{qualifier_value}\""
        results = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query:
        ).execute

        assert_equal 1, results.size
        assert_equal @issue_item.id, results.first.dig("_source", "database_id")
      end
    end
  end

  def new_item(milestone_title)
    repo = create(:repository, owner: @owner_org)
    milestone = create(:milestone, title: milestone_title, repository: repo)
    issue = create(:issue, milestone: milestone, repository: repo)
    create(:memex_project_item, content: issue, memex_project: @memex)
  end
end
