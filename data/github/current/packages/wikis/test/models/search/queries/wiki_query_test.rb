# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesWikiQueryTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")

    @facebox = create(:repository, name: "facebox", owner: @defunkt)
    @grit    = create(:repository, name: "grit", owner: @mojombo)
    RepositoryWiki.create!(repository: @facebox)
    RepositoryWiki.create!(repository: @grit)

    @facebox.unsullied_wiki.setup_git_repository
    @grit.unsullied_wiki.setup_git_repository
  end

  setup do
    @query = Search::Queries::WikiQuery.new(current_user: @defunkt, page: 1)
    GitHub::Experiment.raise_on_mismatches = false
  end

  context "query params" do
    test "generates routing information" do
      @query.phrase = "search @defunkt @mojombo/grit"
      assert_equal({ type: "page", routing: "#{@grit.id},#{@facebox.id}" }, @query.query_params)
    end

    test "generates no routing information for global queries" do
      @query.phrase = "search"

      assert @query.global?
      assert_nil @query.routing
      assert_equal({ type: "page" }, @query.query_params)
    end
  end

  context "when building the query" do
    test "empty queries only match public repos and no wiki state documents" do
      expected = {
        constant_score: {
          filter: {
            bool: {
              must: { term: { public: true } },
              must_not: { term: { is_wiki_state_doc: true } }
            }
          }
        }
      }
      assert_equal expected, @query.build_query
    end

    test "it creates a function score string query" do
      @query.phrase = "search"
      query = @query.build_query

      assert query.key?(:bool)

      expected = {
        query: "search",
        fields: %w[title^1.5 body],
        phrase_slop: 10,
        default_operator: "AND",
        analyzer: "texty_search",
      }
      assert_equal expected, query[:bool][:must][:query_string]

      expected = { bool: {
        must: { term: { public: true } },
        must_not: { term: { is_wiki_state_doc: true } }
      } }
      assert_equal expected, query[:bool][:filter]
    end
  end

  context "with search qualifiers" do
    test "generates an updated filter" do
      @query.phrase = "updated:<2013-02-01"

      expected = { constant_score: { filter: {
        bool: { must: [
          { range: { updated_at: { lt: "2013-02-01||/d" } } },
          { term: { public: true } },
        ], must_not: { term: { is_wiki_state_doc: true } } }
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates an owner repository filter" do
      @query.phrase = "@defunkt"

      expected = { constant_score: { filter: {
        bool: { must:
          { term: { repo_id: @facebox.id } },
        must_not: { term: { is_wiki_state_doc: true } }
        },
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates an owner repository filter for user:" do
      @query.phrase = "user:defunkt"

      expected = { constant_score: { filter: {
        bool: { must:
          { term: { repo_id: @facebox.id } },
        must_not: { term: { is_wiki_state_doc: true } }
        },
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates an owner repository filter for org:" do
      @query.phrase = "org:defunkt"

      expected = { constant_score: { filter: {
        bool: { must:
          { term: { repo_id: @facebox.id } },
        must_not: { term: { is_wiki_state_doc: true } }
        },
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates an owner repository filter for owner:" do
      @query.phrase = "owner:defunkt"

      expected = { constant_score: { filter: {
        bool: { must:
          { term: { repo_id: @facebox.id } },
        must_not: { term: { is_wiki_state_doc: true } }
        },
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates a repository filter" do
      @query.phrase = "@defunkt @mojombo/grit"
      expected = { constant_score: { filter: {
        bool: { must:
          { terms: { repo_id: [@grit.id, @facebox.id] } },
          must_not: { term: { is_wiki_state_doc: true } }
        },
      } } }
      assert_equal expected, @query.build_query
    end

    test "it queries the title" do
      @query.phrase = "search in:title"
      assert_equal %w[title^1.5], @query.query_fields
    end

    test "it queries the body" do
      @query.phrase = "search in:body"
      assert_equal %w[body], @query.query_fields
    end
  end

  context "when building the highlight" do
    test "it creates some highlighting" do
      assert_equal(
          { encoder: :html,
            type: "plain",
            fields: {
              title: { number_of_fragments: 0 },  # force the whole title to be included in the fragment
              body: { number_of_fragments: 1, fragment_size: Search::Queries::WikiQuery::FRAGMENT_SIZE },
          } }, @query.build_highlight
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

    test "maps the sort field" do
      @query.sort = %w[updated desc]
      assert_equal([{ "updated_at" => { "order" => "desc", "unmapped_type" => "date" } }, "_score"], @query.build_sort)
    end
  end

  context "when created with a repository id" do
    test "overrides the normal repository filter" do
      query = Search::Queries::WikiQuery.new(phrase: "search @defunkt -@mojombo", repo_id: @grit.id)

      expected = { bool: {
        must: { query_string: {
          query: "search",
          fields: %w[title^1.5 body],
          phrase_slop: 10,
          default_operator: "AND",
          analyzer: "texty_search",
        } },
        filter: { bool: { must:
          { term: { repo_id: @grit.id } },
          must_not: { term: { is_wiki_state_doc: true } }
        } },
      } }
      assert_equal expected, query.build_query
    end
  end

  context "when validating responses" do
    test 'public field gets extracted from the "_source"' do
      assert_equal false, @query.is_public({ "_source" => { "public" => false } })
      assert_equal true, @query.is_public({ "_source" => { "public" => true } })
      assert_nil @query.is_public({ "_source" => { "no_public_field" => "booo" } })
      assert_nil @query.is_public({ "no_source_field" => "booo" })
    end
  end

  def mock_response
    @response = {
      "took" => 445, "timed_out" => false, "_shards" => { "total" => 2, "successful" => 2, "failed" => 0 },
      "hits" => { "total" => 596, "max_score" => nil, "hits" => [
        {
          "_index" => "wikis",
          "_type" => "page",
          "_id" => "#{@facebox.id}::Home.md",
          "_score" => 3.9096773,
          "_source" => { "title" => "Home", "body" => "Welcome to the wiki!\n", "repo_id" => @facebox.id.to_s, "public" => true, "updated_at" => "2013-02-28T09:10:52-08:00" },
          "highlight" => {
            "body" => ["Welcome to the <em>wiki</em>!\n"],
          },
          "sort" => [1362070469000, 3.9096773],
        },
        {
          "_index" => "wikis",
          "_type" => "page",
          "_id" => "#{@grit.id}::Page-2.md",
          "_score" => 2.5102885,
          "_source" => { "title" => "Page 2", "body" => "This is page 2 of the wiki\n", "repo_id" => @grit.id.to_s, "public" => true, "state" => "open", "updated_at" => "2013-02-28T09:01:22-08:00" },
          "highlight" => {
            "body" => ["This is page 2 of the <em>wiki</em>\n"],
          },
          "sort" => [1362067735000, 2.5102885],
        }]
      }
    }

    @index = Elastomer::Index.new("test")
    @response["hits"] = Elastomer::UpgradeShims.shim_search_response_hits(@response["hits"]) if @index.index_running_version_8_plus?
    @index.stubs(:search).returns(@response)
    @index.stubs(:count).returns(Elastomer::UpgradeShims.get_total_hits(@response["hits"]))

    @query.instance_variable_set(:@index, @index)
    @query.phrase = "wiki"
  end

  context "when executing" do
    test "executes the query" do
      mock_response
      results = @query.execute

      assert_equal @query.page, results.page
      assert_equal @query.per_page, results.per_page
      assert_equal @response["took"], results.time
      assert_equal Elastomer::UpgradeShims.get_total_hits(@response["hits"]), results.total

      first, last = results.results
      assert first.is_a?(Hash), "expected #{first} to be a Hash"
      assert_equal @facebox, first["_model"]

      assert last.is_a?(Hash), "expected #{last} to be a Hash"
      assert_equal @grit, last["_model"]
    end

    test "executes the count query" do
      mock_response
      assert_equal Elastomer::UpgradeShims.get_total_hits(@response["hits"]), @query.count
    end

    test "prunes pages from missing repos" do
      mock_response
      @response["hits"]["hits"].first["_source"]["repo_id"] = "0"

      results = @query.execute
      first = results.results.first

      assert_enqueued_jobs 1, only: RemoveFromSearchIndexJob, queue: :index_high
      assert first.is_a?(Hash), "expected #{first} to be a Hash"
      assert_equal @grit, first["_model"]
    end

    if GitHub.spamminess_check_enabled?
      test "prunes spammy results" do
        mock_response
        perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
          @mojombo.mark_as_spammy
        end

        results = @query.execute
        first = results.results.first

        assert_enqueued_jobs 1, only: RemoveFromSearchIndexJob, queue: :index_high
        assert first.is_a?(Hash), "expected #{first} to be a Hash"
        assert_equal @facebox, first["_model"]
      end
    end
  end

  context "valid query" do
    test "empty phrase query returns not valid query" do
      query = Search::Queries::WikiQuery.new(current_user: @user, phrase: " ")
      refute_predicate query, :valid_query?
    end

    test "phrase query returns valid query" do
      query = Search::Queries::WikiQuery.new(current_user: @user, phrase: "test")
      assert_predicate query, :valid_query?
    end
  end
end
