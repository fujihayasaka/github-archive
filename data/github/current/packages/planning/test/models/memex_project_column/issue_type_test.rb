# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumn::IssueTypeTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    GitHub.flipper[:issue_types].enable
    @organization = create(:organization)
    @task_issue_type = @organization.issue_types.find_by!(name: IssueType::DEFAULTS.first[:name])
    @memex_project = create(:memex_project, owner: @organization)
    @repo = create(:repository, owner: @organization)
    @issue = create(:issue, repository: @repo)
    @issue_item = create(:memex_project_item, memex_project: @memex_project, content: @issue)
    @task_issue = create(:issue, repository: @repo, issue_type: @task_issue_type)
    @task_issue_item = create(:memex_project_item, memex_project: @memex_project, content: @task_issue)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
    @pull_item = create(:memex_project_item, memex_project: @memex_project,  content: @pull)
    @draft_issue_item = @memex_project.build_draft_issue(creator: @issue.user, title: "An idea").tap(&:save!)
    @issue_type_column = @memex_project.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
    @issue_type_field = @issue_type_column.to_field

    @items = []
    @issue_types = []

    issue_type_names = %w[Apple Bread Carrot]

    issue_type_names.each do |name|
      issue_type = @organization.issue_types.find_or_create_by!(name: name)
      @issue_types << issue_type
      issue = create(:issue, issue_type: issue_type, repository: @repo)
      @items << create(:memex_project_item, content: issue, memex_project: @memex_project)
    end
  end

  setup do
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context ".data_type" do
    test "is expected data_type" do
      assert_equal :issue_type, MemexProjectColumn::IssueType.data_type
    end
  end

  context ".elasticsearch_mapping" do
    test "returns the correct multi-field configuration" do
      assert_equal(
        {
          dynamic: "strict",
          properties: {
            id: {
              type: "long",
            },
            name: {
              type: "text",
              fields: { keyword: { type: "keyword" } },
              copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS
            },
          },
        },
        @issue_type_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads issue types" do
      @issue_type_field.preload_elasticsearch_document_data([@task_issue_item])

      assert_no_queries do
        @issue_type_field.elasticsearch_document(@task_issue_item)
      end
    end
  end

  context "#elasticsearch_document" do
    test "returns a type elasticsearch document when issue has an issue type" do
      expected_elasticsearch_document = {
        id: @task_issue_type.id,
        name: @task_issue_type.name,
      }

      assert_equal @task_issue_type, @task_issue_item.content.issue_type
      assert_equal expected_elasticsearch_document, @issue_type_field.elasticsearch_document(@task_issue_item).to_hash
    end

    test "does not return indexable document when the issue type is disabled" do
      @task_issue_type.update!(enabled: false)

      assert_nil @task_issue_item.content.issue_type, "Expected issue type to not be set as its disabled"
      assert_equal @task_issue_type, @task_issue_item.issue_type, "Expected issue type to be set"
      assert_nil @issue_type_field.elasticsearch_document(@task_issue_item), "Expected issue type to not be indexed"
    end

    test "does not return an elasticsearch document if issue type does not exist, but issues.issue_type_id still populated" do
      @task_issue_type.destroy!

      assert_equal @task_issue_type.id, @task_issue_item.content.reload.issue_type_id, "Expected issue to still have issue_type_id"
      assert_nil @issue_type_field.elasticsearch_document(@task_issue_item)
    end

    test "does not return an elasticsearch document when issue does not have an issue type" do
      assert_nil @issue_item.content.issue_type
      assert_nil @issue_type_field.elasticsearch_document(@issue_item)
    end

    test "does not return an elasticsearch document for a pull request item" do
      assert_nil @issue_type_field.elasticsearch_document(@pull_item)
    end

    test "returns nil for a draft issue item" do
      assert_nil @issue_type_field.elasticsearch_document(@draft_issue_item)
    end
  end

  context "#seed_elasticsearch_document" do
    test "picks one of the issue type options from the context when seeding an issue" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(
        issue_types: [@task_issue_type],
        content_type: Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
        single_select_range: (1..1)
      )

      assert_equal @task_issue_type.name, @issue_type_field.seed_elasticsearch_document(context).name
    end

    test "does not pick one of the issue type options from the context when seeding a pull request" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(
        issue_types: [@task_issue_type],
        content_type: Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest,
        single_select_range: (1..1)
      )

      assert_nil @issue_type_field.seed_elasticsearch_document(context)
    end

    test "does not pick one of the issue type options from the context when seeding a draft issue" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(
        issue_types: [@task_issue_type],
        content_type: Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue,
        single_select_range: (1..1)
      )

      assert_nil @issue_type_field.seed_elasticsearch_document(context)
    end
  end

  context "#sorting issue types" do
    test "ascending order" do
      populate_elasticsearch_index!(@items)

      sort_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex_project,
        viewer: @user,
        query: "",
        sort: [@issue_type_field.sort_fragment(direction: "asc")]
      )

      sorted_values = sort_query.execute.results.map do |i|
        i["sort"].first
      end

      assert_equal %w[Apple Bread Carrot], sorted_values
    end

    test "descending order" do
      populate_elasticsearch_index!(@items)

      sort_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex_project,
        viewer: @user,
        query: "",
        sort: [@issue_type_field.sort_fragment(direction: "desc")]
      )

      sorted_values = sort_query.execute.results.map do |i|
        i["sort"].first
      end

      assert_equal %w[Carrot Bread Apple], sorted_values
    end
  end

  context "querying issue types" do
    test "returns matching results for a case-insensitive query matching an issue type", es_8_only: true do
      discovery_issue_type = create(:issue_type, owner: @organization, name: "Discovery", private: false, enabled: true)
      discovery_issue = create(:issue, issue_type: discovery_issue_type, repository: @repo)
      discovery_memex_project_item = create(:memex_project_item, content: discovery_issue, memex_project: @memex_project)

      chore_issue_type = create(:issue_type, owner: @organization, name: "Chore", private: false, enabled: true)
      chore_issue = create(:issue, issue_type: chore_issue_type, repository: @repo)
      chore_memex_project_item = create(:memex_project_item, content: chore_issue, memex_project: @memex_project)

      populate_elasticsearch_index!([discovery_memex_project_item, chore_memex_project_item])

      %w(discovery dIsCoVeRy).each do |qualifier_value|
        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex_project.reload,
          viewer: @user,
          query: "#{@issue_type_field.query_slug}:#{qualifier_value}",
        ).execute

        response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

        assert_equal 1, response.total
        assert_same_elements [discovery_memex_project_item.id], response_database_ids
      end
    end

    test "returns matching results for a query matching multiple issue types", es_8_only: true do
      discovery_issue_type = create(:issue_type, owner: @organization, name: "Discovery", private: false, enabled: true)
      discovery_issue = create(:issue, issue_type: discovery_issue_type, repository: @repo)
      discovery_memex_project_item = create(:memex_project_item, content: discovery_issue, memex_project: @memex_project)

      chore_issue_type = create(:issue_type, owner: @organization, name: "Chore", private: false, enabled: true)
      chore_issue = create(:issue, issue_type: chore_issue_type, repository: @repo)
      chore_memex_project_item = create(:memex_project_item, content: chore_issue, memex_project: @memex_project)

      extra_issue_type = create(:issue_type, owner: @organization, name: "Extra", private: false, enabled: true)
      extra_issue = create(:issue, issue_type: extra_issue_type, repository: @repo)
      extra_memex_project_item = create(:memex_project_item, content: extra_issue, memex_project: @memex_project)

      populate_elasticsearch_index!([discovery_memex_project_item, chore_memex_project_item, extra_memex_project_item])
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex_project.reload,
        viewer: @user,
        query: "#{@issue_type_field.query_slug}:Discovery,Chore",
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      assert_equal 2, response.total
      assert_same_elements [discovery_memex_project_item.id, chore_memex_project_item.id], response_database_ids
    end

    test "returns matching results for a case-insensitive wildcard query matching", es_8_only: true do
      discovery_issue_type = create(:issue_type, owner: @organization, name: "Discovery", private: false, enabled: true)
      discovery_issue = create(:issue, issue_type: discovery_issue_type, repository: @repo)
      discovery_memex_project_item = create(:memex_project_item, content: discovery_issue, memex_project: @memex_project)

      chore_issue_type = create(:issue_type, owner: @organization, name: "Chore", private: false, enabled: true)
      chore_issue = create(:issue, issue_type: chore_issue_type, repository: @repo)
      chore_memex_project_item = create(:memex_project_item, content: chore_issue, memex_project: @memex_project)

      populate_elasticsearch_index!([discovery_memex_project_item, chore_memex_project_item])

      %w(Disc*very DISC*VERY).each do |qualifier_value|
        query = "#{@issue_type_field.query_slug}:#{qualifier_value}"
        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex_project.reload,
          viewer: @user,
          query:,
        ).execute

        response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

        assert_equal 1, response.total, "Could not find item matching query '#{query}'"
        assert_same_elements [discovery_memex_project_item.id], response_database_ids
      end
    end

    test "returns matching results for items without an issue type" do
      issue_with_issue_type = create(:issue, issue_type: @task_issue_type, repository: @repo)
      memex_project_item_with_issue_type = create(:memex_project_item, content: issue_with_issue_type, memex_project: @memex_project)

      issue_without_issue_type = create(:issue, repository: @repo)
      memex_project_item_without_issue_type = create(:memex_project_item, content: issue_without_issue_type, memex_project: @memex_project)

      populate_elasticsearch_index!([memex_project_item_with_issue_type, memex_project_item_without_issue_type])
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex_project.reload,
        viewer: @user,
        query: "no:#{@issue_type_field.query_slug}",
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      refute_nil memex_project_item_with_issue_type.content.issue_type, "Expected project item to have an issue type"
      assert_nil memex_project_item_without_issue_type.content.issue_type, "Expected project item to not have an issue type"
      assert_equal 1, response.total
      assert_same_elements [memex_project_item_without_issue_type.id], response_database_ids
    end

    test "returns matching results for items with an issue type set" do
      issue_with_issue_type = create(:issue, issue_type: @task_issue_type, repository: @repo)
      memex_project_item_with_issue_type = create(:memex_project_item, content: issue_with_issue_type, memex_project: @memex_project)

      issue_without_issue_type = create(:issue, repository: @repo)
      memex_project_item_without_issue_type = create(:memex_project_item, content: issue_without_issue_type, memex_project: @memex_project)

      populate_elasticsearch_index!([memex_project_item_with_issue_type, memex_project_item_without_issue_type])
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex_project.reload,
        viewer: @user,
        query: "-no:#{@issue_type_field.query_slug}",
      ).execute

      response_database_ids = response.results.map { |r| r["_source"]["database_id"] }

      refute_nil memex_project_item_with_issue_type.content.issue_type, "Expected project item to have an issue type"
      assert_nil memex_project_item_without_issue_type.content.issue_type, "Expected project item to not have an issue type"
      assert_equal 1, response.total
      assert_same_elements [memex_project_item_with_issue_type.id], response_database_ids
    end

    test "query_slug" do
      assert_equal :type, @issue_type_field.query_slug
    end

    context "#existence_fragment" do
      test "returns the expected query fragment hash for 'no:type' query" do
        expected_query_fragment = {
          nested: {
            path: "field_values",
            query: {
              exists: {
                field: "field_values.issue_type_value.id",
              }
            }
          }
        }

        assert_equal expected_query_fragment, @issue_type_field.existence_fragment
      end
    end

    context "#query_fragment" do
      test "returns expected results for a query matching an issue type name" do
        issue_type_name = @task_issue.issue_type.name

        expected_query_fragment = {
          bool: {
            should: [
              {
                nested: {
                  path: "field_values",
                  query: {
                    term: {
                      "field_values.issue_type_value.name.keyword" => {
                        value: issue_type_name,
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
        context = Search::Memex::Context.new(memex_project: @memex_project, viewer: @task_issue.user)
        query_fragment = @issue_type_field.query_fragment(values: [issue_type_name], is_negated: false, context:)

        assert_equal expected_query_fragment, query_fragment
      end

      test "returns the expected query fragment hash for a negated issue type query" do
        issue_type_name = @task_issue.issue_type.name

        expected_query_fragment = {
          bool: {
            must_not: [
              {
                nested: {
                  path: "field_values",
                  query: {
                    term: {
                      "field_values.issue_type_value.name.keyword" => {
                        value: issue_type_name,
                        case_insensitive: true,
                      }
                    }
                  }
                }
              }
            ]
          }
        }
        context = Search::Memex::Context.new(memex_project: @memex_project, viewer: @task_issue.user)
        query_fragment = @issue_type_field.query_fragment(values: [issue_type_name], is_negated: true, context:)

        assert_equal expected_query_fragment, query_fragment
      end

      test "returns the expected query fragment hash for a wildcard issue type query" do
        issue_type_name = "#{@task_issue.issue_type.name}*"

        expected_query_fragment = {
          bool: {
            must_not: [
              {
                nested: {
                  path: "field_values",
                  query: {
                    wildcard: {
                      "field_values.issue_type_value.name.keyword" => {
                        value: issue_type_name,
                        case_insensitive: true,
                      }
                    }
                  }
                }
              }
            ]
          }
        }
        context = Search::Memex::Context.new(memex_project: @memex_project, viewer: @task_issue.user)
        query_fragment = @issue_type_field.query_fragment(values: [issue_type_name], is_negated: true, context:)

        assert_equal expected_query_fragment, query_fragment
      end
    end
  end
end
