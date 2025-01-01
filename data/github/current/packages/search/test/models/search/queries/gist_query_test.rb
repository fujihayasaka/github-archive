# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesGistQueryTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")

    @create_contents = [
      { name: "hello.rb", value: "def hello; puts 'Hello!'; end" },
    ]

    @defunkt_public_gist = GistHelpers.generate(user: @defunkt,
                                          public: true,
                                          contents: @create_contents,
                                          description: "Test Gist")
    @mojombo_public_gist = GistHelpers.generate(user: @mojombo,
                                          public: true,
                                          contents: @create_contents,
                                          description: "Test Gist")
    @mojombo_secret_gist = GistHelpers.generate(user: @mojombo,
                                          public: false,
                                          contents: @create_contents,
                                          description: "Test Secret Gist")
  end

  setup do
    @query = Search::Queries::GistQuery.new(current_user: @defunkt, page: 1)
    GitHub::Experiment.raise_on_mismatches = false
  end

  context "query params" do
    test "it will only query repositories" do
      assert_equal("gist", @query.query_params[:type])
    end
  end

  context "when building the query" do
    test "empty queries match non-fork public gists" do
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { public: true } },
          { term: { fork: false } },
          { exists: { field: :owner_id } },
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "it creates a function score string query" do
      @query.phrase = "search"
      query = @query.build_query

      assert query.key?(:bool)
      assert query[:bool][:must][:query_string]

      expected = {
        query: "search",
        fields: %w[code.filename^0.1 code.file description],
        default_operator: "AND",
        analyzer: "code_search",
      }
      actual = query[:bool][:must][:query_string]
      assert_equal expected, actual

      expected = { bool: { must: [
        { term: { public: true } },
        { term: { fork: false } },
        { exists: { field: :owner_id } },
      ] } }
      assert_equal expected, query[:bool][:filter]
    end

    test "it queries the specified fields" do
      @query.phrase = "search in:filename"
      query = @query.build_query

      expected = {
        query: "search",
        fields: %w[code.filename^0.1],
        default_operator: "AND",
      }
      actual = query[:bool][:must][:query_string]
      assert_equal expected, actual

      expected = { bool: { must: [
        { term: { public: true } },
        { term: { fork: false } },
        { exists: { field: :owner_id } },
      ] } }
      assert_equal expected, query[:bool][:filter]
    end

    test "it queries the multiple specified fields" do
      @query.phrase = "search in:description,filename"
      query = @query.build_query
      qs = query[:bool][:must][:query_string]
      assert_equal %w[description code.filename^0.1], qs[:fields]

      @query = Search::Queries::GistQuery.new(phrase: "search in:\"description filename\"")
      query = @query.build_query
      qs = query[:bool][:must][:query_string]
      assert_equal %w[description code.filename^0.1], qs[:fields]

      @query = Search::Queries::GistQuery.new(phrase: "search in:description in:filename")
      query = @query.build_query
      qs = query[:bool][:must][:query_string]
      assert_equal %w[description code.filename^0.1], qs[:fields]
    end

    context "with search qualifiers" do
      test "when searching for a certain filename with NO query" do
        @query.phrase = "filename:hello-world.rb"

        expected = { bool: {
          must: {
            bool: { must: { match: { "code.filename": "hello-world.rb" } } },
          },
          filter: {
            bool: { must: [
              { term: { public: true } },
              { term: { fork: false } },
              { exists: { field: :owner_id } },
            ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "when searching for a certain filename with a query" do
        @query.phrase = "search filename:hello-world.rb"

        expected = { bool: {
          must: {
            bool: { must: [
              { query_string:
                {
                  query: "search",
                  fields: %w[code.filename^0.1 code.file description],
                  default_operator: "AND",
                  analyzer: "code_search",
                },
              },
              { match: { "code.filename": "hello-world.rb" } },
            ] },
          },
          filter: {
            bool: { must: [
              { term: { public: true } },
              { term: { fork: false } },
              { exists: { field: :owner_id } },
            ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "when searching for on of many filenames" do
        @query.phrase = "filename:hello-world.rb filename:hello_world.rb"

        expected = { bool: {
          must: {
            bool: {
              should: [
                { match: { "code.filename": "hello-world.rb" } },
                { match: { "code.filename": "hello_world.rb" } },
              ],
              minimum_should_match: 1,
            },
          },
          filter: {
            bool: { must: [
              { term: { public: true } },
              { term: { fork: false } },
              { exists: { field: :owner_id } },
            ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "when excluding a filename" do
        @query.phrase = "-filename:bad.txt"

        expected = { bool: {
          must: {
            bool: {
              must_not: { match: { "code.filename": "bad.txt" } },
            },
          },
          filter: {
            bool: { must: [
              { term: { public: true } },
              { term: { fork: false } },
              { exists: { field: :owner_id } },
            ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "when excluding many filenames" do
        @query.phrase = "-filename:hello-world.rb -filename:hello_world.rb"

        expected = { bool: {
          must: {
            bool: {
              must_not: [
                { match: { "code.filename": "hello-world.rb" } },
                { match: { "code.filename": "hello_world.rb" } },
              ],
            },
          },
          filter: {
            bool: { must: [
              { term: { public: true } },
              { term: { fork: false } },
              { exists: { field: :owner_id } },
            ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "omits the fork filter" do
        @query.phrase = "fork:true"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { public: true } },
            { exists: { field: :owner_id } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a fork filter" do
        @query.phrase = "fork:only"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { public: true } },
            { term: { fork: true } },
            { exists: { field: :owner_id } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a forks filter" do
        @query.phrase = "forks:>100"

        expected = { constant_score: { filter: {
          bool: { must: [
            { range: { forks: { gt: "100" } } },
            { term: { public: true } },
            { term: { fork: false } },
            { exists: { field: :owner_id } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "validates the forks filter" do
        queries = [
          ["forks:>100", true],
          ["forks:true", false],
          ["forks:1..2", true],
          ["forks:3..2", false],
          ["forks:a..b", false],
          ["forks:1..b", false],
        ]
        queries.each do |phrase, valid|
          query = Search::Queries::GistQuery.new(current_user: @defunkt)
          query.phrase = phrase
          assert_equal valid, query.valid_query?, "Expected #{phrase} to be #{"in" unless valid}valid"
        end
      end

      test "generates a stars filter" do
        @query.phrase = "stars:>42"

        expected = { constant_score: { filter: {
          bool: { must: [
            { range: { stars: { gt: "42" } } },
            { term: { public: true } },
            { term: { fork: false } },
            { exists: { field: :owner_id } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a created filter" do
        @query.phrase = "created:>2013-02-01"

        expected = { constant_score: { filter: {
          bool: { must: [
            { range: { created_at: { gt: "2013-02-01||/d" } } },
            { term: { public: true } },
            { term: { fork: false } },
            { exists: { field: :owner_id } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an owner repository filter" do
        query = Search::Queries::GistQuery.new current_user: @mojombo
        query.phrase = "@mojombo"

        expected = { constant_score: { filter: {
          bool: { must: [
            { terms: { gist_id: [@mojombo_secret_gist.id, @mojombo_public_gist.id].sort } },
            { term: { fork: false } },
            { exists: { field: :owner_id } },
          ] },
        } } }
        assert_equal expected, query.build_query
      end

      test "generates a repository filter" do
        @query.phrase = "@mojombo"

        expected = { constant_score: { filter: {
          bool: { must: [
            # Searching another user's Gists excludes secret gists
            { term: { gist_id: @mojombo_public_gist.id } },
            { term: { fork: false } },
            { exists: { field: :owner_id } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end
    end
  end

  context "when building the sort" do
    test "returns nil when the sort is empty and a query is present" do
      @query.query = "foo"
      assert_nil @query.build_sort
    end

    test "returns the default sort when the sort is empty" do
      assert_equal([{ "stars" => "desc" }, "_score"], @query.build_sort)

      @query.phrase = "\"\""
      assert_equal([{ "stars" => "desc" }, "_score"], @query.build_sort)
    end

    test "maps the sort field" do
      @query.sort = %w[stars desc]
      assert_equal([{ "stars" => "desc" }, "_score"], @query.build_sort)
    end

    test "accepts multiple sort fields" do
      @query.sort = %w[forks desc updated desc]
      assert_equal([{ "forks" => "desc" }, { "updated_at" => "desc" }, "_score"], @query.build_sort)
    end
  end

  context "when executing" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @response = {
        "took" => 445, "timed_out" => false, "_shards" => { "total" => 2, "successful" => 2, "failed" => 0 },
        "hits" => { "total" => 596, "max_score" => nil, "hits" => [
          {
            "_index" => "gists",
            "_type" => "gist",
            "_id" => @defunkt_public_gist.id.to_s,
            "_score" => 3.9096773,
            "_source" => { "description" => "truncated gist doc…" },
            "sort" => [0, 3.9096773],
          },
          {
            "_index" => "gists",
            "_type" => "gist",
            "_id" => @mojombo_public_gist.id.to_s,
            "_score" => 3.9096773,
            "_source" => { "description" => "truncated gist doc…" },
            "sort" => [0, 3.9096773],
          },
        ] }
      }

      @index = Elastomer::Index.new("test")
      @response["hits"] = Elastomer::UpgradeShims.shim_search_response_hits(@response["hits"]) if @index.index_running_version_8_plus?
      @index.stubs(:search).returns(@response)
      @index.stubs(:count).returns(Elastomer::UpgradeShims.get_total_hits(@response["hits"]))

      @query.instance_variable_set(:@index, @index)
    end

    test "executes the query" do
      @query.phrase = "test"
      results = @query.execute

      assert_equal @query.page, results.page
      assert_equal @query.per_page, results.per_page
      assert_equal @response["took"], results.time
      assert_equal Elastomer::UpgradeShims.get_total_hits(@response["hits"]), results.total

      first, last = results.results
      assert first.is_a?(Hash)
      assert_equal @defunkt_public_gist, first["_gist"]
      assert_equal @defunkt_public_gist, first["_model"]

      assert last.is_a?(Hash)
      assert_equal @mojombo_public_gist, last["_gist"]
      assert_equal @mojombo_public_gist, last["_model"]
    end

    test "executes the count query" do
      @query.phrase = "test"
      assert_equal Elastomer::UpgradeShims.get_total_hits(@response["hits"]), @query.count
    end

    test "prunes missing repos" do
      @query.phrase = "test"
      @response["hits"]["hits"].first["_id"] = "0"

      assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["gist", 0], queue: "index_high") do
        results = @query.execute
        first = results.results.first

        assert first.is_a?(Hash)
        assert_equal @mojombo_public_gist, first["_gist"]
        assert_equal @mojombo_public_gist, first["_model"]
      end
    end

    if GitHub.spamminess_check_enabled?
      test "prunes spammy results" do
        @query.phrase = "test"
        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { @mojombo.mark_as_spammy }

        assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["gist", @mojombo_public_gist.id], queue: "index_high") do
          results = @query.execute
          first = results.results.first

          assert first.is_a?(Hash)
          assert_equal @defunkt_public_gist, first["_gist"]
          assert_equal @defunkt_public_gist, first["_model"]
        end
      end

      test "prunes when spammy field has been set" do
        @response["hits"]["hits"].each { |h| h.delete("_source") }
        @query.phrase = "test"
        @query.source_fields = false
        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { @mojombo.mark_as_spammy }

        assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["gist", @mojombo_public_gist.id], queue: "index_high") do
          results = @query.execute
          first = results.results.first

          assert first.is_a?(Hash)
          assert_equal @defunkt_public_gist, first["_gist"]
          assert_equal @defunkt_public_gist, first["_model"]
        end
      end
    end
  end
end
