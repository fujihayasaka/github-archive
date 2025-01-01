# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesUserQueryTest < GitHub::TestCase
  include GitHub::LoggerHelper
  COMMON_NAME = "common name"

  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")

    unless GitHub.single_business_environment?
      @emu_business = create :business, :enterprise_managed
      create :business_saml_provider, business: @emu_business
      @emu_user = create :emu, business: @emu_business
      @emu_user2 = create :emu, business: @emu_business

      @non_emu_user = create(:user, login: "user-non-emu")
      @non_emu_business = create(:business)
      @non_emu_business.add_user_accounts([@non_emu_user.id])

      @emu_user.profile.name = COMMON_NAME
      @emu_user.profile.save

      @emu_user2.profile.name = COMMON_NAME
      @emu_user2.profile.save

      create :profile, user: @non_emu_user, name: COMMON_NAME
    end
  end

  setup do
    setup_search
    @query = Search::Queries::UserQuery.new(current_user: @defunkt, page: 1)
    GitHub::Experiment.raise_on_mismatches = false
  end

  teardown { teardown_search }

  context "query params" do
    test "it will only query users" do
      assert_equal({ type: "user" }, @query.query_params)
    end
  end

  context "when building the query" do
    test "defaults" do
      assert_equal(
        { constant_score: { filter: { bool: { must_not: { exists: { field: :business_id } } } } } },
        @query.build_query,
      )
    end

    test "it creates a function score string query" do
      @query.phrase = "search"
      query = @query.build_query

      assert query[:bool][:must][:function_score][:query].key?(:query_string)

      qs = query[:bool][:must][:function_score][:query][:query_string]
      keys = [:query, :fields, :default_operator, :analyzer]
      keys.each { |key| assert qs.key?(key), "has key #{key.inspect}" }
      assert_equal keys.length, qs.keys.length
      assert_equal "search", qs[:query]
    end

    test "it queries the specified fields" do
      @query.phrase = "search in:login"
      query = @query.build_query

      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[login^10 login.ngram^0.8], qs[:fields]
    end

    test "it queries multiple fields" do
      @query.phrase = "search in:email,name"
      query = @query.build_query

      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[email email.plain name^1.2], qs[:fields]
    end

    context "with search qualifiers" do
      test "generates a location filter" do
        @query.phrase = 'location:"Boulder, CO"'
        assert_equal(
          { constant_score: { filter: { bool: {
            must: {
              query_string: {
                query:            "boulder, co",
                default_field:    :location,
                default_operator: :AND,
              },
            },
            must_not: {
              exists: { field: :business_id }
            }
          } } } }, @query.build_query
        )
      end

      test "generates a sponsorable filter" do
        @query.phrase = "is:sponsorable"
        expected = {
          constant_score: {
            filter: { bool: {
              must: {
                term: { sponsorable: true }
              },
              must_not: {
                exists: { field: :business_id }
              }
            } }
          }
        }
        assert_equal expected, @query.build_query
      end

      test "generates a name filter" do
        @query.phrase = 'fullname:"Chris Wanstrath"'
        assert_equal(
          { constant_score: { filter: { bool: {
            must: {
              query_string: {
                query:            "chris wanstrath",
                default_field:    :name,
                default_operator: :AND,
              },
            },
            must_not: {
              exists: { field: :business_id }
            }
          } } } }, @query.build_query
        )
      end

      test "generates a followers filter" do
        @query.phrase = "followers:>100"
        assert_equal(
          { constant_score: { filter: { bool: { must:             { range: { followers: { gt: "100" } } },
          must_not: { exists: { field: :business_id } } } } } }, @query.build_query
        )
      end

      test "generates a repos filter" do
        @query.phrase = "repos:>42"
        assert_equal(
          { constant_score: { filter: { bool: { must:             { range: { repos: { gt: "42" } } },
          must_not: { exists: { field: :business_id } } } } } }, @query.build_query
        )
      end

      test "generates a created filter" do
        @query.phrase = "created:>2013-02-01"
        assert_equal(
          { constant_score: { filter: { bool: { must:             { range: { created_at: { gt: "2013-02-01||/d" } } },
          must_not: { exists: { field: :business_id } } } } } }, @query.build_query
        )
      end

      test "generates a language filter" do
        @query.phrase = "language:ruby"
        assert_equal(
          { constant_score: { filter: { bool: { must:             { term: { language_id: 326 } },
          must_not: { exists: { field: :business_id } } } } } }, @query.build_query
        )
      end

      test "generates a language filter from lang:" do
        @query.phrase = "lang:ruby"
        assert_equal(
          { constant_score: { filter: { bool: { must:             { term: { language_id: 326 } },
          must_not: { exists: { field: :business_id } } } } } }, @query.build_query
        )
      end

      test "handles lang: and language: together" do
        @query.phrase = "lang:ruby language:javascript"
        assert_equal(
          { constant_score: { filter: { bool: { must:             { terms: { language_id: [183, 326] } },
          must_not: { exists: { field: :business_id } } } } } }, @query.build_query
        )
      end

      test "handles lang: and language: with same language" do
        @query.phrase = "lang:ruby language:ruby"
        assert_equal(
          { constant_score: { filter: { bool: { must:             { term: { language_id: 326 } },
          must_not: { exists: { field: :business_id } } } } } }, @query.build_query
        )
      end

      test "generates a type filter" do
        query = Search::Queries::UserQuery.new phrase: "type:user"
        assert_equal(
          { constant_score: { filter: { bool: { must:             { term: { organization: false } },
          must_not: { exists: { field: :business_id } } } } } }, query.build_query
        )

        query = Search::Queries::UserQuery.new phrase: "type:org"
        assert_equal(
          { constant_score: { filter: { bool: { must:             { term: { organization: true } },
          must_not: { exists: { field: :business_id } } } } } }, query.build_query
        )

        query = Search::Queries::UserQuery.new phrase: "type:organization"
        assert_equal(
          { constant_score: { filter: { bool: { must:             { term: { organization: true } },
          must_not: { exists: { field: :business_id } } } } } }, query.build_query
        )

        query = Search::Queries::UserQuery.new phrase: "type:foo"
        assert_equal(
          { constant_score: { filter: { bool: { must_not: { exists: { field: :business_id } } } } } },
          @query.build_query,
        )
      end

      test "uses a bool query with a filter when search terms are present" do
        @query.phrase = "tim followers:>10 -language:ruby"
        query = @query.build_query

        assert query.key?(:bool)
        assert_equal(
          { bool: {
            must: { range: { followers: { gt: "10" } } },
            must_not: [
              { term: { language_id: 326 } },
              { exists: { field: :business_id } }
            ]
          } },
          query[:bool][:filter],
        )
      end

      test "uses a bool query with a filter when search terms are present with lang:" do
        @query.phrase = "tim followers:>10 -lang:ruby"
        query = @query.build_query

        assert query.key?(:bool)
        assert_equal(
          { bool: {
            must: { range: { followers: { gt: "10" } } },
            must_not: [
              { term: { language_id: 326 } },
              { exists: { field: :business_id } }
            ]
          } },
          query[:bool][:filter],
        )
      end

      test "builds a user_id filter" do
        query = Search::Queries::UserQuery.new phrase: "user:defunkt"
        assert_equal(
          { constant_score: { filter: { bool: { must:             { term: { user_id: @defunkt.id } },
          must_not: { exists: { field: :business_id } } } } } }, query.build_query
        )

        query = Search::Queries::UserQuery.new phrase: "org:mojombo"
        assert_equal(
          { constant_score: { filter: { bool: { must:             { term: { user_id: @mojombo.id } },
          must_not: { exists: { field: :business_id } } } } } }, query.build_query
        )
      end
    end
  end

  unless GitHub.single_business_environment?
    context "EMU senario" do
      test "non-emu user search query doc" do
        query = Search::Queries::UserQuery.new(current_user: @defunkt, page: 1)
        query.phrase = "user-"

        expected_query =
          {
            bool: {
              must: {
                function_score: {
                  query: {
                      query_string: {
                        query: "user\\-",
                        fields: [
                            "login^10",
                            "login.ngram^0.8",
                            "email",
                            "email.plain",
                            "name^1.2",
                            "profile_bio"
                        ],
                        default_operator: "AND",
                        analyzer: "lowercase"
                      }
                  },
                  score_mode: "multiply",
                  functions: [
                      {
                        field_value_factor: {
                            field: "rank",
                            missing: 1
                        }
                      }
                  ]
                }
              },
              filter: {
                bool: {
                  must_not: {
                    exists: {
                      field: :business_id
                    }
                  }
                }
              }
            }
          }

        assert_equal expected_query, query.build_query
      end

      test "emu user search query doc" do
        query = Search::Queries::UserQuery.new(current_user: @emu_user, page: 1)
        query.phrase = "user-"

        expected_query =
          {
            bool: {
              must: {
                function_score: {
                  query: {
                      query_string: {
                        query: "user\\-",
                        fields: [
                            "login^10",
                            "login.ngram^0.8",
                            "email",
                            "email.plain",
                            "name^1.2",
                            "profile_bio"
                        ],
                        default_operator: "AND",
                        analyzer: "lowercase"
                      }
                  },
                  score_mode: "multiply",
                  functions: [
                      {
                        field_value_factor: {
                            field: "rank",
                            missing: 1
                        }
                      }
                  ]
                }
              },
              filter: {
                bool: {
                  must: {
                    term: {
                      business_id: @emu_business.id
                    }
                  }
                }
              }
            }
        }
        assert_equal expected_query, query.build_query
      end

      test "Non-EMU user cannot discover EMU user" do
        make_searchable(@emu_user, @emu_user2, @non_emu_user)

        query = Search::Queries::UserQuery.new(current_user: @defunkt, phrase: "user")
        results = query.execute.results.map { |h| h["_model"] }
        assert_same_elements [@non_emu_user], results
      end

      test "EMU user cannot discover non-EMU user" do
        make_searchable(@emu_user, @emu_user2, @non_emu_user, @defunkt)

        query = Search::Queries::UserQuery.new(current_user: @emu_user, phrase: "user")
        results = query.execute.results.map { |h| h["_model"] }
        assert_same_elements [@emu_user, @emu_user2], results
      end

      test "EMU user pruned from search result for non-EMU user" do
        make_searchable(@emu_user, @emu_user2, @non_emu_user, @defunkt)

        query = Search::Queries::UserQuery.new(current_user: @defunkt, phrase: "user:#{@emu_user.login}")
        results = query.execute.results.map { |h| h["_model"] }
        assert_empty results

        query = Search::Queries::UserQuery.new(current_user: @defunkt, phrase: "fullname:#{@emu_user.profile_name}")
        results = query.execute.results.map { |h| h["_model"] }
        refute_includes results, @emu_user
        refute_includes results, @emu_user2

        query = Search::Queries::UserQuery.new(current_user: @defunkt, phrase: "fullname:\"#{@emu_user.profile_name}\"")
        results = query.execute.results.map { |h| h["_model"] }
        refute_includes results, @emu_user
        refute_includes results, @emu_user2
      end

      test "Non-EMU user pruned from search result for EMU user" do
        make_searchable(@emu_user, @emu_user2, @non_emu_user, @defunkt)

        query = Search::Queries::UserQuery.new(current_user: @emu_user, phrase: "user:#{@non_emu_user.login}")
        results = query.execute.results.map { |h| h["_model"] }
        assert_empty results

        query = Search::Queries::UserQuery.new(current_user: @emu_user, phrase: "fullname:#{@non_emu_user.profile_name}")
        results = query.execute.results.map { |h| h["_model"] }
        refute_includes results, @non_emu_user

        query = Search::Queries::UserQuery.new(current_user: @emu_user, phrase: "fullname:\"#{@non_emu_user.profile_name}\"")
        results = query.execute.results.map { |h| h["_model"] }
        refute_includes results, @non_emu_user
      end

      test "EMU user pruned from search result for EMU user in a different business" do
        other_emu = create :emu
        other_emu.profile.name = COMMON_NAME
        other_emu.profile.save

        refute_equal @emu_user.enterprise_managed_business.id, other_emu.enterprise_managed_business.id

        make_searchable(@emu_user, @emu_user2, @non_emu_user, @defunkt, other_emu)

        query = Search::Queries::UserQuery.new(current_user: @emu_user, phrase: "user:#{other_emu.login}")
        results = query.execute.results.map { |h| h["_model"] }
        assert_empty results

        query = Search::Queries::UserQuery.new(current_user: @emu_user, phrase: "fullname:#{other_emu.profile_name}")
        results = query.execute.results.map { |h| h["_model"] }
        refute_includes results, other_emu

        query = Search::Queries::UserQuery.new(current_user: @emu_user, phrase: "fullname:\"#{other_emu.profile_name}\"")
        results = query.execute.results.map { |h| h["_model"] }
        refute_includes results, other_emu
      end

      test "EMU can search other EMUs from same business" do
        make_searchable(@emu_user, @emu_user2, @non_emu_user, @defunkt)

        query = Search::Queries::UserQuery.new(current_user: @emu_user, phrase: "user:#{@emu_user2.login}")
        results = query.execute.results.map { |h| h["_model"] }
        assert_same_elements [@emu_user2], results

        query = Search::Queries::UserQuery.new(current_user: @emu_user, phrase: "fullname:#{@emu_user2.profile_name}")
        results = query.execute.results.map { |h| h["_model"] }
        assert_same_elements [@emu_user, @emu_user2], results

        query = Search::Queries::UserQuery.new(current_user: @emu_user, phrase: "fullname:\"#{@emu_user2.profile_name}\"")
        results = query.execute.results.map { |h| h["_model"] }
        assert_same_elements [@emu_user, @emu_user2], results
      end

      test "Non-EMUs can search other non-EMUs" do
        make_searchable(@emu_user, @emu_user2, @non_emu_user, @defunkt)

        query = Search::Queries::UserQuery.new(current_user: @defunkt, phrase: "user:#{@non_emu_user.login}")
        results = query.execute.results.map { |h| h["_model"] }
        assert_same_elements [@non_emu_user], results

        query = Search::Queries::UserQuery.new(current_user: @defunkt, phrase: "fullname:#{@non_emu_user.profile_name}")
        results = query.execute.results.map { |h| h["_model"] }
        assert_same_elements [@non_emu_user], results

        query = Search::Queries::UserQuery.new(current_user: @defunkt, phrase: "fullname:\"#{@non_emu_user.profile_name}\"")
        results = query.execute.results.map { |h| h["_model"] }
        assert_same_elements [@non_emu_user], results
      end

      test "ensure that log is showing when pruning happens" do
        expected_log_data = {
          "code.namespace" => "Search::Queries::UserQuery",
          "code.function" => "prune_results",
          "gh.business.exist" => "false"
        }

        assert_logged(**expected_log_data) do
          make_searchable(@emu_user, @emu_user2, @non_emu_user, @defunkt)

          Search::Queries::UserQuery.any_instance.stubs(:prune_mismatch?).returns(true)
          query = Search::Queries::UserQuery.new(current_user: @defunkt, phrase: "user:#{@non_emu_user.login}")
          results = query.execute.results.map { |h| h["_model"] }
        end
      end
    end

    context "#enterprise_id" do
      test "returns nil when not enterprise managed user context" do
        query = Search::Queries::UserQuery.new(current_user: @defunkt, phrase: "user:#{@non_emu_user.login}")
        refute query.enterprise_id

        query = Search::Queries::UserQuery.new(phrase: "user:#{@non_emu_user.login}", business: @non_emu_business)
        refute query.enterprise_id

        query = Search::Queries::UserQuery.new(phrase: "user:#{@non_emu_user.login}")
        refute query.enterprise_id
      end

      test "returns busines_id when context is enterprise managed" do
        query = Search::Queries::UserQuery.new(current_user: @emu_user, phrase: "test")
        assert_equal @emu_business.id, query.enterprise_id

        query = Search::Queries::UserQuery.new(phrase: "test", business: @emu_business)
        assert_equal @emu_business.id, query.enterprise_id
      end
    end
  end

  context "when building the highlight" do
    test "it creates some highlighting" do
      assert_equal(
          { encoder: :html,
            require_field_match: true,
            fields: {
              "login.ngram" => { number_of_fragments: 0 },
              :login        => { number_of_fragments: 0 },
              :name         => { number_of_fragments: 0 },
              "email.plain" => { number_of_fragments: 0 },
              :email        => { number_of_fragments: 0 },
              :profile_bio  => { number_of_fragments: 0 },
            },
            type: "plain"
          }, @query.build_highlight
      )
    end

    test "it only highlights the searched fields" do
      @query.phrase = "search in:login"
      assert_equal(
          { encoder: :html,
            require_field_match: true,
            fields: {
              "login.ngram" => { number_of_fragments: 0 },
              :login        => { number_of_fragments: 0 },
            },
            type: "plain"
          }, @query.build_highlight
      )

      @query = Search::Queries::UserQuery.new phrase: "search in:name,email"
      assert_equal(
          { encoder: :html,
            require_field_match: true,
            fields: {
              :name         => { number_of_fragments: 0 },
              "email.plain" => { number_of_fragments: 0 },
              :email        => { number_of_fragments: 0 },
            },
            type: "plain"
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
    test "returns nil when the sort is empty and a query is present" do
      @query.query = "foo"
      assert_nil @query.build_sort
    end

    test "returns the default sort when the sort is empty" do
      assert_equal([{ "followers" => "desc" }, "_score"], @query.build_sort)

      @query.phrase = '""'
      assert_equal([{ "followers" => "desc" }, "_score"], @query.build_sort)
    end

    test "maps the sort field" do
      @query.sort = %w[joined desc]
      assert_equal([{ "created_at" => "desc" }, "_score"], @query.build_sort)
    end

    test "accepts multiple sort fields" do
      @query.sort = %w[joined desc repositories desc]
      assert_equal([{ "created_at" => "desc" }, { "repos" => "desc" }, "_score"], @query.build_sort)
    end
  end

  context "when building the aggregations" do
    test "creates a filterless aggregation" do
      @query.aggregations = true
      @query.phrase = "repos:42"

      assert_equal [:language_id], @query.aggregations
      assert_equal({ language_id: { terms: { field: :language_id, size: Search::Query::per_page_default } } }, @query.build_aggregations)
    end

    test "creates a global language filter" do
      @query.aggregations = true
      @query.phrase = "language:ruby followers:42"

      assert_equal({ language_id: { terms: { field: :language_id, size: Search::Query::per_page_default } } }, @query.build_aggregations)

      assert_equal(
          { constant_score: { filter: { bool: { must:             { term: { followers: "42" } },
          must_not: { exists: { field: :business_id } } } } } }, @query.build_query
      )

      assert_equal({ bool: { must: { term: { language_id: 326 } } } }, @query.build_filter)
    end

    test "creates a global language filter with lang:" do
      @query.aggregations = true
      @query.phrase = "lang:ruby followers:42"

      assert_equal({ language_id: { terms: { field: :language_id, size: Search::Query::per_page_default } } }, @query.build_aggregations)

      assert_equal(
          { constant_score: { filter: { bool: { must:             { term: { followers: "42" } },
          must_not: { exists: { field: :business_id } } } } } }, @query.build_query
      )

      assert_equal({ bool: { must: { term: { language_id: 326 } } } }, @query.build_filter)
    end
  end

  context "when created with a language" do
    test "overrides user supplied language filters" do
      query = Search::Queries::UserQuery.new(phrase: "search language:ruby -language:perl", language: Linguist::Language["Python"])
      h = query.build_query

      assert h.key?(:bool)
      assert_equal(
          { bool: { must: { term: { language_id: 303 } }, must_not: { exists: { field: :business_id } } } },
          h[:bool][:filter],
      )
    end

    test "overrides user supplied lang: filters" do
      query = Search::Queries::UserQuery.new(phrase: "search lang:ruby -lang:perl", language: Linguist::Language["Python"])
      h = query.build_query

      assert h.key?(:bool)
      assert_equal(
          { bool: { must: { term: { language_id: 303 } }, must_not: { exists: { field: :business_id } } } },
          h[:bool][:filter],
      )
    end
  end

  context "when executing" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @response = {
        "took" => 445, "timed_out" => false, "_shards" => { "total" => 2, "successful" => 2, "failed" => 0 },
        "hits" => { "total" => 596, "max_score" => nil, "hits" => [
          {
            "_index" => "users",
            "_type" => "user",
            "_id" => @defunkt.id.to_s,
            "_score" => 3.9096773,
            "_source" => { "login" => "defunkt", "name" => "Chris Wanstrath" },
            "highlight" => { "name" => ["Chris Wanstrath"] },
            "sort" => [1362070469000, 3.9096773],
          }, {
            "_index" => "users",
            "_type" => "user",
            "_id" => @mojombo.id.to_s,
            "_score" => 2.5102885,
            "_source" => { "login" => "mojombo", "name" => "Tom Preston-Werner" },
            "highlight" => { "login" => ["mojombo"] },
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
      @query.phrase = "search"
      results = @query.execute

      assert_equal @query.page, results.page
      assert_equal @query.per_page, results.per_page
      assert_equal @response["took"], results.time
      assert_equal Elastomer::UpgradeShims.get_total_hits(@response["hits"]), results.total

      first, last = results.results
      assert first.is_a?(Hash)
      assert_equal @defunkt, first["_model"]

      assert last.is_a?(Hash)
      assert_equal @mojombo, last["_model"]
    end

    test "executes the count query" do
      @query.phrase = "search"
      assert_equal Elastomer::UpgradeShims.get_total_hits(@response["hits"]), @query.count
    end

    if GitHub.spamminess_check_enabled?
      test "prunes spammy results" do
        @query.phrase = "search"
        @mojombo.update!(spammy: true)

        results = @query.execute
        first = results.results.first

        assert_enqueued_jobs 1, only: RemoveFromSearchIndexJob, queue: :index_high
        assert first.is_a?(Hash)
        assert_equal @defunkt, first["_model"]
      end

      test "prunes when spammy field has been set" do
        @query.phrase = "search"
        @query.source_fields = false
        @mojombo.update!(spammy: true)

        results = @query.execute
        first = results.results.first

        assert_enqueued_jobs 1, only: RemoveFromSearchIndexJob, queue: :index_high
        assert first.is_a?(Hash)
        assert_equal @defunkt, first["_model"]
      end
    end

    test "prunes missing repos" do
      @query.phrase = "search"
      @response["hits"]["hits"].first["_id"] = "0"

      results = @query.execute
      first = results.results.first

      assert_enqueued_jobs 1, only: RemoveFromSearchIndexJob, queue: :index_high
      assert first.is_a?(Hash)
      assert_equal @mojombo, first["_model"]
    end

    test "prunes mannequins" do
      mannequin = create(:mannequin)

      response = {
        "took" => 445, "timed_out" => false, "_shards" => { "total" => 2, "successful" => 2, "failed" => 0 },
        "hits" => { "total" => 596, "max_score" => nil, "hits" => [
          {
            "_index" => "users",
            "_type" => "user",
            "_id" => @defunkt.id.to_s,
            "_score" => 3.9096773,
            "_source" => { "login" => "defunkt", "name" => "Chris Wanstrath" },
            "highlight" => { "name" => ["Chris Wanstrath"] },
            "sort" => [1362070469000, 3.9096773],
          }, {
            "_index" => "users",
            "_type" => "user",
            "_id" => mannequin.id.to_s,
            "_score" => 1.0,
            "_source" => { "login" => "#{mannequin.login}", "name" => nil },
            "highlight" => { "login" => ["#{mannequin.login}"] },
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

      index = Elastomer::Index.new("test")
      index.stubs(:search).returns(response)
      index.stubs(:count).returns(response["hits"]["total"])

      @query.instance_variable_set(:@index, index)
      @query.phrase = "search"
      @query.source_fields = false

      results = @query.execute.results
      first = results.first

      assert_enqueued_jobs 1, only: RemoveFromSearchIndexJob, queue: :index_high
      assert_equal 1, results.length
      assert first.is_a?(Hash)
      assert_equal @defunkt, first["_model"]
    end
  end

  context "valid query" do
    test "empty phrase query returns not valid query" do
      query = Search::Queries::UserQuery.new(current_user: @user, phrase: " ")
      refute_predicate query, :valid_query?
    end

    test "phrase query returns valid query" do
      query = Search::Queries::UserQuery.new(current_user: @user, phrase: "test")
      assert_predicate query, :valid_query?
    end
  end
end
