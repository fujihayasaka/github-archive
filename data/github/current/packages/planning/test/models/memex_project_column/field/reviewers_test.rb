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
      head_ref: "ref-#{SecureRandom.hex(6)}",
      head_sha: "head-sha-#{SecureRandom.hex(6)}",
    )

    @org_member = create(:verified_user, login: "alpha")
    @org_member2 = create(:verified_user, login: "beta")
    @org_member3 = create(:verified_user, login: "charlie")
    @team = create(:team, organization: @org, privacy: :closed, name: "delta")
    @team.add_repository(@repo, :push)
    @team.add_member(@admin, adder: @admin)
    @org.add_member(@org_member)
    @org.add_member(@org_member2)
    @review_request = create(:review_request, pull_request: @pull_request, reviewer: @org_member)
    @pull_request_review = create(:pull_request_review, :approved, pull_request: @pull_request, user: @org_member)

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

    test "does not query tables excessively" do
      assert_query_count_per_table({
        review_requests: 1,
        pull_request_reviews: 1,
        # One query from prefilling ReviewRequest#reviewer association, one from prefilling PullRequestReview#user association
        users: 2,
      }) do
        @reviewers_field.preload_elasticsearch_document_data([@item])
      end
    end

    test "fetches all required columns from pull_request_reviews" do
      # Generate Elasticsearch document without any cached associations
      expected_documents = assert_query_count_per_table({ pull_request_reviews: 2 }) do
        @reviewers_field.elasticsearch_document(@item).map(&:to_hash)
      end

      uncached_item = MemexProjectItem.find(@item.id)

      assert_query_count_per_table({ pull_request_reviews: 1 }) do
        @reviewers_field.preload_elasticsearch_document_data([uncached_item])
      end

      # Ensure we're using the preloaded data from preload_elasticsearch_document_data
      actual_documents = assert_query_count_per_table({ pull_request_reviews: 0 }) do
        @reviewers_field.elasticsearch_document(uncached_item).map(&:to_hash)
      end

      assert_equal expected_documents, actual_documents
    end

    test "does not raise exception if content no longer exists" do
      refute_nil @item.content, "Expected item to have content"

      @item.content.destroy!
      @item.reload

      assert_nil @item.content, "Expected item to no longer have content"

      assert_nothing_raised do
        @reviewers_field.preload_elasticsearch_document_data([@item])
      end
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

    test "excludes team review requests that have been fulfilled by a user reviewer" do
      team_review_request = create(:review_request, pull_request: @pull_request, reviewer: @team)
      actor_ids = @reviewers_field.elasticsearch_document(@item).map { _1.to_hash[:actor_id] }
      # First validate that the team is included until the request is fulfilled
      assert_includes actor_ids, team_review_request.reviewer_id

      team_review_request.pull_request_reviews.create!(state: :approved, user: @admin, pull_request: @pull_request, head_sha: @pull_request.head_sha)
      actor_ids = @reviewers_field.elasticsearch_document(@item.reload).map { _1.to_hash[:actor_id] }
      # The team should no longer be included...
      refute_includes actor_ids, team_review_request.reviewer_id
      # ...but the user who fulfilled the review on behalf of the team should be included
      assert_includes actor_ids, @admin.id
    end

    test "excludes deferred and dismissed review requests" do
      deferred_request = create(:review_request, :deferred, pull_request: @pull_request, reviewer: @org_member2)
      dismissed_request = create(:review_request, :dismissed, pull_request: @pull_request, reviewer: @org_member3)
      actor_ids = @reviewers_field.elasticsearch_document(@item).map { _1.to_hash[:actor_id] }
      refute_includes actor_ids, deferred_request.reviewer_id, "Expected deferred request to be excluded"
      refute_includes actor_ids, dismissed_request.reviewer_id, "Expected dismissed request to be excluded"
    end

    test "excludes review requests with missing reviewers" do
      request_without_reviewer = create(:review_request, pull_request: @pull_request, reviewer: @org_member2)
      @org_member2.delete
      actor_ids = @reviewers_field.elasticsearch_document(@item).map { _1.to_hash[:actor_id] }
      assert actor_ids.none? { _1.nil? }
      refute_includes actor_ids, request_without_reviewer.reviewer_id, "Expected request without reviewer to be excluded"
    end

    test "excludes pending reviews" do
      pending_review = create(:pull_request_review, :pending, pull_request: @pull_request, user: @org_member2)
      reviewers = @reviewers_field.elasticsearch_document(@item)
      refute_includes reviewers.map { _1.to_hash[:actor_id] }, pending_review.user_id
    end

    test "includes unique combination of review requests and reviews" do
      # Create overlapping review request and review for same user
      create(:review_request, pull_request: @pull_request, reviewer: @org_member2)
      create(:pull_request_review, :approved, pull_request: @pull_request, user: @org_member2)

      reviewers = @reviewers_field.elasticsearch_document(@item)

      org_member2_entries = reviewers.select { _1.to_hash[:actor_id] == @org_member2.id }
      assert_equal 1, org_member2_entries.length
    end

    test "properly differentiates between Team and User types" do
      create(:review_request, pull_request: @pull_request, reviewer: @team)
      create(:pull_request_review, :approved, pull_request: @pull_request, user: @org_member3)

      reviewers = @reviewers_field.elasticsearch_document(@item)

      team_reviewer = reviewers.find { _1.to_hash[:actor_type] == "Team" }
      user_reviewer = reviewers.find { _1.to_hash[:actor_id] == @org_member3.id }

      assert_equal @team.id, team_reviewer.to_hash[:actor_id]
      assert_equal @team.name, team_reviewer.to_hash[:actor_slug]
      assert_equal "Team", team_reviewer.to_hash[:actor_type]

      assert_equal @org_member3.id, user_reviewer.to_hash[:actor_id]
      assert_equal @org_member3.display_login, user_reviewer.to_hash[:actor_slug]
      assert_equal "User", user_reviewer.to_hash[:actor_type]
    end

    test "sorts reviewers by actor_id and actor_type" do
      # Create mixed reviewers to test sorting
      create(:review_request, pull_request: @pull_request, reviewer: @team)
      create(:pull_request_review, :approved, pull_request: @pull_request, user: @org_member3)

      reviewers = @reviewers_field.elasticsearch_document(@item)

      actual_sort_keys = reviewers.map { [_1.to_hash[:actor_id], _1.to_hash[:actor_type]] }
      sorted_sort_keys = actual_sort_keys.sort

      assert_equal sorted_sort_keys, actual_sort_keys
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
        sort: [@reviewers_field.sort_fragment(direction: "asc")],
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
        sort: [@reviewers_field.sort_fragment(direction: "desc")],
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
