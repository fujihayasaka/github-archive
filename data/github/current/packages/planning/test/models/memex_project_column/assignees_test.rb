# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnAssigneesTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @memex = create(:memex_project)
    @issue = create(:assigned_issue)
    @item = create(:memex_project_item, content: @issue, memex_project: @memex)
    @assignees_field = @memex.columns.find(&:assignees?)&.to_field
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
            login: {
              type: "text",
              fields: { keyword: { type: "keyword" } },
              copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS
            }
          }
        },
        @assignees_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#seed_elasticsearch_document" do
    test "picks assignees from the seed context" do
      users = create_list(:user, 3)
      expected_users_metadata = users.map do |user|
        {
          id: user.id,
          login: user.login
        }
      end
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(
        users: users,
        require_non_nil_value: true
      )
      refute_empty expected_users_metadata & @assignees_field.seed_elasticsearch_document(context).map { |a| a.to_hash }
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads assignee relationships for issues" do
      @assignees_field.preload_elasticsearch_document_data([@item])
      assert_no_queries { @assignees_field.elasticsearch_document(@item) }
    end

    test "preloads assignee relationships for pull_requests" do
      pull = create(:pull_request, :disable_disk_access)
      pull_item = create(:memex_project_item, content: pull)

      @assignees_field.preload_elasticsearch_document_data([pull_item])
      assert_no_queries { @assignees_field.elasticsearch_document(pull_item) }
    end

    test "preloads assignee relationships for draft issues" do
      draft_issue_item = @item.memex_project.build_draft_issue(creator: @issue.user, title: "An idea").tap(&:save!)
      draft_issue_item.reload

      @assignees_field.preload_elasticsearch_document_data([draft_issue_item])
      assert_no_queries { @assignees_field.elasticsearch_document(draft_issue_item) }
    end

    test "safely handles nil content" do
      pull = create(:pull_request, :disable_disk_access)
      pull_item = create(:memex_project_item, content: pull)
      pull_item.expects(:pull_request?).returns(true).at_least_once
      pull_item.update(content: nil)

      assert_nothing_raised do
        @assignees_field.preload_elasticsearch_document_data([pull_item])
      end
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing an array of logins ordered by id in ascending order" do
      zebra_assignee = create(:user, login: "zebra")
      armadillo_assignee = create(:user, login: "armadillo")
      @repo.add_member(zebra_assignee)
      @repo.add_member(armadillo_assignee)
      pull_request = create(:pull_request, :disable_disk_access, repository: @repo, assignees: [zebra_assignee, armadillo_assignee])
      pull_request_item = create(:memex_project_item, content: pull_request, memex_project: @memex)
      expected_assignee_metadata = pull_request.assignees.sort_by(&:id).map do |assignee|
        {
          id: assignee.id,
          login: assignee.login
        }
      end
      assert_equal 2, expected_assignee_metadata.length

      assert_equal(
        expected_assignee_metadata,
        @assignees_field.elasticsearch_document(pull_request_item).map { |a| a.to_hash }
      )
    end
  end

  context "#query_fragment" do
    test "returns the expected query fragment hash when searching by login" do
      expected_query_fragment = {
        bool: {
          should: [
            {
              nested: {
                path: "field_values",
                query: {
                  term: {
                    "field_values.assignees_value.login.keyword" => {
                      value: @issue.assignees.first.login,
                      case_insensitive: true
                    }
                  }
                }
              }
            }
          ],
          minimum_should_match: 1
        }
      }
      context = Search::Memex::Context.new(memex_project: @item.memex_project, viewer: @issue.assignees.first)
      query_fragment = @assignees_field.query_fragment(values: [@issue.assignees.first.login], is_negated: false, context:)

      assert_equal expected_query_fragment, query_fragment
    end

    test "returns the expected query fragment hash when searching by @me" do
      expected_query_fragment = {
        bool: {
          should: [
            {
              nested: {
                path: "field_values",
                query: {
                  term: {
                    "field_values.assignees_value.login.keyword" => {
                      value: @issue.assignees.first.login,
                      case_insensitive: true
                    }
                  }
                }
              }
            }
          ],
          minimum_should_match: 1
        }
      }
      context = Search::Memex::Context.new(memex_project: @item.memex_project, viewer: @issue.assignees.first)
      query_fragment = @assignees_field.query_fragment(values: ["@me"], is_negated: false, context:)

      assert_equal expected_query_fragment, query_fragment
    end

    test "returns the expected query fragment hash when searching with negated login query" do
      expected_query_fragment = {
        bool: {
          must_not: [
            {
              nested: {
                path: "field_values",
                query: {
                  term: {
                    "field_values.assignees_value.login.keyword" => {
                      value: @issue.assignees.first.login,
                      case_insensitive: true
                    }
                  }
                }
              }
            }
          ]
        }
      }
      context = Search::Memex::Context.new(memex_project: @item.memex_project, viewer: @issue.assignees.first)
      query_fragment = @assignees_field.query_fragment(values: [@issue.assignees.first.login], is_negated: true, context:)

      assert_equal expected_query_fragment, query_fragment
    end
  end

  context "#existence_fragment" do
    test "returns the expected query fragment hash for 'no:assignee' query" do
      expected_query_fragment = {
        nested: {
          path: "field_values",
          query: {
            exists: {
              field: "field_values.assignees_value.login"
            }
          }
        }
      }

      assert_equal expected_query_fragment, @assignees_field.existence_fragment
    end
  end

  context "#querying" do
    # case_insensitive matching requires es_8
    test "term queries return correct documents by exact, case-insensitive match", es_8_only: true do
      items = [
        new_item("foo-user"),
        new_item("bar-user", pad_with_extra_user = true),
        new_item("nomatches"),
        new_item(nil, false, user: @user),
        new_item(nil, false, user: @user),
        new_item("barry"),
        new_item,
      ]

      populate_elasticsearch_index!(items)

      test_cases = {
        # We expect a hyphenated login to make an exact match rather than including other "user" logins too
        "#{@assignees_field.query_slug}:foo-user" => [items[0].id],
        # We expect to match items with multiple assignees by a single assingee
        "#{@assignees_field.query_slug}:bar-user" => [items[1].id],
        # # We expect a partial match to return no items without specifying a wildcard
        "#{@assignees_field.query_slug}:foo" => [],
        # We expect a partial match to return no items without specifying a wildcard
        "#{@assignees_field.query_slug}:user" => [],
        # We expect @me to match items assigned to the viewer
        "#{@assignees_field.query_slug}:@me" => [items[3].id, items[4].id],
        # We expect "barry" to just return the meh "barry" item
        "#{@assignees_field.query_slug}:barry" => [items[5].id],
        # We expect case-insensitive searches for matching documents by assignee
        "#{@assignees_field.query_slug}:BaRrY" => [items[5].id],
        # We expect items without assignees to be returned when using no: or -has:
        "-has:#{@assignees_field.query_slug}" => [items[6].id],
        "no:#{@assignees_field.query_slug}" => [items[6].id],
        # We expect items with assignees to be returned when using -no: or has:
        "has:#{@assignees_field.query_slug}" => [items[0].id, items[1].id, items[2].id, items[3].id, items[4].id, items[5].id],
        "-no:#{@assignees_field.query_slug}" => [items[0].id, items[1].id, items[2].id, items[3].id, items[4].id, items[5].id],
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

    # case_insensitive matching requires es_8
    test "wildcard queries match correct documents", es_8_only: true do
      items = [
        new_item("foo-user"),
        new_item("bar-user", pad_with_extra_user = true),
        new_item("nomatches"),
        new_item("amused"),
        new_item("barry"),
      ]

      populate_elasticsearch_index!(items)

      test_cases = {
        # We expect that bar* will match the 2 items that start with bar but nothing else
        "#{@assignees_field.query_slug}:bar*" => [items[1].id, items[4].id],
        # We expect that this will match the 3 items with "us" somewhere in the login
        "#{@assignees_field.query_slug}:*us*" => [items[0].id, items[1].id, items[3].id],
        # We expect that this will match the 2 items that end with "user"
        "#{@assignees_field.query_slug}:*user" => [items[0].id, items[1].id],
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

  context "#graphql_value" do
    test "null returns null" do
      assert_nil @assignees_field.graphql_value(nil)
    end

    test "_noValue returns null" do
      assert_nil @assignees_field.graphql_value("_noValue")
    end

    test "assignee returns an array" do
      value = "monalisa"

      assert_equal [value], @assignees_field.graphql_value(value)
    end
  end

  context "#graphql_title" do
    test "null returns default empty group title" do
      assert_equal "No #{@assignees_field.name}", @assignees_field.graphql_title(nil)
    end

    test "_noValue returns default empty group title" do
      assert_equal "No #{@assignees_field.name}", @assignees_field.graphql_title("_noValue")
    end

    test "assignee" do
      assignee = "monalisa"

      assert_equal assignee, @assignees_field.graphql_title(assignee)
    end
  end

  # Creates a new memex item, favoring an actual user object for the assignee if passed.
  def new_item(login = nil, pad_with_extra_user = false, user: nil)
    issue = if user.present?
      create(:issue, assignees: [user], repository: @repo)
    else
      assignees = login.present? ? [create(:user, login: login)] : []
      assignees.unshift(create(:user, login: "nomatches2")) if pad_with_extra_user
      create(:issue, mannequin_assignees: assignees)
    end
    create(:memex_project_item, memex_project: @memex, content: issue)
  end
end
