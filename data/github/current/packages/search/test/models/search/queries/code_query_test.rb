# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesCodeQueryTest < GitHub::TestCase

  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")
    @twp     = create(:user, login: "TwP", plan: "medium", email: "twp@example.com")

    @facebox = create(:repository, name: "facebox", owner: @defunkt)
    @grit    = create(:repository, name: "grit", owner: @mojombo)
    @log     = create(:private_repository, name: "log", owner: @twp)
  end

  setup do
    disable_feature_flag(:disable_codesearch)

    @query = Search::Queries::CodeQuery.new(current_user: @defunkt, page: 1)

    example_repo :defunkt_facebox, @facebox
    example_repo :mojombo_grit, @grit
  end

  context "query params" do
    test "it will only query code" do
      assert_equal({ type: "code" }, @query.query_params)
    end

    test "generates routing information" do
      @query.phrase = "search @defunkt @mojombo/grit"
      assert_equal({ type: "code", routing: "#{@grit.id},#{@facebox.id}" }, @query.query_params)
    end

    test "generates no routing information for global queries" do
      query = Search::Queries::CodeQuery.new(current_user: @twp, phrase: "search")

      assert_nil query.routing

      expected = { query: {
        bool: {
          must: { query_string: {
            query: "search",
            fields: %w[file],
            default_operator: "AND",
            analyzer: "code_search",
          } },
          filter: { bool: { must:
            { bool: { should: [
              { term: { public: true } },
              { term: { repo_id: @log.id } },
            ] } },
            must_not: { term: { is_code_search_state_doc: true } },
          } },
        } },
        _source: true,
        from: 0,
        size: 10,
      }
      assert_equal expected, query.query_document
    end

    test "injects :context for metrics tracking" do
      query = Search::Queries::CodeQuery.new(current_user: @twp, phrase: "search")
      assert_equal("raw.global", query.build_query_params[:context])

      query = Search::Queries::CodeQuery.new(current_user: @twp, phrase: "search @mojombo/grit")
      assert_equal("raw.scoped", query.build_query_params[:context])
    end

    test "injects :context for metrics tracking for requests with enterprise installation" do
      query = Search::Queries::CodeQuery.new(current_enterprise_installation: true, phrase: "search")
      assert_equal("enterprise.global", query.build_query_params[:context])

      query = Search::Queries::CodeQuery.new(current_enterprise_installation: true, phrase: "search @mojombo/grit")
      assert_equal("enterprise.scoped", query.build_query_params[:context])
    end
  end

  context "when building the query" do
    test "it defaults to match_all" do
      expected = { constant_score: { filter: {
        bool: { must:
          { term: { public: true } },
          must_not: { term: { is_code_search_state_doc: true } },
        },
      } } }
      assert_equal expected, @query.build_query
    end

    test "it creates a string query" do
      @query.phrase = "search"
      query = @query.build_query

      assert @query.valid_query?, "query should be valid"

      assert query.key?(:bool)

      expected = { query_string: {
        query: "search",
        fields: %w[file],
        default_operator: "AND",
        analyzer: "code_search",
      } }
      assert_equal expected, query[:bool][:must]

      expected = { bool: { must:
        { term: { public: true } },
        must_not: { term: { is_code_search_state_doc: true } },
      }
    }
      assert_equal expected, query[:bool][:filter]
    end

    test "it queries the specified fields" do
      @query.phrase = "search in:path"
      query = @query.build_query

      assert @query.valid_query?, "query should be valid"

      qs = query[:bool][:must][:query_string]
      assert_equal %w[path^0.1 filename^0.1], qs[:fields]
    end

    test "it queries the multiple specified fields" do
      @query.phrase = "search in:file,path"
      query = @query.build_query

      qs = query[:bool][:must][:query_string]
      assert_equal %w[file path^0.1 filename^0.1], qs[:fields]
    end

    test "it queries the filename field" do
      @query.phrase = "servolux filename:gemfile"
      query = @query.build_query

      assert @query.valid_query?, "query should be valid"

      bool = query[:bool][:must][:bool]
      assert bool.has_key?(:must)
      assert !bool.has_key?(:must_not)

      assert_equal 2, bool[:must].length
      assert_equal({ match: { filename: { query: "gemfile", operator: "and" } } }, bool[:must].last)

      assert bool[:must].first.has_key?(:query_string)
    end

    test "it queries _just_ the filename field" do
      @query.phrase = "filename:gemfile"
      query = @query.build_query

      assert @query.valid_query?, "query should be valid"

      bool = query[:bool][:must][:bool]
      assert bool.has_key?(:must)
      assert !bool.has_key?(:must_not)

      assert_equal({ match: { filename: { query: "gemfile", operator: "and" } } }, bool[:must])
    end

    context "with search qualifiers" do
      test "generates a fork filter for fork:only" do
        @query.phrase = "fork:only"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { public: true } },
            { term: { fork: true } },
          ], must_not: { term: { is_code_search_state_doc: true } }, },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a fork filter for fork:false" do
        @query.phrase = "fork:false"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { public: true } },
            { term: { fork: false } },
            ], must_not: { term: { is_code_search_state_doc: true } }, },
          } } }
        assert_equal expected, @query.build_query
      end

      test "generates no fork filter for fork:true" do
        @query.phrase = "fork:true"

        expected = { constant_score: { filter: {
          bool: { must:
            { term: { public: true } },
            must_not: { term: { is_code_search_state_doc: true } },
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "bad values for fork qualifiers behave as fork:false" do
        @query.phrase = "fork:foobarzzz"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { public: true } },
            { term: { fork: false } },
          ],
          must_not: { term: { is_code_search_state_doc: true } },
        },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an extension filter" do
        @query.phrase = "extension:foo extension:.BaR"

        expected = { constant_score: { filter: {
          bool: { must: [
            { terms: { extension: %w[foo bar] } },
            { term: { public: true } },
          ], must_not: { term: { is_code_search_state_doc: true } }, },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a size filter" do
        @query.phrase = "size:>1024"

        expected = { constant_score: { filter: {
          bool: { must: [
            { range: { file_size: { gt: "1024" } } },
            { term: { public: true } },
          ], must_not: { term: { is_code_search_state_doc: true } }, },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a path filter" do
        @query.phrase = "path:lib/foo -path:vendor"

        expected = { constant_score: { filter: {
          bool: {
            must: [
              { term: { public: true } },
              { term: { "path.filter" => "lib/foo" } },
            ],
            must_not: [
              { term: { is_code_search_state_doc: true } },
              { term: { "path.filter" => "vendor" } }
            ]
          },
        } } }
        assert_equal expected, @query.build_query

        @query = Search::Queries::CodeQuery.new(current_user: @defunkt, phrase: "path:/lib/DotJS")

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { public: true } },
            { term: { "path.filter" => "lib/dotjs" } },
          ], must_not: { term: { is_code_search_state_doc: true } } },
        } } }
        assert_equal expected, @query.build_query

        @query = Search::Queries::CodeQuery.new(current_user: @defunkt, phrase: "path:/")

        expected = { constant_score: { filter: {
          bool: {
            must: [
              { term: { public: true } },
              { bool:
                { must_not:
                  { exists: { field: "path.filter" } },
                },
              },
            ], must_not: { term: { is_code_search_state_doc: true } } },
        } } }
        assert_equal expected, @query.build_query

        @query = Search::Queries::CodeQuery.new(current_user: @defunkt, phrase: "-path:/")

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { public: true } },
            { exists: { field: "path.filter" } },
          ], must_not: { term: { is_code_search_state_doc: true } } },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an owner repository filter" do
        @query.phrase = "@defunkt"

        expected = { constant_score: { filter: {
          bool: { must:
            { term: { repo_id: @facebox.id } },
            must_not: { term: { is_code_search_state_doc: true } },
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a repository filter" do
        @query.phrase = "@defunkt @mojombo/grit"

        expected = { constant_score: { filter: {
          bool: { must:
            { terms: { repo_id: [@grit.id, @facebox.id] } },
            must_not: { term: { is_code_search_state_doc: true } },
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a language filter" do
        @query.phrase = "language:ruby"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { language_id: 326 } },
            { term: { public: true } },
          ], must_not: { term: { is_code_search_state_doc: true } }, },
        } } }
        assert_equal expected, @query.build_query
      end
    end

    context "private profile users in phrase" do
      test "filtering by private profile user when viewer is the user" do
        enable_feature_flag(:invalidate_private_profile_searches)
        private_user = create(:user, private_profile: true)
        # Repo for `user:` searches
        create(:repository, owner: private_user)

        # Qualifier
        query = Search::Queries::CodeQuery.new(phrase: "foo user:#{private_user}", current_user: private_user)
        assert_predicate query, :valid_query?

        # No qualifier, just the user login
        query = Search::Queries::CodeQuery.new(phrase: private_user.login, current_user: private_user)
        assert_predicate query, :valid_query?
      end

      test "filtering by private profile user when viewer is not the user" do
        enable_feature_flag(:invalidate_private_profile_searches)
        private_user = create(:user, private_profile: true)
        # Repo for `user:` searches
        create(:repository, owner: private_user)
        viewer = create(:user)

        # Qualifier
        query = Search::Queries::CodeQuery.new(phrase: "foo user:#{private_user}", current_user: viewer)
        refute_predicate query, :valid_query?

        # No qualifier, just the user login
        query = Search::Queries::CodeQuery.new(phrase: private_user.login, current_user: viewer)
        assert_predicate query, :valid_query?
      end
    end
  end

  context "when building the highlight" do
    test "it creates some highlighting" do
      assert_equal(
        { type: "plain",
          encoder: "default",
          pre_tags: [Search::Queries::CodeQuery::PRE_TAG],
          post_tags: [Search::Queries::CodeQuery::POST_TAG],
          fields: {
            file: { number_of_fragments: 2 },
          },
          require_field_match: true,
        }, @query.build_highlight
      )
    end

    test "it only highlights the searched fields" do
      @query.phrase = "search in:path"
      assert_equal(
        { type: "plain",
          encoder: "default",
          pre_tags: [Search::Queries::CodeQuery::PRE_TAG],
          post_tags: [Search::Queries::CodeQuery::POST_TAG],
          fields: {
            path: { number_of_fragments: 0 },
            filename: { number_of_fragments: 0 },
          },
          require_field_match: true,
        }, @query.build_highlight
      )

      @query = Search::Queries::CodeQuery.new phrase: 'search in:"file path"'
      assert_equal(
        { type: "plain",
          encoder: "default",
          pre_tags: [Search::Queries::CodeQuery::PRE_TAG],
          post_tags: [Search::Queries::CodeQuery::POST_TAG],
          fields: {
            path: { number_of_fragments: 0 },
            filename: { number_of_fragments: 0 },
            file: { number_of_fragments: 2 },
          },
          require_field_match: true,
        }, @query.build_highlight
      )
    end

    test "only if highlighting is enabled" do
      @query.phrase = "search"

      doc = @query.query_document
      assert !doc.key?(:highlight)

      @query.highlight = true
      doc = @query.query_document
      assert doc.key?(:highlight)
    end
  end

  context "when building the sort" do
    test "returns nil when the sort is empty" do
      assert_nil @query.build_sort
    end

    test "maps the sort field" do
      @query.sort = %w[indexed desc]
      assert_equal([{ "timestamp" => "desc" }, "_score"], @query.build_sort)
    end
  end

  context "when building the aggregations" do
    test "creates a filterless aggregation" do
      @query.aggregations = true
      @query.phrase = "extension:.rb"

      assert_equal [:language_id], @query.aggregations
      assert_equal({ language_id: { terms: { field: :language_id, size: Search::Query::per_page_default } } }, @query.build_aggregations)
    end

    test "creates a global language filter" do
      @query.aggregations = true
      @query.phrase = "language:ruby"

      assert_equal({ language_id: { terms: { field: :language_id, size: Search::Query::per_page_default } } }, @query.build_aggregations)

      expected = { constant_score: { filter: {
        bool: { must:
          { term: { public: true } },
          must_not: { term: { is_code_search_state_doc: true } },
        },
      } } }
      assert_equal expected, @query.build_query

      assert_equal({ bool: { must: { term: { language_id: 326 } } } }, @query.build_filter)
    end
  end

  context "when created with a language" do
    test "overrides user supplied language filters" do
      query = Search::Queries::CodeQuery.new(phrase: "search language:ruby -language:perl", language: Linguist::Language["Python"])
      query = query.build_query

      expected = { bool: { must: [
        { term: { language_id: 303 } },
        { term: { public: true } },
      ], must_not: { term: { is_code_search_state_doc: true } },
      } }
      assert_equal expected, query[:bool][:filter]
    end
  end

  context "when created with a repository id" do
    test "overrides the normal repository filter" do
      query = Search::Queries::CodeQuery.new(phrase: "search @defunkt -@mojombo", repo_id: @grit.id)
      query = query.build_query

      expected = { bool: { must:
        { term: { repo_id: @grit.id } },
        must_not: { term: { is_code_search_state_doc: true } },
      } }
      assert_equal expected, query[:bool][:filter]
    end
  end

  context "when executing" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @response = {
        "took" => 445, "timed_out" => false, "_shards" => { "total" => 2, "successful" => 2, "failed" => 0 },
        "hits" => { "total" => 596, "max_score" => nil, "hits" => [
          {
            "_index" => "issues",
            "_type" => "code",
            "_id" => "11508855",
            "_score" => 3.9096773,
            "_source" => { "repo_id" => @facebox.id.to_s, "public" => true, "created_at" => "2013-02-28T08:54:29-08:00", "updated_at" => "2013-02-28T09:10:52-08:00", "language_id" => 272 },
            "highlight" => {
              "comments.body" => ["Can you be more clear? And anyways, I have just started the GTK2 theme. Will notify you when it is done. Now you'll find thousands of things if you <em>search</em>.\n"],
            },
            "sort" => [1362070469000, 3.9096773],
          }, {
            "_index" => "issues",
            "_type" => "code",
            "_id" => "11506778",
            "_score" => 2.5102885,
            "_source" => { "repo_id" => @grit.id.to_s, "public" => true, "created_at" => "2013-02-28T08:08:55-08:00", "updated_at" => "2013-02-28T09:01:22-08:00", "language_id" => 303 },
            "highlight" => {
              "comments.body" => ["The max gap is the number of past frames, the method uses in its <em>search</em> for the closest segmentation result. It was introduced in order to bridge &quot;empty images&quot; that sometimes happen to be acquired"],
            },
            "sort" => [1362067735000, 2.5102885],
          }]
        },
        "aggregations" => {
          "language_id" => {
            "doc_count_error_upper_bound" => 0,
            "sum_other_doc_count" => 25,
            "buckets" => [
              { "key" => 183, "doc_count" => 159 },
              { "key" => 303, "doc_count" => 103 },
              { "key" => 181, "doc_count" => 80 },
              { "key" => 272, "doc_count" => 62 },
              { "key" => 326, "doc_count" => 42 },
              { "key" => 41, "doc_count" => 20 },
              { "key" => 43, "doc_count" => 19 },
              { "key" => 42, "doc_count" => 11 },
              { "key" => 282, "doc_count" => 9 },
              { "key" => 257, "doc_count" => 5 },
            ],
          },
        }
      }

      @index = Elastomer::Index.new("test")
      @response["hits"] = Elastomer::UpgradeShims.shim_search_response_hits(@response["hits"]) if @index.index_running_version_8_plus?
      @index.stubs(:search).returns(@response)
      @index.stubs(:count).returns(Elastomer::UpgradeShims.get_total_hits(@response["hits"]))

      @query.instance_variable_set(:@index, @index)
    end

    test "executes the query" do
      @query.phrase = "search @mojombo/grit"
      @facebox.stubs(:code_is_searchable?).returns(true)
      @grit.stubs(:code_is_searchable?).returns(true)

      results = @query.execute

      assert_equal @query.page, results.page
      assert_equal @query.per_page, results.per_page
      assert_equal @response["took"], results.time
      assert_equal Elastomer::UpgradeShims.get_total_hits(@response["hits"]), results.total

      first, last = results.results
      assert first.is_a?(Hash)
      assert_equal @facebox, first["_model"]

      assert last.is_a?(Hash)
      assert_equal @grit, last["_model"]
    end

    test "executes the count query" do
      @query.phrase = "search"
      assert_equal Elastomer::UpgradeShims.get_total_hits(@response["hits"]), @query.count
    end

    if GitHub.use_elastomer_code_search?
      test "prunes missing repos and their code from legacy code search cluster" do
        @query.phrase = "search @mojombo/grit"
        @response["hits"]["hits"].first["_source"]["repo_id"] = 0

        assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["code", 0], queue: "index_high") do
          assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["repository", 0], queue: "index_high") do
            results = @query.execute
            first = results.results.first

            assert first.is_a?(Hash)
            assert_equal @grit, first["_model"]
          end
        end
      end
    else
      test "prunes missing repos but not code from legacy code search cluster" do
        @query.phrase = "search @mojombo/grit"
        @response["hits"]["hits"].first["_source"]["repo_id"] = 0

        code_job_matcher = ->(job_args) do
          job_args[:job] == RemoveFromSearchIndexJob &&
            job_args[:args][0] == "code" &&
            job_args[:args][1] == 0
        end
        assert_no_enqueued_jobs(only: code_job_matcher) do
          assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["repository", 0], queue: "index_high") do
            results = @query.execute
            first = results.results.first

            assert first.is_a?(Hash)
            assert_equal @grit, first["_model"]
          end
        end
      end
    end

    if GitHub.spamminess_check_enabled?
      if GitHub.use_elastomer_code_search?
        test "prunes spammy results from legacy code search clusters" do
          @query.phrase = "search"
          perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
            @mojombo.mark_as_spammy
          end

          assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["code",  @grit.id], queue: "index_high") do
            results = @query.execute
            first = results.results.first

            assert first.is_a?(Hash)
            assert_equal @facebox, first["_model"]
          end
        end
      else
        test "does not prune spammy results from legacy code search search" do
          @query.phrase = "search"
          perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
            @mojombo.mark_as_spammy
          end

          code_job_matcher = ->(job_args) do
            job_args[:job] == RemoveFromSearchIndexJob &&
              job_args[:args][0] == "code" &&
              job_args[:args][1] == @grit.id
          end
          assert_no_enqueued_jobs(only: code_job_matcher) do
            results = @query.execute
            first = results.results.first

            assert first.is_a?(Hash)
            assert_equal @facebox, first["_model"]
          end
        end
      end

      if GitHub.use_elastomer_code_search?
        test "prunes from legacy code search cluster when source fields is set to false" do
          @query.phrase = "search"
          @query.source_fields = false
          perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
            @mojombo.mark_as_spammy
          end

          assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["code",  @grit.id], queue: "index_high") do
            results = @query.execute
            assert_equal 1, results.length
          end
        end
      else
        test "does not prune from legacy code search cluster even if source fields is set to false" do
          @query.phrase = "search"
          @query.source_fields = false
          perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
            @mojombo.mark_as_spammy
          end

          code_job_matcher = ->(job_args) do
            job_args[:job] == RemoveFromSearchIndexJob &&
              job_args[:args][0] == "code" &&
              job_args[:args][1] == @grit.id
          end
          assert_no_enqueued_jobs(only: code_job_matcher) do
            results = @query.execute
            assert_equal 1, results.length
          end
        end
      end
    end
  end

  test "very long query strings are invalid" do
    query = Search::Queries::CodeQuery.new current_user: @defunkt, phrase:
      "searching for some very long query string will take a long time and produce to many SpanTerm queries in Luceneand make Elasticsearch unhappy and that makes Tim unhappy"

    refute query.valid_query?, "the query string should be too long"
    assert_equal "The search is longer than 128 characters.", query.invalid_reason
  end

  if GitHub.enterprise?
    test "code search is always enabled" do
      feature = FlipperFeature.find_by(name: "disable_codesearch") || create(:flipper_feature, name: "disable_codesearch")
      user    = create(:user)
      feature.enable user

      query = Search::Queries::CodeQuery.new(current_user: user, phrase: "bacon")
      assert query.valid_query?
    end
  else
    test "query is marked as invalid for disabled users" do
      feature = FlipperFeature.find_by(name: "disable_codesearch") || create(:flipper_feature, name: "disable_codesearch")
      user    = create(:user)
      feature.enable user

      query = Search::Queries::CodeQuery.new(current_user: user, phrase: "bacon")
      refute query.valid_query?
      assert_equal "Code search is not available at this time.", query.invalid_reason
    end

    test "global code search is disabled for anonymous requests" do
      query = Search::Queries::CodeQuery.new(current_user: nil, phrase: "bacon")
      refute query.valid_query?
      assert_equal "Must include at least one user, organization, or repository", query.invalid_reason
    end

    test "global code search is allowed for anonymous requests with enterprise installation" do
      org = create :organization, admin: @defunkt
      inst = create(:enterprise_installation, owner: org)
      query = Search::Queries::CodeQuery.new(current_user: nil, current_enterprise_installation: inst, phrase: "bacon")
      assert query.valid_query?
    end
  end
end
