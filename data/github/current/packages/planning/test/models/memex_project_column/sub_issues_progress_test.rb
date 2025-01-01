# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnSubIssuesProgressTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @admin = create(:verified_user)
    @org = create(:organization, admin: @admin)
    @repo = create(:private_repository, owner: @org)

    @child1 = create(:issue, repository: @repo)
    @child2 = create(:issue, repository: @repo)
    @child3 = create(:issue, repository: @repo, state: "closed")
    @child4 = create(:issue, repository: @repo)
    @child5 = create(:issue, repository: @repo, state: "closed")
    @child6 = create(:issue, repository: @repo, state: "closed")

    # 0% completed
    @parent1 = create(:issue, repository: @repo)
    # 50% completed
    @parent2 = create(:issue, repository: @repo)
    # 100% completed
    @parent3 = create(:issue, repository: @repo)
    # Emulates a parent that has had all of its sub-issues removed
    @not_really_a_parent = create(:issue, repository: @repo)
    # A plain ol' project item that does _not_ have an associated SubIssueList
    @issue = create(:issue, repository: @repo)


    @parent1.add_sub_issue!(@child1, @admin.id)
    @parent1.add_sub_issue!(@child2, @admin.id)
    @parent2.add_sub_issue!(@child3, @admin.id)
    @parent2.add_sub_issue!(@child4, @admin.id)
    @parent3.add_sub_issue!(@child5, @admin.id)
    @parent3.add_sub_issue!(@child6, @admin.id)

    @parent1.recalculate_sub_issue_list!
    @parent2.recalculate_sub_issue_list!
    @parent3.recalculate_sub_issue_list!
    @not_really_a_parent.recalculate_sub_issue_list!

    @memex = create(:memex_project, owner: @org)

    @item1 = create(:memex_project_item, content: @parent1, memex_project: @memex)
    @item2 = create(:memex_project_item, content: @parent2, memex_project: @memex)
    @item3 = create(:memex_project_item, content: @parent3, memex_project: @memex)
    @item4 = create(:memex_project_item, content: @not_really_a_parent, memex_project: @memex)
    @item5 = create(:memex_project_item, content: @issue, memex_project: @memex)

    @sub_issues_progress_field = @item1.memex_project.columns.find(&:sub_issues_progress?)&.to_field

    @pull_request = create(
      :pull_request,
      :disable_disk_access,
      repository: @repo,
      user: @admin,
      head_ref: "ref-#{SecureRandom.hex(6)}"
    )
    @pr_item = create(:memex_project_item, content: @pull_request, memex_project: @memex)
    @draft_issue_item = @memex.build_draft_issue(creator: @admin, title: "An idea").tap(&:save!)
  end

  setup do
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context ".elasticsearch_mapping" do
    test "returns the correct object configuration" do
      assert_equal(
        {
          dynamic: "strict",
          properties: {
            total: { type: "long" },
            percent_completed: { type: "long" },
          }
        },
        @sub_issues_progress_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads sub-issues progress data" do
      assert_query_count_per_table({
        issues: 1,
      }) do
        @sub_issues_progress_field.preload_elasticsearch_document_data([@item1, @item2])
      end
      assert_no_queries { @sub_issues_progress_field.elasticsearch_document(@item1) }
      assert_no_queries { @sub_issues_progress_field.elasticsearch_document(@item2) }
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing sub-issues progress for an issue item" do
      assert_equal(
        {
          total: @parent1.sub_issue_list.total,
          percent_completed: @parent1.sub_issue_list.percent_completed,
        },
        @sub_issues_progress_field.elasticsearch_document(@item1).to_hash
      )
    end

    test "returns nil for a draft issue" do
      assert_nil @sub_issues_progress_field.elasticsearch_document(@draft_issue_item)
    end

    test "returns nil for a pull request" do
      assert_nil @sub_issues_progress_field.elasticsearch_document(@pr_item)
    end

    test "returns nil for an issue if the sub-issue list total is 0" do
      # Mimicking what happens when sub-issues are removed from an issue
      former_parent = create(:issue, repository: @repo)
      former_parent.sub_issues.update!([])
      former_parent.recalculate_sub_issue_list!
      former_parent_item = create(:memex_project_item, content: former_parent, memex_project: @memex)

      assert_equal 0, former_parent.sub_issue_list.total
      assert_nil @sub_issues_progress_field.elasticsearch_document(former_parent_item)
    end
  end

  context "#seed_elasticsearch_document" do
    test "generates arbitrary sub-issues progress numbers" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(require_non_nil_value: true)
      assert @sub_issues_progress_field.seed_elasticsearch_document(context)
    end
  end

  context "#sort_fragment" do
    test "sorts in ascending order" do
      populate_elasticsearch_index!([@item1, @item2, @item3])

      expected_sorted_values = [@item1, @item2, @item3].map { |i| i.content.sub_issue_list.percent_completed }.sort

      unsorted_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @admin,
        query: "",
      )

      unsorted_response_values = unsorted_query.execute.results.map { |i| i["sort"].first }
      refute_equal expected_sorted_values, unsorted_response_values, "Expected unsorted results, got sorted results - test may be flaky."

      sorted_asc_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @admin,
        query: "",
        sort: [@sub_issues_progress_field.sort_fragment(direction: "asc")]
      )

      sorted_response_values = sorted_asc_query.execute.results.map { |i| i["sort"].first }
      assert_equal expected_sorted_values, sorted_response_values
    end

    test "sorts in descending order" do
      populate_elasticsearch_index!([@item1, @item2, @item3])

      expected_sorted_values = [@item1, @item2, @item3].map { |i| i.content.sub_issue_list.percent_completed }.sort.reverse

      unsorted_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @admin,
        query: "",
      )

      unsorted_response_values = unsorted_query.execute.results.map { |i| i["sort"].first }
      refute_equal expected_sorted_values, unsorted_response_values, "Expected unsorted results, got sorted results - test may be flaky."

      sorted_asc_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @admin,
        query: "",
        sort: [@sub_issues_progress_field.sort_fragment(direction: "desc")]
      )

      sorted_response_values = sorted_asc_query.execute.results.map { |i| i["sort"].first }
      assert_equal expected_sorted_values, sorted_response_values
    end
  end

  context "#existence_fragment" do
    test "returns the expected existence fragment hash for 'no:sub-issues-progress' query" do
      expected_query_fragment = {
        nested: {
          path: "field_values",
          query: {
            bool: {
              must: [
                {
                  range: {
                    "field_values.sub_issues_progress_value.total": {
                      gt: 0
                    }
                  }
                },
                exists: {
                  field: "field_values.sub_issues_progress_value.total"
                }
              ]
            }
          }
        }
      }

      assert_equal expected_query_fragment, @sub_issues_progress_field.existence_fragment
    end
  end

  context "querying" do
    test "correctly queries for existence of sub-issues-progress", es_8_only: true do
      populate_elasticsearch_index!([@item1, @item2, @item3, @item4, @item5])

      queries = ["has:sub-issues-progress", "-no:sub-issues-progress"]

      queries.each do |query_string|
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @admin,
          query: query_string,
        )

        response = query.execute

        # Items 1, 2, and 3
        #   are parent issues with sub-issues and we expect them to be returned in the result set.
        # Item 4
        #   is an issue with a SubIssueList association with 0 sub-issues and we do not expect this to be returned.
        # Item 5
        #   is a plain ol' issue that does not have a SubIssueList association and we do not expect this to be returned.
        expected_ids = [@item1.id, @item2.id, @item3.id]
        actual_ids = response.results.map { |result| result["_source"]["database_id"] }

        assert_same_elements expected_ids, actual_ids
      end
    end

    test "correctly queries for non-existence of sub-issues-progress", es_8_only: true do
      populate_elasticsearch_index!([@item1, @item2, @item3, @item4, @item5])

      queries = ["-has:sub-issues-progress", "no:sub-issues-progress"]

      queries.each do |query_string|
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @admin,
          query: query_string,
        )

        response = query.execute

        # Items 1, 2, and 3
        #   are parent issues with sub-issues and we do not expect them to be returned in the result set.
        # Item 4
        #   is an issue with a SubIssueList association with 0 sub-issues and we do expect this to be returned.
        # Item 5
        #   is a plain ol' issue that does not have a SubIssueList association and we do expect this to be returned.
        expected_ids = [@item4.id, @item5.id]
        actual_ids = response.results.map { |result| result["_source"]["database_id"] }

        assert_same_elements expected_ids, actual_ids
      end
    end
  end
end
