# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnReviewersTest < GitHub::TestCase
  include MemexHelpers
  fixtures do
    @admin = create(:verified_user, login: "org-admin")
    @org = create(:organization, admin: @admin)
    @repo = create(:private_repository, owner: @org)
    @pull_request = create(
      :pull_request,
      :disable_disk_access,
      repository: @repo,
      user: @admin,
      head_ref: "ref-#{SecureRandom.hex(6)}"
    )

    @org_member = create(:verified_user, login: "alpha")
    @org_member2 = create(:verified_user, login: "beta")
    @org_member3 = create(:verified_user, login: "charlie")
    @team = create(:team, organization: @org, privacy: :closed, name: "delta")
    @team.add_repository(@repo, :push)
    @team.add_member(@admin, adder: @admin)
    @org.add_member(@org_member)
    @org.add_member(@org_member2)

    @memex = create(:memex_project, owner: @org)
    @item = create(:memex_project_item, content: @pull_request, memex_project: @memex)

    @issue = create(:issue, repository: @repo, user: @admin)
    @issue_item = create(:memex_project_item, content: @issue, memex_project: @memex)
    @draft_issue_item = @memex.build_draft_issue(creator: T.must(@issue).user, title: "An idea").tap(&:save!)

    @reviewers_field = @item.memex_project.columns.find(&:reviewers?)&.to_field
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
          properties:
          {
            actor_id: { type: "long" },
            actor_slug: { type: "text", fields: { keyword: { type: "keyword" } }, copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS },
            actor_type: { type: "text", fields: { keyword: { type: "keyword" } } }
          }
        },
        @reviewers_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#seed_elasticsearch_document" do
    test "picks reviewers from the seed context" do
      users = create_list(:user, 3)
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(
        users: users,
        require_non_nil_value: true
      )
      expected_reviewers_metadata = users.map do |r|
        {
          actor_id: r.id,
          actor_slug: r.login,
          actor_type: "User"
        }
      end

      refute_empty expected_reviewers_metadata & @reviewers_field.seed_elasticsearch_document(context).map { |r| r.to_hash }
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads reviewers data" do
      @reviewers_field.preload_elasticsearch_document_data([@item])
      assert_no_queries { @reviewers_field.elasticsearch_document(@item) }
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing an array of reviewers for a pull request item" do
      create(:pull_request_review, :approved, pull_request: @pull_request, user: @org_member)
      create(:pull_request_review, :approved, pull_request: @pull_request, user: @org_member2)

      @pull_request.request_review_from(actor: @admin, reviewers: [@org_member])
      @pull_request.request_review_from(actor: @admin, reviewers: [@team])

      reviewers_names = [@team.name, @org_member.login, @org_member2.login]

      assert_same_elements(
        reviewers_names,
        @reviewers_field.elasticsearch_document(@item).map { |r| r.to_hash[:actor_slug] }
      )
    end

    test "returns a fragment containing an empty array for a draft issue" do
      assert_empty(
        @reviewers_field.elasticsearch_document(@draft_issue_item)
      )
    end

    test "returns a fragment containing an empty array for an issue" do
      assert_empty(
        @reviewers_field.elasticsearch_document(@issue_item)
      )
    end
  end

  context "#sort_fragment" do
    test "sorts in ascending order" do
      pull_request_item_pairs = [pull_request_item_pair, pull_request_item_pair, pull_request_item_pair]
      create(:pull_request_review, :approved, pull_request: pull_request_item_pairs[0][:pull_request], user: @org_member)
      create(:pull_request_review, :approved, pull_request: pull_request_item_pairs[1][:pull_request], user: @org_member2)
      pull_request_item_pairs[2][:pull_request].request_review_from(actor: @admin, reviewers: [@team])

      reviewers_names = [@org_member.login, @org_member2.login, @team.name]
      reviewers_names_sorted_asc = reviewers_names.sort

      populate_elasticsearch_index!(pull_request_item_pairs.map { |i| i[:item] })

      unsorted_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
      )
      unsorted_response_values = unsorted_query.execute.results.map do |i|
        i["sort"].first
      end

      refute_equal reviewers_names_sorted_asc, unsorted_response_values, "Expected unsorted results, got sorted results - test may be flaky."
      # Test ascending
      sorted_asc_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @admin,
        query: "",
        sort: [@reviewers_field.sort_fragment(direction: "asc")]
      )
      sorted_response_values = sorted_asc_query.execute.results.map { |i| i["sort"].first }
      assert_equal reviewers_names_sorted_asc, sorted_response_values
    end

    test "sorts in descending order" do
      pull_request_item_pairs = [pull_request_item_pair, pull_request_item_pair, pull_request_item_pair]
      create(:pull_request_review, :approved, pull_request: pull_request_item_pairs[0][:pull_request], user: @org_member)
      create(:pull_request_review, :approved, pull_request: pull_request_item_pairs[1][:pull_request], user: @org_member2)
      pull_request_item_pairs[2][:pull_request].request_review_from(actor: @admin, reviewers: [@team])

      reviewers_names = [@org_member.login, @org_member2.login, @team.name]
      reviewers_names_sorted_desc = reviewers_names.sort.reverse

      populate_elasticsearch_index!(pull_request_item_pairs.map { |i| i[:item] })

      unsorted_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
      )
      unsorted_response_values = unsorted_query.execute.results.map do |i|
        i["sort"].first
      end

      refute_equal reviewers_names_sorted_desc, unsorted_response_values, "Expected unsorted results, got sorted results - test may be flaky."
      # Test descending
      sorted_desc_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @admin,
        query: "",
        sort: [@reviewers_field.sort_fragment(direction: "desc")]
      )
      sorted_response_values = sorted_desc_query.execute.results.map { |i| i["sort"].first }
      assert_equal reviewers_names_sorted_desc, sorted_response_values
    end
  end

  context "#query_fragment" do
    test "returns the expected query fragment hash when searching by login" do
      create(:pull_request_review, :approved, pull_request: @pull_request, user: @org_member)

      expected_query_fragment = {
        bool: {
          should: [
            {
              nested: {
                path: "field_values",
                query: { term: { "field_values.reviewers_value.actor_slug.keyword" => { value: @org_member.display_login, case_insensitive: true } } }
              }
            }
          ],
          minimum_should_match: 1
        }
      }
      context = Search::Memex::Context.new(memex_project: @memex, viewer: @org_member2)
      query_fragment = @reviewers_field.query_fragment(values: [@org_member.display_login], is_negated: false, context:)

      assert_equal expected_query_fragment, query_fragment
    end

    test "returns the expected query fragment hash when searching by @me" do
      create(:pull_request_review, :approved, pull_request: @pull_request, user: @org_member2)

      expected_query_fragment = {
        bool: {
          should: [
            {
              nested: {
                path: "field_values",
                query: { term: { "field_values.reviewers_value.actor_slug.keyword" => { value: @org_member2.display_login, case_insensitive: true } } }
              }
            }
          ],
          minimum_should_match: 1
        }
      }
      context = Search::Memex::Context.new(memex_project: @memex, viewer: @org_member2)
      query_fragment = @reviewers_field.query_fragment(values: ["@me"], is_negated: false, context:)

      assert_equal expected_query_fragment, query_fragment
    end

    test "returns the expected query fragment hash when searching with negated login query" do
      create(:pull_request_review, :approved, pull_request: @pull_request, user: @org_member)

      expected_query_fragment = {
        bool: {
          must_not: [
            {
              nested: {
                path: "field_values",
                query: { term: { "field_values.reviewers_value.actor_slug.keyword" => { value: @org_member.display_login, case_insensitive: true } } }
              }
            }
          ]
        }
      }
      context = Search::Memex::Context.new(memex_project: @memex, viewer: @org_member2)
      query_fragment = @reviewers_field.query_fragment(values: [@org_member.display_login], is_negated: true, context:)

      assert_equal expected_query_fragment, query_fragment
    end
  end

  context "#existence_fragment" do
    test "returns the expected query fragment hash for 'no:reviewer' query" do
      expected_query_fragment = {
        nested: {
          path: "field_values",
          query: {
            exists: {
              field: "field_values.reviewers_value.actor_slug"
            }
          }
        }
      }

      assert_equal expected_query_fragment, @reviewers_field.existence_fragment
    end
  end

  context "#querying" do
    test "queries match correct documents" do
      pull_request_item_pairs = [pull_request_item_pair, pull_request_item_pair, pull_request_item_pair, pull_request_item_pair]
      reviewers = %w(fo-user bar-user amused barry)
      reviewers.each_with_index do |reviewer_login, index|
        reviewer = create(:verified_user, login: reviewer_login)
        create(:pull_request_review, :approved, pull_request: pull_request_item_pairs[index][:pull_request], user: reviewer)
      end

      populate_elasticsearch_index!(pull_request_item_pairs.map { |i| i[:item] })

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @admin,
        query: "reviewers:bar-user"
      )
      response = query.execute
      expected_result_ids = [pull_request_item_pairs[1][:item].id]
      actual_result_ids = response.results.map { |result| result["_source"]["database_id"] }
      assert_same_elements expected_result_ids, actual_result_ids
    end

    test "wildcard queries match correct documents" do
      pull_request_item_pairs = [pull_request_item_pair, pull_request_item_pair, pull_request_item_pair, pull_request_item_pair]
      reviewers = %w(fo-user bar-user amused barry)
      reviewers.each_with_index do |reviewer_login, index|
        reviewer = create(:verified_user, login: reviewer_login)
        create(:pull_request_review, :approved, pull_request: pull_request_item_pairs[index][:pull_request], user: reviewer)
      end

      populate_elasticsearch_index!(pull_request_item_pairs.map { |i| i[:item] })

      test_cases = {
        # We expect that bar* will match the 2 users that start with bar but nothing else
        "reviewers:bar*" => [pull_request_item_pairs[1][:item].id, pull_request_item_pairs[3][:item].id],
        # We expect that this will match the 3 users with "us" somewhere in the login
        "reviewers:*us*" => [pull_request_item_pairs[0][:item].id, pull_request_item_pairs[1][:item].id, pull_request_item_pairs[2][:item].id],
        # We expect that this will match the 2 users that end with "user"
        "reviewers:*user" => [pull_request_item_pairs[0][:item].id, pull_request_item_pairs[1][:item].id],
      }

      test_cases.each do |query_string, expected_result_ids|
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @admin,
          query: query_string
        )
        response = query.execute
        actual_result_ids = response.results.map { |result| result["_source"]["database_id"] }

        assert_same_elements expected_result_ids, actual_result_ids, "Query that failed: #{query_string}"
      end
    end
  end

  def pull_request_item_pair
    pull_request = create(
      :pull_request,
      :disable_disk_access,
      repository: @repo,
      user: @admin,
      head_ref: "ref-#{SecureRandom.hex(6)}"
    )
    item = create(:memex_project_item, content: pull_request, memex_project: @memex)

    {
      item: item,
      pull_request: pull_request
    }
  end
end
