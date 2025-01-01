# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesReleaseQueryTest < GitHub::TestCase
  EXECUTION_TOTAL = 2

  fixtures do
    @user = create :user
    @repo = create :repository, owner: @user, from_example: :repository_test_simple

    @private_repo = create :private_repository, owner: @user, from_example: :repository_test_simple


    @releases = create_list :release, 3, :published, repository: @repo, author: @user
    @releases += create_list(:release, 2, :draft, repository: @repo, author: @user)

    @private_releases = create_list :release, 3, :published, repository: @private_repo, author: @user

    @response = mock_results(@releases)
    @response_private = mock_results(@private_releases)
  end

  context "when creating the query" do
    test "it will only query releases" do
      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo)
      assert_equal({ type: "release" }, query.query_params)
    end
  end

  context "when building the query" do
    test "by default queries match all releases except drafts" do
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { repo_id: @repo.id } },
          { term: { draft: false } },
        ] }
      } } }

      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo)
      assert_equal expected, query.build_query
    end

    test "allows filtering only draft releases for users with write access via qualifier" do
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { repo_id: @repo.id } },
          { term: { draft: true } },
        ] }
      } } }
      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo, phrase: "draft:true", allow_drafts: true)
      assert_equal expected, query.build_query
    end

    test "allows excluding draft releases via qualifier" do
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { repo_id: @repo.id } },
          { term: { draft: false } },
        ] }
      } } }

      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo, phrase: "draft:false")
      assert_equal expected, query.build_query
    end

    test "allows excluding prereleases via qualifier" do
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { repo_id: @repo.id } },
          { term: { prerelease: false } },
        ] }
      } } }

      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo, phrase: "prerelease:false", allow_drafts: true)
      assert_equal expected, query.build_query
    end

    test "normalize removes mutually exclusive values (right-most wins)" do
      normalized_phrase = Search::Queries::ReleaseQuery.stringify(
        Search::Queries::ReleaseQuery.normalize(
        Search::Queries::ReleaseQuery.parse("draft:false draft:true tag:v1 tag:v2")))

      assert_equal "draft:true tag:v2", normalized_phrase
    end

    test "allows filtering by tag name via qualifier" do
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { repo_id: @repo.id } },
          { term: { tag_name: "v2" } },
        ] }
      } } }
      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo, phrase: "tag:v2", allow_drafts: true)
      assert_equal expected, query.build_query
    end

    test "generates a created filter" do
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { repo_id: @repo.id } },
          { range: { created_at: { gt: "2021-10-01||/d" } } },
        ] },
      } } }
      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo, phrase: "created:>2021-10-01", allow_drafts: true)
      assert_equal expected, query.build_query
    end

    test "search by a phrase" do
      expected = { bool: {
        must: { function_score: {
          query: {
            query_string: {
              query: "v1.0.0",
              fields: [:tag_name, :name, :body],
              default_operator: "AND",
            },
          },
          score_mode: "multiply",
        } },
        filter: { bool: { must:
          { term: { repo_id: @repo.id } },
        } }
      } }

      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo, phrase: "v1.0.0", allow_drafts: true)
      assert_equal expected, query.build_query
    end

    test "search by a qualifier and phrase" do
      expected = { bool: {
        must: { function_score: {
          query: {
            query_string: {
              query: "v1.0.0",
              fields: [:tag_name, :name, :body],
              default_operator: "AND",
            },
          },
          score_mode: "multiply",
        } },
        filter: { bool: { must: [
          { term: { repo_id: @repo.id } },
          { term: { draft: true } },
        ] } }
      } }
      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo, phrase: "draft:true v1.0.0", allow_drafts: true)
      assert_equal expected, query.build_query
    end
  end

  context "when building the sort" do
    expected_default_sort = [
      { "draft" => "desc" },
      { "created_day" => "desc" },
      { "version_major" => "desc" },
      { "version_minor" => "desc" },
      { "version_patch" => "desc" },
      { "prerelease" => "asc" },
      { "tag_name.raw" => "desc" },
    ]

    test "uses default sort when the query is empty" do
      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo)
      assert_equal(expected_default_sort, query.build_sort)
    end

    test "maps the sort field" do
      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo)
      query.sort = %w[tag desc]
      assert_equal([{ "tag_name.raw" => "desc" }], query.build_sort)
    end

    test "uses default sort when searching a phrase" do
      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo, phrase: "v1.0.0")
      assert_equal(expected_default_sort, query.build_sort)
    end
  end

  context "when executing" do
    test "executes the query" do
      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo, page: 1, phrase: "any")
      query.instance_variable_set(:@index, stub_index)

      results = query.execute

      assert_equal query.page, results.page
      assert_equal query.per_page, results.per_page
      assert_equal @response["took"], results.time
      assert_equal EXECUTION_TOTAL, results.total

      assert_equal EXECUTION_TOTAL, results.results.size
      result_tags = results.results.map { |h| h["_source"]["tag_name"] }
      expected_tags = @releases.take(EXECUTION_TOTAL).map(&:tag_name)
      assert_equal expected_tags, result_tags
    end

    test "executes the count query" do
      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo, page: 1, phrase: "any")
      query.instance_variable_set(:@index, stub_index)

      assert_equal EXECUTION_TOTAL, query.count
    end

    test "prunes releases from results when not viewable by user" do
      someone = create :user
      query = Search::Queries::ReleaseQuery.new(current_user: someone, repository: @private_repo, page: 1)
      query.instance_variable_set(:@index, stub_index(@response_private))

      results = query.execute
      assert_empty results.models
    end

    test "draft releases are not returned when user has no write access" do
      someone = create :user
      query = Search::Queries::ReleaseQuery.new(current_user: someone, repository: @repo, page: 1, limit: 3)
      query.instance_variable_set(:@index, stub_index)

      results = query.execute
      # we should skip over all drafts and instead return a full page of published releases
      assert results.models.count, 3
      refute results.models.any?(&:draft?)
      assert results.models.all?(&:published?)
    end

    test "limits results by existing releases on queried repository" do
      query = Search::Queries::ReleaseQuery.new(current_user: @private_repo.owner, repository: @private_repo, page: 1)
      query.instance_variable_set(:@index, stub_index(@response_private))

      # All the releases have been deleted since the index was last updated
      @private_releases.map(&:destroy!)

      results = query.execute
      assert_empty results.models
    end
  end

  def stub_index(response = @response)
    index = Elastomer::Index.new("test")
    index.stubs(:search).returns(response)
    index.stubs(:count).returns(EXECUTION_TOTAL)
    index
  end

  def mock_results(releases)
    {
      "took" => 445, "timed_out" => false, "_shards" => { "total" => EXECUTION_TOTAL, "successful" => EXECUTION_TOTAL, "failed" => 0 },
      "hits" => {
        "total" => EXECUTION_TOTAL,
        "max_score" => nil,
        "hits" => releases.take(EXECUTION_TOTAL).map do |release|
          {
            "_index" => "releases",
            "_type" => "release",
            "_id" => release.id.to_s,
            "_source" => { "tag_name" => release.tag_name },
          }
        end
      },
      "aggregations" => {}
    }.freeze
  end

  context "when building the highlight" do
    test "it creates some highlighting" do
      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo)
      assert_equal(
          { type: "plain",
            fields: {
              tag_name: {
                number_of_fragments: 0,
                pre_tags: ["<mark class='hx_keyword-hl'>"],
                post_tags: ["</mark>"],
              },
              name: {
                number_of_fragments: 50,
                fragment_size: 0,
                pre_tags: [""],
                post_tags: [""]
              },
              body: {
                number_of_fragments: 1000,
                fragment_size: 0,
                pre_tags: ["<mark>"],
                post_tags: ["</mark>"],
              },
          } }, query.build_highlight
      )
    end

    test "only if highlighting is enabled" do
      query = Search::Queries::ReleaseQuery.new(current_user: @user, repository: @repo)
      query.phrase = "search"

      doc = query.query_document
      refute doc.key?(:highlight)

      query.highlight = true
      doc = query.query_document
      assert doc.key?(:highlight)
    end
  end
end
