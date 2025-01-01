# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnLabelsTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @user = create(:verified_user)
    @repo = create(:repository)
    @memex = create(:memex_project)
    @label = create(:label, repository: @repo)
    @issue = create(:issue, repository: @repo).tap { |issue| issue.labels << @label }
    @issue_item = create(:memex_project_item, content: @issue, memex_project: @memex)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo).tap { |pull| pull.issue.labels << @label }
    @pull_item = create(:memex_project_item, memex_project: @memex, content: @pull)
    @draft_issue_item = @issue_item.memex_project.build_draft_issue(creator: @issue.user, title: "An idea").tap(&:save!)
    @labels_field = @memex.columns.find(&:labels?)&.to_field

    # fixtures for sorting
    @labels = []
    @issues = []
    @items = []
    label_names = %w[aword bword cword]
    3.times do |n|
      # create labels with specific names for sorting
      @labels << create(:label, name: label_names[n], repository: @repo)

      # assign labels to issues
      @issues << create(:issue, repository: @repo).tap { |issue| issue.labels << @labels[n] }

      # assign issues to items
      @items << create(:memex_project_item, content: @issues[n], memex_project: @memex)
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
            name: {
              type: "text",
              fields: { keyword: { type: "keyword" } },
              copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS
            },
            repository_id: { type: "long" }
          }
        },
        @labels_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads labels data" do
      @labels_field.preload_elasticsearch_document_data([@issue_item])
      assert_no_queries { @labels_field.elasticsearch_document(@issue_item) }
    end

    test "safely preloads labels data even if an issue has been deleted" do
      pull = create(:pull_request, :disable_disk_access)
      pull_item = create(:memex_project_item, content: pull)
      pull_item.expects(:pull_request?).returns(true).at_least_once
      pull_item.update(content: nil)
      assert_nothing_raised do
        @labels_field.preload_elasticsearch_document_data([pull_item])
      end
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing an array of label names for an issue item" do
      expected_label_metadata = @issue.labels.map do |label|
        {
          id: label.id,
          name: label.name,
          repository_id: label.repository_id
        }
      end
      refute_empty expected_label_metadata

      assert_equal(
        expected_label_metadata,
        @labels_field.elasticsearch_document(@issue_item).map { |l| l.to_hash }
      )
    end

    test "returns a fragment containing an array of label names for an pull request item" do
      expected_label_metadata = @issue.labels.map do |label|
        {
          id: label.id,
          name: label.name,
          repository_id: label.repository_id
        }
      end
      refute_empty expected_label_metadata

      assert_equal(
        expected_label_metadata,
        @labels_field.elasticsearch_document(@pull_item).map { |l| l.to_hash }
      )
    end

    test "returns nil for a draft issue item" do
      assert_nil @labels_field.elasticsearch_document(@draft_issue_item)
    end

    test "labels are ordered by id in ascending order for data consistency comparisons" do
      zebra_label = create(:label, repository: @repo, name: "Zebra")
      armadillo_label = create(:label, repository: @repo, name: "Armadillo")
      issue = create(:issue, repository: @repo)
      issue.labels << zebra_label
      issue.labels << armadillo_label
      issue_item = create(:memex_project_item, content: issue, memex_project: @memex)
      expected_label_metadata = issue.labels.order(id: :asc).map do |label|
        {
          id: label.id,
          name: label.name,
          repository_id: label.repository_id
        }
      end
      refute_empty expected_label_metadata

      assert_equal(
        expected_label_metadata,
        @labels_field.elasticsearch_document(issue_item).map { |l| l.to_hash }
      )
    end
  end

  context "#seed_elasticsearch_document" do
    test "picks labels from the seed context" do
      labels = create_list(:label, 3)
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(
        labels: labels,
        require_non_nil_value: true
      )
      seeded_label_ids = labels.map(&:id)
      es_label_ids = @labels_field.seed_elasticsearch_document(context).map { |l| l.to_hash }.pluck(:id)
      refute_empty seeded_label_ids & es_label_ids
    end
  end

  context "#sorting labels" do
    test "ascending order" do
      populate_elasticsearch_index!(@items)
      labels_column = @memex.find_column_by_name_or_id(MemexProjectColumn::LABELS_COLUMN_NAME)

      sort_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
        sort: [labels_column.to_field.sort_fragment(direction: "asc")]
      )

      sorted_values = sort_query.execute.results.map do |i|
        # ["a", "-Infinity", 31]
        # ["b", "-Infinity", 32]
        # ["c", "-Infinity", 33]
        i["sort"].first
      end

      assert_equal %w[aword bword cword], sorted_values
    end

    test "descending order" do
      populate_elasticsearch_index!(@items)
      labels_column = @memex.find_column_by_name_or_id(MemexProjectColumn::LABELS_COLUMN_NAME)

      sort_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
        sort: [labels_column.to_field.sort_fragment(direction: "desc")]
      )

      sorted_values = sort_query.execute.results.map do |i|
        # ["c", "-Infinity", 117]
        # ["b", "-Infinity", 116]
        # ["a", "-Infinity", 115]
        i["sort"].first
      end

      assert_equal %w[cword bword aword], sorted_values
    end
  end

  context "#existence_fragment" do
    test "returns the expected query fragment hash for 'no:label' query" do
      expected_query_fragment = {
        nested: {
          path: "field_values",
          query: {
            exists: { field: "field_values.labels_value.name" }
          }
        }
      }

      assert_equal expected_query_fragment, @labels_field.existence_fragment
    end
  end

  context "#query_fragment" do
    test "returns expected results for a query matching a label" do
      label_name = @labels.first.name

      expected_query_fragment = {
        bool: {
          should: [
            {
              nested: {
                path: "field_values",
                query: {
                  term: {
                    "field_values.labels_value.name.keyword" => {
                      value: label_name,
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
      query_fragment = @labels_field.query_fragment(values: [label_name], is_negated: false, context:)

      assert_equal expected_query_fragment, query_fragment
    end

    test "returns the expected query fragment hash for a negated label query" do
      label_name = @labels.first.name

      expected_query_fragment = {
        bool: {
          must_not: [
            {
              nested: {
                path: "field_values",
                query: {
                  term: {
                    "field_values.labels_value.name.keyword" => {
                      value: label_name,
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
      query_fragment = @labels_field.query_fragment(values: [label_name], is_negated: true, context:)

      assert_equal expected_query_fragment, query_fragment
    end
  end

  context "query behaviour" do
    test "returns all results if no query is specified" do
      populate_elasticsearch_index!(@items)
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "",
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      assert_equal 3, response.total
      assert_same_elements(@items.map { |item| item.id }, response_database_ids)
    end

    test "returns unlabeled results when using `no:` filter" do
      unlabeled_item = create(:memex_project_item, memex_project: @memex)

      populate_elasticsearch_index!([unlabeled_item].concat(@items))
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "no:#{@labels_field.query_slug}",
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      assert_equal 1, response.total
      assert_same_elements([unlabeled_item.id], response_database_ids)
    end

    test "returns matching results for a case-insensitive query matching a label", es_8_only: true  do
      populate_elasticsearch_index!(@items)

      label_name = @labels[0].name
      matching_item = @items[0]

      [label_name, label_name.upcase].each do |qualifier_value|
        query = "#{@labels_field.query_slug}:#{qualifier_value}"
        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query:,
        ).execute

        response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

        assert_equal 1, response.total, "Could not find label matching query '#{query}'"
        assert_same_elements [matching_item.id], response_database_ids
      end
    end

    test "does not return matching results for a query partially matching a label" do
      populate_elasticsearch_index!(@items)

      label_query = @labels[0].name.chop
      matching_item = @items[0]

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "#{@labels_field.query_slug}:#{label_query}",
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      assert_equal 0, response.total
    end

    test "returns matching results for a query excluding a label" do
      populate_elasticsearch_index!(@items)

      label_name = @labels[0].name
      matching_item = @items[0]

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "-#{@labels_field.query_slug}:#{label_name}",
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      assert_equal 2, response.total
      assert_same_elements [@items[1].id, @items[2].id], response_database_ids
    end
  end
end
