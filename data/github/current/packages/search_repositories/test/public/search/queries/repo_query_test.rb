# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesRepoQueryTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")
    @facebox = create(:repository, name: "facebox", owner: @defunkt)
    @grit    = create(:repository, name: "grit", owner: @mojombo)

    @avocado = create(:organization, name: "avocado", login: "avocado", admin: @defunkt)
    @ripen   = create(:repository, name: "ripen", owner: @avocado)

    @acme = create :business_plus_org, login: "acme"
    business = create :business, organizations: [@acme]

    @coyote = create :user
    @acme.add_member @coyote

    @acme_repo = create :private_repository, owner: @acme
    @acme_repo.add_member @coyote
  end

  setup do
    @query = Search::Queries::RepoQuery.new(current_user: @defunkt, page: 1, cap_filter: cap_authorizing_filter)

    example_repo :defunkt_facebox, @facebox
    example_repo :mojombo_grit, @grit
  end

  context "query params" do
    test "it will only query repositories" do
      assert_equal({ type: "repository" }, @query.query_params)
    end
  end

  context "when building the query" do
    test "empty queries match non-fork public repos" do
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { fork: false } },
          { term: { public: true } },
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "allows inclusion of fork public repos via option" do
      expected = { constant_score: { filter: {
        bool: { must:
          { term: { public: true } },
        },
      } } }

      query = Search::Queries::RepoQuery.new(current_user: @defunkt, include_forks: true)
      assert_equal expected, query.build_query
    end

    test "downcases visibility values" do
      @query.phrase = "visibility:Private"

      expected = { constant_score: { filter: {
        bool: {
          must: [{ term: { visibility: "private" } },
            { term: { fork: false } },
            { term: { public: true } }], # Inserted by security check
        },
      } } }

      assert_equal expected, @query.build_query
    end

    test "downcases comma-separated visibility values" do
      @query.phrase = "visibility:Private,Internal"

      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [{ term: { fork: false } }, { term: { public: true } }],
              should: { terms: { visibility: %w[internal private] } },
              minimum_should_match: 1,
            },
          },
        },
      }

      assert_equal expected, @query.build_query
    end

    test "it creates a function score string query" do
      @query.phrase = "search"
      query = @query.build_query

      assert query.key?(:bool)
      assert query[:bool][:must][:function_score][:query][:query_string]

      expected = {
        query: "search",
        fields: %w[name^1.2 name.camel name.ngram^0.8 description applied_topics],
        default_operator: "AND",
      }
      actual = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal expected, actual

      expected = { bool: { must: [
        { term: { fork: false } },
        { term: { public: true } },
      ] } }
      assert_equal expected, query[:bool][:filter]
    end

    test "it queries the specified fields" do
      @query.phrase = "search in:name"
      query = @query.build_query

      expected = {
        query: "search",
        fields: %w[name^2 name.camel name.ngram^0.8 name_with_owner],
        default_operator: "AND",
      }
      actual = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal expected, actual

      expected = { bool: { must: [
        { term: { fork: false } },
        { term: { public: true } },
      ] } }
      assert_equal expected, query[:bool][:filter]
    end

    test "it queries the specified topic field" do
      @query.phrase = "search in:topics"
      query = @query.build_query

      expected = {
        query: "search",
        fields: %w[applied_topics],
        default_operator: "AND",
      }
      actual = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal expected, actual

      expected = { bool: { must: [
        { term: { fork: false } },
        { term: { public: true } },
      ] } }
      assert_equal expected, query[:bool][:filter]
    end

    test "it finds private repositories via 'is'" do
      @query.phrase = "is:private"
      expected = {
        constant_score: {
          filter: {
            bool: {
              # User defunkt has no private repo access, so no accessible repos
              # list here. Security check inserts public: true.
              must: [{ term: { visibility: "private" } },
                     { term: { fork: false } },
                     { term: { public: true } }],
            },
          },
        },
      }
      assert_equal expected, @query.build_query
    end

    test "it finds private repositories via 'visibility'" do
      @query.phrase = "visibility:private"
      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [{ term: { visibility: "private" } },
                     { term: { fork: false } },
                     { term: { public: true } }], # Inserted by security check
            },
          },
        },
      }
      assert_equal expected, @query.build_query
    end

    test "it finds internal repositories via 'is'" do
      @query.phrase = "is:internal"
      expected = {
        constant_score: {
          filter: {
            bool: {
              # User defunkt has no private repo access, so no accessible repos
              # list here. Security check inserts public: true.
              must: [{ term: { visibility: "internal" } },
                     { term: { fork: false } },
                     { term: { public: true } }],
            },
          },
        },
      }
      assert_equal expected, @query.build_query
    end

    test "it finds both public and internal repositories via 'is' with multiple expressions" do
      @query.phrase = "is:internal is:public"
      expected = {
        constant_score: {
          filter: {
            bool: {
              # User defunkt has no private repo access, so no accessible repos
              # list here. Security check inserts public: true.
              must: [{ terms: { visibility: %w[internal public] } },
                     { term: { fork: false } },
                     { term: { public: true } }],
            },
          },
        },
      }
      assert_equal expected, @query.build_query
    end

    test "visibility term supports comma syntax for OR" do
      @query.phrase = "visibility:internal,public"
      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [{ term: { fork: false } }, { term: { public: true } }],
              should: { terms: { visibility: %w[internal public] } },
              minimum_should_match: 1,
            },
          },
        },
      }
      assert_equal expected, @query.build_query
    end

    test "multi-key visibility term search resolves to an OR because repos can't have multiple visibility states" do
      @query.phrase = "visibility:internal visibility:private"
      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [
                { terms: { visibility: %w[internal private] } },
                { term: { fork: false } },
                { term: { public: true } }],
            },
          },
        },
      }
      assert_equal expected, @query.build_query
    end

    test "multi-key visibility term combined with commas resolves to a single OR search" do
      @query.phrase = "visibility:internal,public visibility:private"
      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [{ term: { visibility: "private" } },
                     { term: { fork: false } },
                     { term: { public: true } }],
              should: { terms: { visibility: %w[internal public] } },
              minimum_should_match: 1,
            },
          },
        },
      }
      assert_equal expected, @query.build_query
    end

    test "it finds both internal and private repositories via 'is' with multiple expressions" do
      @query.phrase = "is:internal is:private"
      expected = {
        constant_score: {
          filter: {
            bool: {
              # User defunkt has no private repo access, so no accessible repos
              # list here. Security check inserts public: true.
              must: [{ terms: { visibility: %w[internal private] } },
                { term: { fork: false } },
                { term: { public: true } }],
            },
          },
        },
      }
      assert_equal expected, @query.build_query
    end

    test "it finds all private, public and internal repositories via 'is' with multiple expressions" do
      @query.phrase = "is:private is:public is:internal"
      expected = {
        constant_score: {
          filter: {
            bool: {
              # User defunkt has no private repo access, so no accessible repos
              # list here. Security check inserts public: true.
              must: [{ terms: { visibility: %w[private public internal] } },
                { term: { fork: false } },
                { term: { public: true } }],
            },
          },
        },
      }
      assert_equal expected, @query.build_query
    end

    test "it does not include private repo IDs for anonymous user" do
      query = Search::Queries::RepoQuery.new(current_user: nil)
      query.phrase = "is:private"
      expected = {
        constant_score: {
          filter: {
            bool: {
              # Anonymous user has no private repos, so no accessible repos list
              # here. Security check inserts public: true.
              must: [{ term: { visibility: "private" } },
                     { term: { fork: false } },
                     { term: { public: true } }],
            },
          },
        },
      }
      assert_equal expected, query.build_query
    end

    test "it searches only accessible private repos with is:private" do
      private_repo1 = create(:private_repository, owner: @defunkt)

      private_repo2 = create(:private_repository)
      private_repo2.add_member @defunkt

      @query.phrase = "is:private"

      actual = @query.build_query

      assert_equal [:constant_score], actual.keys
      assert_equal [:filter], actual[:constant_score].keys
      assert_equal [:bool], actual[:constant_score][:filter].keys
      assert_equal [:must], actual[:constant_score][:filter][:bool].keys

      actual_must = actual[:constant_score][:filter][:bool][:must]
      assert_equal 3, actual_must.size
      assert_includes actual_must, { term: { visibility: "private" } }
      assert_includes actual_must, { term: { fork: false } }

      actual_must_bool = actual_must.detect { |hash| hash.keys == [:bool] }[:bool]
      assert_equal [:should], actual_must_bool.keys

      actual_should = actual_must_bool[:should]
      assert_equal 2, actual_should.size

      actual_should_terms = actual_should.detect { |hash| hash.keys == [:terms] }[:terms]
      assert_equal 1, actual_should_terms.size
      assert_same_elements [private_repo1.id, private_repo2.id], actual_should_terms[:repo_id]
    end

    test "generates a filter for the presence of a funding file" do
      @query.phrase = "has:funding-file"
      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [
                { term: { fork: false } },
                { term: { public: true } },
                { term: { has_funding_file: true } },
              ],
            },
          },
        },
      }
      assert_equal expected, @query.build_query
    end

    test "generates a sponsorable filter" do
      @query.phrase = "is:sponsorable"
      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [
                { term: { fork: false } },
                { term: { sponsorable: true } },
                { term: { public: true } },
              ],
            },
          },
        },
      }
      assert_equal expected, @query.build_query
    end

    test "it finds public repositories via 'is'" do
      @query.phrase = "is:public"
      expected = {
        constant_score: {
          filter: {
            bool: {
              # Repo security check inserts second public: true.
              must: [{ term: { visibility: "public" } },
                     { term: { fork: false } },
                     { term: { public: true } }],
            },
          },
        },
      }
      assert_equal expected, @query.build_query
    end

    test "it doesn't crash with negated non-repo 'is'" do
      @query.phrase = "-is:locked"
      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [{ term: { fork: false } },
                     { term: { public: true } }],
            },
          },
        },
      }
      assert_equal expected, @query.build_query
    end

    test "it queries the multiple specified fields" do
      @query.phrase = "search in:readme,description"
      query = @query.build_query
      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[readme description], qs[:fields]

      @query = Search::Queries::RepoQuery.new(phrase: 'search in:"name readme"')
      query = @query.build_query
      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[name^2 name.camel name.ngram^0.8 name_with_owner readme], qs[:fields]

      @query = Search::Queries::RepoQuery.new(phrase: "search in:name in:description")
      query = @query.build_query
      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[name^2 name.camel name.ngram^0.8 name_with_owner description], qs[:fields]

      @query = Search::Queries::RepoQuery.new(phrase: "search in:name in:topics")
      query = @query.build_query
      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[name^2 name.camel name.ngram^0.8 name_with_owner applied_topics], qs[:fields]

      @query = Search::Queries::RepoQuery.new(phrase: "search in:description in:topics")
      query = @query.build_query
      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[description applied_topics], qs[:fields]
    end

    test "do not quote a single word" do
      @query.query = "one"
      assert_equal "one", @query.escaped_query
    end

    test "quote words separately" do
      @query.query = "one two three"
      assert_equal '"one" "two" "three"', @query.escaped_query

      @query.query = 'one "two cars"'
      assert_equal '"one" "two cars"', @query.escaped_query

      @query.query = 'one "two cars" "three blue trucks" four'
      assert_equal '"one" "two cars" "three blue trucks" "four"', @query.escaped_query
    end

    test "do not quote numbers" do
      @query.query = "123"
      assert_equal "123", @query.escaped_query

      @query.query = "123 456"
      assert_equal "123 456", @query.escaped_query

      @query.query = "123 text 456"
      assert_equal '123 "text" 456', @query.escaped_query

      @query.query = '123 "my quoted text" 456 text 789'
      assert_equal '123 "my quoted text" 456 "text" 789', @query.escaped_query
    end

    test "do not quote words if AND, OR, NOT are present" do
      phrases = [
        "one AND two three",
        "one two OR three",
        "one AND two OR three",
        "hello NOT world"
      ]

      phrases.each do |phrase|
        @query.query = phrase
        assert_equal phrase, @query.escaped_query
      end
    end

    test "it queries the full name with owner field when '/' is present in the query" do
      @query.phrase = "TwP/servolux"
      query = @query.build_query
      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[name^1.2 name.camel name.ngram^0.8 description applied_topics
                      name_with_owner], qs[:fields]

      # TwP is not a valid user, so no function_score is added for exact match
      assert_equal 1, query[:bool][:must][:function_score][:functions].size
    end

    test "it boosts score of name with owner when '/' is present in the query" do
      @query.phrase = "mojombo/the_repo"
      query = @query.build_query
      functions = query[:bool][:must][:function_score][:functions]
      assert_equal 2, functions.size
      assert_equal functions[0], { field_value_factor: { field: "rank", missing: 1 } }
      assert_equal functions[1][:weight], 20
      assert_equal functions[1][:filter][:bool][:must], [{ term: { owner_id: @mojombo.id } }, { match: { name: "the_repo" } }]
    end

    test "it boosts score of repo name when 'org:' is present" do
      @query.phrase = "the_repo org:mojombo"
      query = @query.build_query
      functions = query[:bool][:must][:function_score][:functions]
      assert_equal 2, functions.size
      assert_equal functions[0], { field_value_factor: { field: "rank", missing: 1 } }
      assert_equal functions[1][:weight], 20
      assert_equal functions[1][:filter][:bool][:must], [{ term: { owner_id: @mojombo.id } }, { match: { name: "the_repo" } }]
    end

    test "it boosts score of repo name when 'user:' is present" do
      @query.phrase = "the_repo user:mojombo"
      query = @query.build_query
      functions = query[:bool][:must][:function_score][:functions]
      assert_equal 2, functions.size
      assert_equal functions[0], { field_value_factor: { field: "rank", missing: 1 } }
      assert_equal functions[1][:weight], 20
      assert_equal functions[1][:filter][:bool][:must], [{ term: { owner_id: @mojombo.id } }, { match: { name: "the_repo" } }]
    end

    test "it boosts score of repo name when 'owner:' is present" do
      @query.phrase = "the_repo owner:mojombo"
      query = @query.build_query
      functions = query[:bool][:must][:function_score][:functions]
      assert_equal 2, functions.size
      assert_equal functions[0], { field_value_factor: { field: "rank", missing: 1 } }
      assert_equal functions[1][:weight], 20
      assert_equal functions[1][:filter][:bool][:must], [{ term: { owner_id: @mojombo.id } }, { match: { name: "the_repo" } }]
    end

    test "it doesn't boost score when '/' is not an exact name with owner" do
      @query.phrase = "mojombo/the_repo boo"
      # We don't want a {match: {name: "the_repo boo"}} because it would match both "the_repo" and "boo"
      assert_equal 1, @query.build_query[:bool][:must][:function_score][:functions].size

      @query.phrase = "mojombo/the_repo in:name"
      # Modifiers are supported
      assert_equal 2, @query.build_query[:bool][:must][:function_score][:functions].size
    end

    test "it doesn't boost score when org: if repo name has whitespaces" do
      # Same if written with org: cualifier
      @query.phrase = "the_repo boo org:mojombo"
      assert_equal 1, @query.build_query[:bool][:must][:function_score][:functions].size
    end

    context "with search qualifiers" do
      test "generates an archived:false filter" do
        @query.phrase = "archived:false"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { archived: false } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an archived:true filter" do
        @query.phrase = "archived:true"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { archived: true } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "omits the fork filter" do
        @query.phrase = "fork:true"

        expected = { constant_score: { filter: {
          bool: { must:
            { term: { public: true } },
          },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a mirror filter" do
        @query.phrase = "mirror:true"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { mirror: true } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      [true, false].each do |binary_fork_filter|
        test "generates a fork filter (binary_fork_filter: #{binary_fork_filter})" do
          query = Search::Queries::RepoQuery.new(current_user: @defunkt, binary_fork_filter: binary_fork_filter)
          query.phrase = "fork:only"

          expected = { constant_score: { filter: {
            bool: { must: [
              { term: { fork: true } },
              { term: { public: true } },
            ] },
          } } }
          assert_equal expected, query.build_query
        end
      end

      test "allows binary fork filter via option" do
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: true } },
            { term: { public: true } },
          ] },
        } } }

        query = Search::Queries::RepoQuery.new(current_user: @defunkt, binary_fork_filter: true)
        # On binary mode, fork:true means only forks, instead of show all forks and sources
        query.phrase = "fork:true"
        assert_equal expected, query.build_query
      end

      test "generates a user filter" do
        @query.phrase = "user:defunkt"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { repo_id: @facebox.id } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a user filter from org:" do
        @query.phrase = "org:defunkt"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { repo_id: @facebox.id } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an owner filter from org: for an admin" do
        query = Search::Queries::RepoQuery.new(current_user: @defunkt, page: 1, cap_filter: cap_authorizing_filter)
        query.phrase = "org:avocado"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { owner_id: @avocado.id } },
          ] },
        } } }
        assert_equal expected, query.build_query
      end

      test "generates an owner filter from org: for a business member" do
        query = Search::Queries::RepoQuery.new(current_user: @coyote, cap_filter: cap_authorizing_filter, experiment_owner_id_and_repo_id: true)
        query.phrase = "org:acme"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { owner_id: @acme.id } },
            { bool: { should: [
              { term: { repo_id: @acme_repo.id } },
              { terms: { visibility: %w[public internal] } },
            ] } },
          ] },
        } } }
        assert_equal expected, query.build_query
      end

      test "excludes public & internal repos if user query limits to private" do
        query = Search::Queries::RepoQuery.new(current_user: @coyote, cap_filter: cap_authorizing_filter, experiment_owner_id_and_repo_id: true)
        query.phrase = "org:acme visibility:private"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { owner_id: @acme.id } },
            { term: { repo_id: @acme_repo.id } },
          ] },
        } } }
        assert_equal expected, query.build_query
      end

      test "excludes public & private repos if user query limits to internal" do
        query = Search::Queries::RepoQuery.new(current_user: @coyote, cap_filter: cap_authorizing_filter, experiment_owner_id_and_repo_id: true)
        query.phrase = "org:acme visibility:internal"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { owner_id: @acme.id } },
            { term: { visibility: "internal" } },
          ] },
        } } }
        assert_equal expected, query.build_query
      end

      test "excludes internal & private repos if user query limits to public" do
        query = Search::Queries::RepoQuery.new(current_user: @coyote, cap_filter: cap_authorizing_filter, experiment_owner_id_and_repo_id: true)
        query.phrase = "org:acme visibility:public"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { owner_id: @acme.id } },
            { term: { visibility: "public" } },
          ] },
        } } }
        assert_equal expected, query.build_query
      end

      test "excludes public repos if user query limits to internal & private" do
        query = Search::Queries::RepoQuery.new(current_user: @coyote, cap_filter: cap_authorizing_filter, experiment_owner_id_and_repo_id: true)
        query.phrase = "org:acme visibility:internal,private"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { owner_id: @acme.id } },
            { bool: { should: [
              { term: { repo_id: @acme_repo.id } },
              { term: { visibility: "internal" } },
            ] } },
          ] },
        } } }
        assert_equal expected, query.build_query
      end

      test "includes internal & private repos if user query limits to non-public" do
        query = Search::Queries::RepoQuery.new(current_user: @coyote, cap_filter: cap_authorizing_filter, experiment_owner_id_and_repo_id: true)
        query.phrase = "org:acme -visibility:public"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { owner_id: @acme.id } },
            { bool: { should: [
              { term: { repo_id: @acme_repo.id } },
              { terms: { visibility: %w[public internal] } },
            ] } },
          ], must_not: { term: { visibility: "public" } } },
        } } }
        assert_equal expected, query.build_query
      end

      test "generates an owner filter from org: for a non-member" do
        non_member = create :user
        query = Search::Queries::RepoQuery.new(current_user: non_member, cap_filter: cap_authorizing_filter, experiment_owner_id_and_repo_id: true)
        query.phrase = "org:avocado"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { owner_id: @avocado.id } },
            { term: { visibility: "public" } },
          ] },
        } } }
        assert_equal expected, query.build_query
      end

      context "skip_permission_check" do
        test "generates an owner filter from org: if skip_permission_check" do
          query = Search::Queries::RepoQuery.new(
            current_user: nil,
            skip_permission_check: true,
            phrase: "org:avocado"
          )

          expected = { constant_score: { filter: {
            bool: { must: [
              { term: { fork: false } },
              { term: { owner_id: @avocado.id } },
            ] },
          } } }

          assert_equal expected, query.build_query
          assert query.valid_query?
        end

        test "generates an owner filter with custom properties if skip_permission_check" do
          query = Search::Queries::RepoQuery.new(
            current_user: nil,
            skip_permission_check: true,
            phrase: "org:avocado props.Color:Red"
          )

          expected = { constant_score: { filter: {
            bool: { must: [
              { term: { "custom_property_values.keyword" => "Color:red" } },
              { term: { fork: false } },
              { term: { owner_id: @avocado.id } },
            ] },
          } } }

          assert_equal expected, query.build_query
        end

        test "generates a repo_id filter for limit_to_repo_ids without checking permissions" do
          private_org_repo = create(:private_repository, owner: @avocado)
          non_member_user = create :user

          query = Search::Queries::RepoQuery.new(
            current_user: non_member_user,
            skip_permission_check: true,
            limit_to_repo_ids: [@ripen.id, private_org_repo.id],
            phrase: "org:avocado"
          )

          expected = { constant_score: { filter: {
            bool: { must: [
              { term: { fork: false } },
              { terms: { repo_id: [@ripen.id, private_org_repo.id] } },
            ] },
          } } }

          assert_equal expected, query.build_query
        end

        test "ignores the cap_filter" do
          query = Search::Queries::RepoQuery.new(
            current_user: @defunkt,
            cap_filter: cap_unauthorizing_filter(@avocado),
            skip_permission_check: true,
            phrase: "org:avocado"
          )

          expected = { constant_score: { filter: {
            bool: { must: [
              { term: { fork: false } },
              { term: { owner_id: @avocado.id } },
            ] },
          } } }

          assert_equal expected, query.build_query
        end
      end

      test "generates a user filter from owner:" do
        @query.phrase = "owner:defunkt"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { repo_id: @facebox.id } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a forks filter" do
        @query.phrase = "forks:>100"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { range: { forks: { gt: "100" } } },
            { term: { public: true } },
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
          query = Search::Queries::RepoQuery.new(current_user: @defunkt)
          query.phrase = phrase
          assert_equal valid, query.valid_query?, "Expected #{phrase} to be #{"in" unless valid}valid"
        end
      end

      test "generates a size filter" do
        @query.phrase = "size:>1024"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { range: { size: { gt: "1024" } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a stars filter" do
        @query.phrase = "stars:>42"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { range: { followers: { gt: "42" } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a followers filter" do
        @query.phrase = "followers:<1000"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { range: { followers: { lt: "1000" } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a created filter" do
        @query.phrase = "created:>2013-02-01"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { range: { created_at: { gt: "2013-02-01||/d" } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a pushed filter" do
        @query.phrase = "pushed:<2013-02-01"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { range: { pushed_at: { lt: "2013-02-01||/d" } } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates an owner repository filter" do
        @query.phrase = "@defunkt"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { repo_id: @facebox.id } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a repository filter" do
        @query.phrase = "@defunkt @mojombo/grit"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { terms: { repo_id: [@grit.id, @facebox.id] } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a language filter" do
        @query.phrase = "language:ruby"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { language_id: 326 } },
            { term: { fork: false } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a language filter from lang:" do
        @query.phrase = "lang:ruby"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { language_id: 326 } },
            { term: { fork: false } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "handles lang: and language: together" do
        @query.phrase = "lang:ruby language:javascript"

        expected = { constant_score: { filter: {
          bool: { must: [
            { terms: { language_id: [183, 326] } },
            { term: { fork: false } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "handles OR comma-syntax in lang: into a should filter" do
        @query.phrase = "lang:ruby,go"

        expected = { constant_score: { filter: { bool: {
          must: [
            { term: { fork: false } },
            { term: { public: true } },
          ],
          should: { terms: { language_id: [132, 326] } },
          minimum_should_match: 1,
        } } } }
        assert_equal expected, @query.build_query
      end

      test "handles OR comma-syntax in mixed lang: and language: into a should filter" do
        @query.phrase = "lang:ruby,go language:go,javascript"

        expected = { constant_score: { filter: {
          bool: { must: [
            { bool: { must: [
              { bool: { should: { terms: { language_id: [132, 183] } } } },
              { bool: { should: { terms: { language_id: [132, 326] } } } },
            ] } },
            { term: { fork: false } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "handles lang: and language: with same language" do
        @query.phrase = "lang:ruby language:ruby"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { language_id: 326 } },
            { term: { fork: false } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end

      test "generates a license filter" do
        @query.phrase = "license:mit"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { license_id: 13 } }, # mit
            { term: { fork: false } },
            { term: { public: true } },
          ] },
        } } }

        assert_equal expected, @query.build_query
      end

      test "generates a license filter for a license family" do
        @query.phrase = "license:gpl"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  {
                    terms: {
                      license_id: [
                        8, # GPL 2.0
                        9,  # GPL 3.0
                      ],
                    },
                  },
                  { term: { fork: false } },
                  { term: { public: true } },
                ],
              },
            },
          },
        }

        assert_equal expected, @query.build_query
      end

      test "generates a license filter for comma-separated licenses" do
        @query.phrase = "license:mit,gpl"

        expected = { constant_score: { filter: { bool: {
          must: [
            { terms: { license_id: [8, 9, 13] } },
            { term: { fork: false } },
            { term: { public: true } },
          ],
        } } } }
        assert_equal expected, @query.build_query
      end

      test "generates a license filter for multiple licenses" do
        @query.phrase = "license:mit license:gpl"

        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  {
                    terms: {
                      license_id: [
                        13, # MIT
                        8,  # GPL 2.0
                        9,   # GPL 3.0
                      ],
                    },
                  },
                  { term: { fork: false } },
                  { term: { public: true } },
                ],
              },
            },
          },
        }

        assert_equal expected, @query.build_query
      end

      test "validates license qualifier values" do
        @query.phrase = "license:not-a-real-license"

        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { fork: false } },
            { term: { public: true } },
          ] },
        } } }

        assert_equal expected, @query.build_query
        refute @query.valid_query?
        assert_equal "An invalid license was specified.", @query.invalid_reason
      end
    end

    context "Topics" do
      test "searches by applied topics only" do
        @query.phrase = "topic:lumberjack"
        expected = {
          bool: {
            must: {
              bool: {
                must: [
                  nested: {
                    path: "ranked_hashtags",
                    query: {
                      function_score: {
                        query: {
                          match: { "ranked_hashtags.applied" => "lumberjack" },
                        },
                        score_mode: "multiply",
                        functions: [{ field_value_factor: { field: "ranked_hashtags.rank", missing: 1 } }],
                      },
                    },
                  },
                ],
              },
            },
            filter: {
              bool: {
                must: [{ term: { fork: false } }, { term: { public: true } }],
              },
            },
          },
        }
        assert_equal expected, @query.build_query
      end

      test "searches by topics with comma-syntax means OR" do
        @query.phrase = "topic:angular,react"
        assert_predicate @query, :filtering_by_topic?
        expected = {
          bool: {
            must: {
              bool: {
                must: [
                  nested: {
                    path: "ranked_hashtags",
                    query: {
                      function_score: {
                        query: {
                          bool: {
                            should: [
                              { match: { "ranked_hashtags.applied" => "angular" } },
                              { match: { "ranked_hashtags.applied" => "react" } },
                          ]
                          }
                        },
                        score_mode: "multiply",
                        functions: [{ field_value_factor: { field: "ranked_hashtags.rank", missing: 1 } }],
                      },
                    },
                  },
                ],
              },
            },
            filter: {
              bool: {
                must: [{ term: { fork: false } }, { term: { public: true } }],
              },
            },
          },
        }
        assert_equal expected, @query.build_query
      end

      test "searches by topics mixing single value and multiple value" do
        @query.phrase = "topic:angular,react topic:ruby"
        assert_predicate @query, :filtering_by_topic?
        expected = {
          bool: {
            must: {
              bool: {
                must: [
                  { nested: {
                    path: "ranked_hashtags",
                    query: {
                      function_score: {
                        query: { match: { "ranked_hashtags.applied" => "ruby" } },
                        score_mode: "multiply",
                        functions: [{ field_value_factor: { field: "ranked_hashtags.rank", missing: 1 } }],
                      },
                    },
                  } },
                  { nested: {
                    path: "ranked_hashtags",
                    query: {
                      function_score: {
                        query: {
                          bool: {
                            should: [
                              { match: { "ranked_hashtags.applied" => "angular" } },
                              { match: { "ranked_hashtags.applied" => "react" } },
                          ]
                          }
                        },
                        score_mode: "multiply",
                        functions: [{ field_value_factor: { field: "ranked_hashtags.rank", missing: 1 } }],
                      },
                    },
                  } },
                ],
              },
            },
            filter: {
              bool: {
                must: [{ term: { fork: false } }, { term: { public: true } }],
              },
            },
          },
        }
        assert_equal expected, @query.build_query
      end

      test "combines topic qualifier with query" do
        @query.phrase = "flannel #lumberjack"
        expected = {
          bool: {
            must: {
              bool: {
                must: [
                  {
                    function_score: {
                      query: {
                        query_string: {
                          query: "flannel",
                          fields: ["name^1.2", "name.camel", "name.ngram^0.8", "description",
                                   "applied_topics"],
                          default_operator: "AND",
                        },
                      },
                      score_mode: "multiply",
                      functions: [{ field_value_factor: { field: "rank", missing: 1 } }],
                    },
                  },
                  {
                    nested: {
                      path: "ranked_hashtags",
                      query: {
                        function_score: {
                          query: {
                            match: { "ranked_hashtags.applied" => "lumberjack" },
                          },
                          score_mode: "multiply",
                          functions: [
                            { field_value_factor: { field: "ranked_hashtags.rank", missing: 1 } },
                          ],
                        },
                      },
                    },
                  },
                ],
              },
            },
            filter: {
              bool: {
                must: [{ term: { fork: false } }, { term: { public: true } }],
              },
            },
          },
        }
        assert_equal expected, @query.build_query
      end

      test "searches by excluded topics only" do
        @query.phrase = "-topic:lumberjack"
        expected = {
          bool: {
            must: {
              bool: {
                must_not: [
                  nested: {
                    path: "ranked_hashtags",
                    query: {
                      function_score: {
                        query: {
                          match: { "ranked_hashtags.applied" => "lumberjack" },
                        },
                        score_mode: "multiply",
                        functions: [{ field_value_factor: { field: "ranked_hashtags.rank", missing: 1 } }],
                      },
                    },
                  },
                ],
              },
            },
            filter: {
              bool: {
                must: [{ term: { fork: false } }, { term: { public: true } }],
              },
            },
          },
        }
        assert_equal expected, @query.build_query
      end

      test "combines topic exclusion qualifier with query" do
        @query.phrase = "flannel -topic:lumberjack"
        expected = {
          bool: {
            must: {
              bool: {
                must: [
                  {
                    function_score: {
                      query: {
                        query_string: {
                          query: "flannel",
                          fields: ["name^1.2", "name.camel", "name.ngram^0.8", "description",
                                    "applied_topics"],
                          default_operator: "AND",
                        },
                      },
                      score_mode: "multiply",
                      functions: [{ field_value_factor: { field: "rank", missing: 1 } }],
                    },
                  }
                ],
                must_not: [
                  {
                    nested: {
                      path: "ranked_hashtags",
                      query: {
                        function_score: {
                          query: {
                            match: { "ranked_hashtags.applied" => "lumberjack" },
                          },
                          score_mode: "multiply",
                          functions: [
                            { field_value_factor: { field: "ranked_hashtags.rank", missing: 1 } },
                          ],
                        },
                      },
                    },
                  }
                ]
              },
            },
            filter: {
              bool: {
                must: [{ term: { fork: false } }, { term: { public: true } }],
              },
            },
          },
        }
        assert_equal expected, @query.build_query
      end

      test "combines topic inclusion with topic exclusion" do
        @query.phrase = "topic:flannel -topic:lumberjack"
        expected = {
          bool: {
            must: {
              bool: {
                must: [
                  {
                    nested: {
                      path: "ranked_hashtags",
                      query: {
                        function_score: {
                          query: {
                            match: { "ranked_hashtags.applied" => "flannel" },
                          },
                          score_mode: "multiply",
                          functions: [
                            { field_value_factor: { field: "ranked_hashtags.rank", missing: 1 } },
                          ],
                        },
                      },
                    },
                  }
                ],
                must_not: [
                  {
                    nested: {
                      path: "ranked_hashtags",
                      query: {
                        function_score: {
                          query: {
                            match: { "ranked_hashtags.applied" => "lumberjack" },
                          },
                          score_mode: "multiply",
                          functions: [
                            { field_value_factor: { field: "ranked_hashtags.rank", missing: 1 } },
                          ],
                        },
                      },
                    },
                  }
                ]
              },
            },
            filter: {
              bool: {
                must: [{ term: { fork: false } }, { term: { public: true } }],
              },
            },
          },
        }
        assert_equal expected, @query.build_query
      end

      test "allows searching for a topic using the #topic syntax" do
        @query.phrase = "#lumberjack"
        expected = {
          bool: {
            must: {
              bool: {
                must: [
                  nested: {
                    path: "ranked_hashtags",
                    query: {
                      function_score: {
                        query: {
                          match: { "ranked_hashtags.applied" => "lumberjack" },
                        },
                        score_mode: "multiply",
                        functions: [{ field_value_factor: { field: "ranked_hashtags.rank", missing: 1 } }],
                      },
                    },
                  },
                ],
              },
            },
            filter: { bool: { must: [{ term: { fork: false } }, { term: { public: true } }] } },
          },
        }
        assert_equal expected, @query.build_query
      end
    end
  end

  context "custom properties" do
    %w[properties props p].each do |prefix|
      test "'#{prefix}' prefix: filters by any dynamic property" do
        @query.phrase = "org:avocado #{prefix}.Color:Red #{prefix}.production:true"
        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { "custom_property_values.keyword" => "Color:red" } },
                  { term: { "custom_property_values.keyword" => "production:true" } },
                  { term: { fork: false } },
                  { term: { owner_id: @avocado.id } },
                ]
              }
            }
          }
        }
        assert_equal expected, @query.build_query
      end

      test "'#{prefix}' prefix: supports OR via comma syntax" do
        @query.phrase = "org:avocado #{prefix}.My-Color:Red,Blue #{prefix}.production:true"
        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { "custom_property_values.keyword" => "production:true" } },
                  { term: { fork: false } },
                  { term: { owner_id: @avocado.id } },
                ],
                should: { terms: { "custom_property_values.keyword" => %w[My-Color:red My-Color:blue] } },
                minimum_should_match: 1,
              }
            }
          }
        }
        assert_equal expected, @query.build_query
      end

      test "'#{prefix}' prefix: filters by missing property using `no:` qualifier" do
        @query.phrase = "org:avocado no:#{prefix}.color"
        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { fork: false } },
                  { term: { owner_id: @avocado.id } },
                ],
                must_not: { prefix: { "custom_property_values.keyword" => "color:" } },
              }
            }
          }
        }
        assert_equal expected, @query.build_query
      end

      test "'#{prefix}' prefix: filters by missing property using `no:` qualifier mixed with other filters" do
        @query.phrase = "org:avocado #{prefix}.version:none no:#{prefix}.color no:#{prefix}.fun #{prefix}.env:test -#{prefix}.prod:true -#{prefix}.team:sales"
        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { "custom_property_values.keyword" => "version:none" } },
                  { term: { "custom_property_values.keyword" => "env:test" } },
                  { term: { fork: false } },
                  { term: { owner_id: @avocado.id } },
                ],
                must_not: [
                  { term: { "custom_property_values.keyword" => "prod:true" } },
                  { term: { "custom_property_values.keyword" => "team:sales" } },
                  { prefix: { "custom_property_values.keyword" => "color:" } },
                  { prefix: { "custom_property_values.keyword" => "fun:" } },
                ],
              }
            }
          }
        }
        assert_equal expected, @query.build_query
      end

      test "'#{prefix}' prefix: filters by present property (negate missing)" do
        @query.phrase = "org:avocado -no:#{prefix}.color"
        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { prefix: { "custom_property_values.keyword" => "color:" } },
                  { term: { fork: false } },
                  { term: { owner_id: @avocado.id } },
                ],
              }
            }
          }
        }
        assert_equal expected, @query.build_query
      end

      test "#{prefix} filters are ignored if not in the scope of an org" do
        @query.phrase = "#{prefix}.color:red #{prefix}.production:true"
        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { fork: false } },
                  { term: { public: true } },
                ]
              }
            }
          }
        }
        assert_equal expected, @query.build_query
      end

      test "#{prefix} filter is not consumed if not used with a dot and a colon" do
        @query.phrase = "#{prefix}:red #{prefix}.production"

        text_query = @query.build_query[:bool][:must][:function_score][:query][:query_string][:query]

        assert_equal "\"#{prefix}\\:red\" \"#{prefix}.production\"", text_query
      end

      test "#{prefix} filter is ignored if user not a member" do
        expected = {
          constant_score: {
            filter: {
              bool: {
                must: [{ term: { owner_id: @avocado.id } }, { term: { visibility: "public" } }],
              }
            }
          }
        }

        query_non_member = Search::Queries::RepoQuery.new(current_user: @mojombo, include_forks: true, cap_filter: cap_authorizing_filter, experiment_owner_id_and_repo_id: true)
        query_non_member.phrase = "org:avocado #{prefix}.color:red"
        assert_equal expected, query_non_member.build_query

        query_anon = Search::Queries::RepoQuery.new(current_user: nil, include_forks: true, cap_filter: cap_authorizing_filter, experiment_owner_id_and_repo_id: true)
        query_anon.phrase = "org:avocado #{prefix}.color:red"
        assert_equal expected, query_anon.build_query
      end
    end
  end

  context "when building the highlight" do
    test "it creates some highlighting" do
      assert_equal(
          { encoder: :html,
            fields: {
              :name => { number_of_fragments: 0 },
              "name.camel" => { number_of_fragments: 0 },
              "name.ngram" => { number_of_fragments: 0 },
              :description => { number_of_fragments: 1, fragment_size: 256 },
            },
            type: "plain"
          },
          @query.build_highlight,
      )
    end

    test "it only highlights the searched fields" do
      @query.phrase = "search in:name"
      assert_equal(
          { encoder: :html,
            fields: {
              :name => { number_of_fragments: 0 },
              "name.camel" => { number_of_fragments: 0 },
              "name.ngram" => { number_of_fragments: 0 },
              :name_with_owner => { number_of_fragments: 0 },
            },
            type: "plain"
          },
          @query.build_highlight,
      )

      @query = Search::Queries::RepoQuery.new(phrase: "search in:description")
      assert_equal(
          { encoder: :html,
            fields: { description: { number_of_fragments: 1, fragment_size: 256 } },
            type: "plain"
          },
          @query.build_highlight,
      )

      @query = Search::Queries::RepoQuery.new(phrase: "search in:readme")
      assert_nil @query.build_highlight
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
      @query.sort = %w[stars desc]
      assert_equal([{ "followers" => "desc" }, "_score"], @query.build_sort)
    end

    test "accepts multiple sort fields" do
      @query.sort = %w[forks desc updated desc]
      assert_equal([{ "forks" => "desc" }, { "pushed_at" => "desc" }, "_score"], @query.build_sort)
    end

    test "gets sort from query - name defaults to desc as every field" do
      @query.phrase = "sort:name"
      assert_equal([{ "name_sort" => "desc" }, "_score"], @query.build_sort)
    end

    test "gets sort from query - name ascending" do
      @query.phrase = "sort:name-asc"
      assert_equal([{ "name_sort" => "asc" }, "_score"], @query.build_sort)
    end

    test "gets sort from query - updated defaults to desc" do
      @query.phrase = "sort:updated"
      assert_equal([{ "pushed_at" => "desc" }, "_score"], @query.build_sort)
    end

    test "gets sort from query - unknown fields are ignored" do
      @query.phrase = "sort:unknown"
      assert_equal(["_score"], @query.build_sort)
    end

    test "gets sort from query - many terms supported" do
      @query.phrase = "sort:stars sort:name-asc"
      assert_equal([{ "followers" => "desc" }, { "name_sort" => "asc" }, "_score"], @query.build_sort)
    end
  end

  context "when building the aggregations" do
    test "creates a filterless aggregation" do
      @query.aggregations = true
      @query.phrase = "stars:>42"

      assert_equal [:language_id], @query.aggregations
      assert_equal({ language_id: { terms: { field: :language_id, size: Search::Query::per_page_default } } }, @query.build_aggregations)
    end

    test "creates a global language filter" do
      @query.aggregations = true
      @query.phrase = "language:ruby"

      assert_equal({ language_id: { terms: { field: :language_id, size: Search::Query::per_page_default } } }, @query.build_aggregations)

      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { fork: false } },
          { term: { public: true } },
        ] },
      } } }
      assert_equal expected, @query.build_query

      assert_equal({ bool: { must: { term: { language_id: 326 } } } }, @query.build_filter)
    end

    test "creates a global language filter with lang:" do
      @query.aggregations = true
      @query.phrase = "lang:ruby"

      assert_equal({ language_id: { terms: { field: :language_id, size: Search::Query::per_page_default } } }, @query.build_aggregations)

      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { fork: false } },
          { term: { public: true } },
        ] },
      } } }
      assert_equal expected, @query.build_query

      assert_equal({ bool: { must: { term: { language_id: 326 } } } }, @query.build_filter)
    end
  end

  context "when created with a language" do
    test "overrides user supplied language filters" do
      query = Search::Queries::RepoQuery.new(phrase: "search language:ruby -language:perl", language: Linguist::Language["Python"])
      query = query.build_query

      expected = { bool: { must: [
        { term: { language_id: 303 } },
        { term: { fork: false } },
        { term: { public: true } },
      ] } }
      assert_equal expected, query[:bool][:filter]
    end

    test "overrides user supplied language filters with lang:" do
      query = Search::Queries::RepoQuery.new(phrase: "search lang:ruby -lang:perl", language: Linguist::Language["Python"])
      query = query.build_query

      expected = { bool: { must: [
        { term: { language_id: 303 } },
        { term: { fork: false } },
        { term: { public: true } },
      ] } }
      assert_equal expected, query[:bool][:filter]
    end
  end

  context "when executing" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @response = {
        "took" => 445, "timed_out" => false, "_shards" => { "total" => 2, "successful" => 2, "failed" => 0 },
        "hits" => { "total" => 596, "max_score" => nil, "hits" => [
          {
            "_index" => "repos",
            "_type" => "repository",
            "_id" => @facebox.id.to_s,
            "_score" => 3.9096773,
            "_source" => { "name" => "facebox" },
            "highlight" => {
              "comments.body" => ["Can you be more clear? And anyways, I have just started the GTK2 theme. Will notify you when it is done. Now you'll find thousands of things if you <em>search</em>.\n"],
            },
            "sort" => [1362070469000, 3.9096773],
          }, {
            "_index" => "repos",
            "_type" => "repository",
            "_id" => @grit.id.to_s,
            "_score" => 2.5102885,
            "_source" => { "name" => "grit" },
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
      @query.phrase = "search"
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
        @query.phrase = "search"
        @response["hits"]["hits"].first["_id"] = "0"
      end
    else
      test "prunes missing repos but not code from legacy code search cluster" do
        @query.phrase = "search"
        @response["hits"]["hits"].first["_id"] = "0"

        code_job_matcher = ->(job_args) do
          job_args[:job] == RemoveFromSearchIndexJob &&
            job_args[:args][0] == "code" &&
            job_args[:args][1] == 0
        end
      end
    end

    if GitHub.spamminess_check_enabled?
      test "prunes spammy results" do
        @query.phrase = "search"
        perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
          @mojombo.mark_as_spammy
        end
      end

      test "prunes when spammy field has been set" do
        @response["hits"]["hits"].each { |h| h.delete("_source") }
        @query.phrase = "search"
        @query.source_fields = false
        perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
          @mojombo.mark_as_spammy
        end
      end
    end
  end

  test "invalid query if the org is not authorized" do
    cap_filter = cap_unauthorizing_filter(@avocado)

    query = Search::Queries::RepoQuery.new(current_user: @defunkt, phrase: "org:#{@avocado.login}", include_forks: true, cap_filter:)

    expected = { constant_score: { filter:
      { bool: { must:
        { term: { public: true } }
      } }
    } }
    assert_equal(expected, query.build_query)

    refute query.valid_query?
  end
end

class SearchQueriesRepoQueryWithElasticTest < GitHub::TestCase
  setup do
    setup_search
  end

  teardown do
    teardown_search
  end

  test "find text in multiple fields" do
    in_title_repo = create :repository, name: "one-two"
    in_description_repo = create :repository, name: "descr", description: "a mix of one and two words"
    mixed_repo = create :repository, name: "one", description: "two cars"
    make_searchable(in_title_repo, in_description_repo, mixed_repo)

    query = Search::Queries::RepoQuery.new(current_user: create(:user), query: "one two")
    results = query.execute

    assert_same_elements %w(one-two descr one), results.results.map { |item| item.dig("_source", "name") }
  end
end
