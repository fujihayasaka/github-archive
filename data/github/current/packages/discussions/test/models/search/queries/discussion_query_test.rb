# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesDiscussionQueryTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo_owner = create(:user)
    @repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @label = create(:label, repository: @repo)
    @discussion = create(:discussion, repository: @repo, labels: [@label])
    @private_repo_owner = create(:user)
    @private_repo = create(:private_repository, owner: @private_repo_owner, has_discussions: true)
    @category = create(:discussion_category, repository: @repo)
  end

  setup do
    act_as(@user)
    @query = Search::Queries::DiscussionQuery.new(current_user: @user)
    GitHub::Experiment.raise_on_mismatches = false
  end

  context ".normalize" do
    test "removes conflicting `is:` queries values and keeps rightmost value" do
      assert_equal [[:is, "private"]],
        Search::Queries::DiscussionQuery.normalize(Search::Queries::DiscussionQuery.parse("is:public is:private"))

      assert_equal [[:is, "answered"]],
        Search::Queries::DiscussionQuery.normalize(Search::Queries::DiscussionQuery.parse("is:unanswered is:answered"))

      assert_equal [[:is, "unlocked"]],
        Search::Queries::DiscussionQuery.normalize(Search::Queries::DiscussionQuery.parse("is:locked is:unlocked"))

      assert_equal [[:is, "closed"]],
        Search::Queries::DiscussionQuery.normalize(Search::Queries::DiscussionQuery.parse("is:open is:closed"))

      assert_equal [[:is, "open"]],
        Search::Queries::DiscussionQuery.normalize(Search::Queries::DiscussionQuery.parse("is:closed is:open"))
    end

    test "removes conflicting no:label and label: terms and keeps the rightmost value" do
      assert_equal [[:no, "label"]],
        Search::Queries::DiscussionQuery.normalize(Search::Queries::DiscussionQuery.parse("label:something label:other no:label"))

      assert_equal [[:label, "aaa"], [:label, "bbb"]],
        Search::Queries::DiscussionQuery.normalize(Search::Queries::DiscussionQuery.parse("no:label label:aaa label:bbb"))

      assert_equal [[:label, "aaa"], [:label, "bbb"]],
        Search::Queries::DiscussionQuery.normalize(Search::Queries::DiscussionQuery.parse("label:aaa no:labels label:bbb"))
    end
  end

  context "query params" do
    test "generates routing information" do
      @query.phrase = "search @#{@repo.nwo}"
      assert_equal({ routing: "#{@repo.id}" }, @query.query_params)
    end

    test "generates no routing information for global queries" do
      @query.phrase = "search"
      assert_predicate @query, :global?
      assert_nil @query.routing
      assert_equal({}, @query.query_params)
    end
  end

  context "when building the query" do
    test "empty queries only match public repos" do
      expected = { constant_score: { filter: { bool: { must: { term: { public: true } } } } } }
      assert_equal expected, @query.build_query
    end

    test "creates a function score string query" do
      @query.phrase = "search"
      query = @query.build_query

      assert query.key?(:bool)
      assert query[:bool][:must][:function_score]

      expected = {
        query: "search",
        fields: %w[title^1.5 body comments.body^0.8],
        phrase_slop: 10,
        default_operator: "AND",
        analyzer: "texty_search",
      }
      assert_equal expected, query[:bool][:must][:function_score][:query][:query_string]

      expected = { bool: { must: { term: { public: true } } } }
      assert_equal expected, query[:bool][:filter]
    end

    test "it escapes wildcard by default" do
      @query.phrase = "search* in:title"
      query = @query.build_query

      assert_equal("search\\*", query[:bool][:must][:function_score][:query][:query_string][:query])
    end

    test "it does not escape wildcard if escape_wildcards is set to false" do
      raw_query = Search::Queries::IssueQuery.new(escape_wildcards: false)
      raw_query.phrase = "search* in:title"
      query = raw_query.build_query

      assert_equal("search*", query[:bool][:must][:function_score][:query][:query_string][:query])
    end

    test "does not assume that numbers are discussion numbers if :in is specified" do
      @query.phrase = "search 1234 in:title"
      query = @query.build_query

      refute query[:bool][:must].key?(:bool)

      assert_equal '"search" 1234', query[:bool][:must][:function_score][:query][:query_string][:query]

      expected = { bool: { must: { term: { public: true } } } }
      assert_equal expected, query[:bool][:filter]
    end

    test "it can be forced to search for numbers even when :in is specified" do
      raw_query = Search::Queries::DiscussionQuery.new(force_discussion_number_terms: true)
      raw_query.phrase = "search 1234 in:title"
      query = raw_query.build_query

      # Make sure the free text portion of the query is correct.
      assert_equal(
        '"search" 1234',
        query[:bool][:must][:bool][:should][0][:function_score][:query][:query_string][:query]
      )

      # Make sure we have a number clause too.
      assert_equal(
        { term: { number: { value: 1234, boost: 100 } } },
        query[:bool][:must][:bool][:should][1]
      )
    end

    test "assumes that numbers are discussion numbers if :in is not specified" do
      @query.phrase = "search 1234"
      query = @query.build_query

      assert query[:bool][:must].key?(:bool)

      assert_equal '"search" 1234', query[:bool][:must][:bool][:should][0][:function_score][:query][:query_string][:query]

      expected = { bool: { must: { term: { public: true } } } }
      assert_equal expected, query[:bool][:filter]

      expected = { term: { number: { value: 1234, boost: 100 } } }
      assert_equal expected, query[:bool][:must][:bool][:should][1]
    end

    test "queries the specified fields" do
      @query.phrase = "search in:title"
      query = @query.build_query

      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[title^1.5], qs[:fields]
    end

    test "queries multiple fields" do
      @query.phrase = 'search in:"title body"'
      query = @query.build_query

      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[title^1.5 body], qs[:fields]
    end

    test "when `ngram_title: true` it adds a title.ngram to the search fields" do
      discussion_query = Search::Queries::DiscussionQuery.new(current_user: @user, ngram_title: true)
      discussion_query.phrase = "spaghetti"
      query = discussion_query.build_query

      qs = query[:bool][:must][:function_score][:query][:query_string]
      assert_equal %w[title^1.5 title.ngram^0.5 body comments.body^0.8], qs[:fields]
    end
  end

  context "when building the query with search qualifiers" do
    test "generates an author filter" do
      @query.phrase = "author:#{@user}"

      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { user_id: @user.id } },
          { term: { public: true } },
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates an author exclusion filter" do
      @query.phrase = "-author:#{@user}"

      expected = { constant_score: { filter: {
        bool: {
          must: { term: { public: true } },
          must_not: { term: { user_id: @user.id } },
        },
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates an answered-by filter" do
      @query.phrase = "answered-by:#{@user}"

      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { answered_by_id: @user.id } },
          { term: { public: true } },
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates an answered-by exclusion filter" do
      @query.phrase = "-answered-by:#{@user}"

      expected = { constant_score: { filter: {
        bool: {
          must: { term: { public: true } },
          must_not: { term: { answered_by_id: @user.id } },
        },
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates a commenter filter" do
      @query.phrase = "commenter:#{@user}"

      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { "comments.user_id" => @user.id } },
          { term: { public: true } },
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
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates an updated filter" do
      @query.phrase = "updated:<2013-02-01"

      expected = { constant_score: { filter: {
        bool: { must: [
          { range: { updated_at: { lt: "2013-02-01||/d" } } },
          { term: { public: true } },
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates a closed filter" do
      @query.phrase = "closed:<2013-02-01"

      expected = { constant_score: { filter: {
        bool: { must: [
          { range: { closed_at: { lt: "2013-02-01||/d" } } },
          { term: { public: true } },
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates a number of comments filter" do
      @query.phrase = "comments:>42"

      expected = { constant_score: { filter: {
        bool: { must: [
          { range: { num_comments: { gt: "42" } } },
          { term: { public: true } },
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates an owner repository filter" do
      @query.phrase = "@#{@repo_owner}"

      expected = { constant_score: { filter: { bool: { must: { term: { repository_id: @repo.id } } } } } }
      assert_equal expected, @query.build_query
    end

    test "generates a repository filter" do
      other_repo = create(:repository)
      @query.phrase = "@#{@repo_owner} @#{other_repo.nwo}"
      expected = { constant_score: { filter: { bool: { must: { terms: { repository_id: [other_repo.id, @repo.id] } } } } } }
      assert_equal expected, @query.build_query
    end

    test "generates a repository filter for app viewing private repos" do
      public_repo    = create(:repository, owner: @private_repo_owner, has_discussions: true)
      github_app     = create(:integration)
      installation   = make_integration_installation(
        integration: github_app,
        target: @private_repo_owner,
        permissions: { "discussions" => :read },
      )

      act_as(installation.bot)
      @query.current_user = installation.bot
      @query.phrase = "user:#{@private_repo_owner}"
      expected = { constant_score: { filter: {
        bool: { must: { terms: { repository_id: [public_repo.id, @private_repo.id] } } }
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates a repository filter for unauthorized app trying to search for private repos" do
      public_repo    = create(:repository, owner: @private_repo_owner, has_discussions: true)
      github_app     = create(:integration)
      installation   = make_integration_installation(
        integration: github_app,
        target: @user,
        permissions: { "discussions" => :read },
      )

      act_as(installation.bot)
      @query.current_user = installation.bot
      @query.phrase = "user:#{@private_repo_owner}"
      expected = { constant_score: { filter: {
        bool: { must: { term: { repository_id: public_repo.id } } }
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates an involves filter" do
      @query.phrase = "involves:#{@user}"
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { public: true } },
          { bool: { should: [
            { term: { user_id: @user.id } },
            { term: { "comments.user_id" => @user.id } },
          ] } },
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates a label filter" do
      @query.phrase = "label:WHATEVER"
      expected = { constant_score: { filter: { bool: { must: [
        { term: { labels: "whatever" } },
        { term: { public: true } },
       ] } } } }
      assert_equal expected, @query.build_query
    end

    test "generates a no-label filter" do
      @query.phrase = "no:labels"
      expected = { constant_score: { filter: { bool: { must: [
        { bool: { must_not: { exists: { field: :labels } } } },
        { term: { public: true } },
       ] } } } }
      assert_equal expected, @query.build_query
    end

    test "generates unique filters" do
      @query.phrase = "updated:2016-09-01..2016-09-30 comments:>50 " * 12
      expected = { constant_score: { filter: {
        bool: {
          must: [
            { range: { updated_at: { gte: "2016-09-01||/d", lte: "2016-09-30||/d" } } },
            { range: { num_comments: { gt: "50" } } },
            { term: { public: true } },
          ],
        },
      } } }
      assert_equal expected, @query.build_query
    end

    test "generates a category filter" do
      query = Search::Queries::DiscussionQuery.new(current_user: @user, repo_id: @repo.id)
      query.phrase = "category:#{@category.name}"

      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [
                { term: { category_id: @category.id } },
                { term: { repository_id: @repo.id } },
              ],
            },
          },
        },
      }

      assert_equal expected, query.build_query
    end

    test "generating a category filter is case insensitive" do
      cased_category = create(:discussion_category, repository: @repo, name: "Paprika")

      query = Search::Queries::DiscussionQuery.new(current_user: @user, repo_id: @repo.id)
      query.phrase = "category:PAPRIKA"

      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [
                { term: { category_id: cased_category.id } },
                { term: { repository_id: @repo.id } },
              ],
            },
          },
        },
      }

      assert_equal expected, query.build_query
    end

    test "generates a category filter based on referenced repositories" do
      other_repo = create(:repository, has_discussions: true)
      other_category = create(:discussion_category, repository: other_repo)

      query = Search::Queries::DiscussionQuery.new(current_user: @user)
      query.phrase = "repo:#{@repo.nwo} repo:#{other_repo.nwo} category:#{@category.name} category:#{other_category.name}"

      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [
                { terms: { category_id: [@category.id, other_category.id] } },
                { terms: { repository_id: [@repo.id, other_repo.id] } },
              ],
            },
          },
        },
      }

      assert_equal expected, query.build_query
    end

    test "generates a category filter based on a referenced repository when the owner of the repo is capitalized" do
      owner = create(:user, login: "NameWithCapital")
      repo = create(:repository, has_discussions: true, owner: owner)
      category = create(:discussion_category, repository: repo)

      query = Search::Queries::DiscussionQuery.new(current_user: @user)
      query.phrase = "repo:#{repo.nwo} category:#{category.name}"

      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [
                { term: { category_id: category.id } },
                { term: { repository_id: repo.id } },
              ],
            },
          },
        },
      }

      assert_equal expected, query.build_query
    end

    test "accounts for negated repository references" do
      query = Search::Queries::DiscussionQuery.new(current_user: @user)
      query.phrase = "-repo:#{@repo.nwo} category:#{@category.name}"

      expected = {
        constant_score: {
          filter: {
            bool: {
              must: { term: { public: true } },
              must_not: { term: { repository_id: @repo.id } },
            },
          },
        },
      }

      assert_equal expected, query.build_query
    end

    test "generates a category exclusion filter" do
      query = Search::Queries::DiscussionQuery.new(current_user: @user, repo_id: @repo.id)
      query.phrase = "-category:#{@category.name}"

      expected = {
        constant_score: {
          filter: {
            bool: {
              must: { term: { repository_id: @repo.id } },
              must_not: { term: { category_id: @category.id } },
            },
          },
        },
      }

      assert_equal expected, query.build_query
    end

    test "generates a state reason filter" do
      query = Search::Queries::DiscussionQuery.new(current_user: @user, repo_id: @repo.id)
      query.phrase = "reason:resolved"

      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [
                { term: { state_reason: "resolved" } },
                { term: { repository_id: @repo.id } },
              ],
            },
          },
        },
      }

      assert_equal expected, query.build_query
    end

    test "generates a state reason exclusion filter" do
      query = Search::Queries::DiscussionQuery.new(current_user: @user, repo_id: @repo.id)
      query.phrase = "-reason:resolved"

      expected = {
        constant_score: {
          filter: {
            bool: {
              must: { term: { repository_id: @repo.id } },
              must_not: { term: { state_reason: "resolved" } },
            },
          },
        },
      }

      assert_equal expected, query.build_query
    end
  end

  context "using the 'is:' qualifier" do
    test "filters on multiple 'is' qualifiers" do
      @query.phrase = "is:public is:locked is:unanswered"
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { public: true } },
          { term: { unanswered: true } },
          { term: { locked: true } },
          { term: { public: true } },
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "filters on the public state" do
      @query.phrase = "is:public"
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { public: true } },
          { term: { public: true } },
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "filters on the public state for anonymous users" do
      query = Search::Queries::DiscussionQuery.new(current_user: nil)
      query.phrase = "is:public"
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { public: true } },
          { term: { public: true } },
        ] },
      } } }
      assert_equal expected, query.build_query
    end

    test "filters on the private state" do
      private_repo = create(:private_repository, owner: @user)
      @query.phrase = "is:private"
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { public: false } },
          { bool: { should: [
            { term: { public: true } },
            { term: { repository_id: private_repo.id } },
          ] } },
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "filters on the private state for anonymous users" do
      query = Search::Queries::DiscussionQuery.new(current_user: nil)
      query.phrase = "is:private"
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { public: false } },
          { term: { public: true } },
        ] },
      } } }
      assert_equal expected, query.build_query
    end

    test "filters on the locked state true" do
      %w(is:locked -is:unlocked).each do |phrase|
        @query.phrase = phrase
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { locked: true } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end
    end

    test "filters on the locked state false" do
      %w(is:unlocked -is:locked).each do |phrase|
        @query.phrase = phrase
        expected = { constant_score: { filter: {
          bool: { must: [
            { term: { locked: false } },
            { term: { public: true } },
          ] },
        } } }
        assert_equal expected, @query.build_query
      end
    end

    test "filters on the answered state" do
      private_repo = create(:private_repository, owner: @user)
      @query.phrase = "is:answered"
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { answered: true } },
          { bool: { should: [
            { term: { public: true } },
            { term: { repository_id: private_repo.id } },
          ] } },
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "filters on the negated answered state" do
      private_repo = create(:private_repository, owner: @user)
      @query.phrase = "-is:answered"
      expected = { constant_score: { filter: {
        bool: { must:
          { bool: { should: [
            { term: { public: true } },
            { term: { repository_id: private_repo.id } }
          ] } },
                must_not: { term: { answered: true } } }
      } } }
      assert_equal expected, @query.build_query
    end

    test "filters on the unanswered state" do
      private_repo = create(:private_repository, owner: @user)
      @query.phrase = "is:unanswered"
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { unanswered: true } },
          { bool: { should: [
            { term: { public: true } },
            { term: { repository_id: private_repo.id } },
          ] } },
        ] },
      } } }
      assert_equal expected, @query.build_query
    end

    test "filters on the negated unanswered state" do
      private_repo = create(:private_repository, owner: @user)
      @query.phrase = "-is:unanswered"
      expected = { constant_score: { filter: {
        bool: { must:
          { bool: { should: [
            { term: { public: true } },
            { term: { repository_id: private_repo.id } }
          ] } },
                must_not: { term: { unanswered: true } } }
      } } }
      assert_equal expected, @query.build_query
    end

    test "filters on the open state" do
      @query.phrase = "is:open"

      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { state: "open" } },
          { term: { public: true } },
        ] },
      } } }

      assert_equal expected, @query.build_query
    end

    test "filters on the closed state" do
      @query.phrase = "is:closed"

      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { state: "closed" } },
          { term: { public: true } },
        ] },
      } } }

      assert_equal expected, @query.build_query
    end
  end

  context "private profile users in qualifiers" do
    test "filtering by private profile user when viewer is the user" do
      enable_feature_flag(:invalidate_private_profile_searches)
      private_user = create(:user, private_profile: true)
      # Repo for `user:` searches
      create(:repository, owner: private_user)

      # Qualifiers
      %w(author commenter user org owner involves).each do |qualifier|
        query = Search::Queries::DiscussionQuery.new(phrase: "#{qualifier}:#{private_user}", current_user: private_user)
        assert_predicate query, :valid_query?
      end

      # No qualifier, just the user login
      query = Search::Queries::DiscussionQuery.new(phrase: private_user.login, current_user: private_user)
      assert_predicate query, :valid_query?
    end

    test "filtering by private profile user when viewer is not the user" do
      enable_feature_flag(:invalidate_private_profile_searches)
      private_user = create(:user, private_profile: true)
      # Repo for `user:` searches
      create(:repository, owner: private_user)
      viewer = create(:user)

      # Qualifiers
      %w(author commenter user org owner involves).each do |qualifier|
        query = Search::Queries::DiscussionQuery.new(phrase: "#{qualifier}:#{private_user}", current_user: viewer)
        refute_predicate query, :valid_query?
      end

      # No qualifier, just the user login
      query = Search::Queries::DiscussionQuery.new(phrase: private_user.login, current_user: viewer)
      assert_predicate query, :valid_query?
    end
  end

  context "when building the highlight" do
    test "creates some highlighting" do
      assert_equal(
          { encoder: :html,
            fields: {
              :title => { number_of_fragments: 0 },
              :body => { number_of_fragments: 1, fragment_size: Search::Queries::DiscussionQuery::FRAGMENT_SIZE },
              "comments.body" => { number_of_fragments: 1, fragment_size: Search::Queries::DiscussionQuery::FRAGMENT_SIZE },
            },
            type: "plain"
          }, @query.build_highlight
      )
    end

    test "only highlights the searched fields" do
      @query.phrase = "search in:title"
      assert_equal(
        { encoder: :html,
          fields: {
          title: { number_of_fragments: 0 },
          },
          type: "plain"
        }, @query.build_highlight
      )

      @query = Search::Queries::DiscussionQuery.new(phrase: "search in:title,comments")
      assert_equal(
        { encoder: :html,
          fields: {
            :title => { number_of_fragments: 0 },
            "comments.body" => { number_of_fragments: 1, fragment_size: Search::Queries::DiscussionQuery::FRAGMENT_SIZE },
          },
          type: "plain"
        }, @query.build_highlight
      )
    end

    test "only if highlighting is enabled" do
      @query.phrase = "search"

      doc = @query.query_document
      refute doc.key?(:highlight)

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
      assert_equal([{ "bumped_at" => { "order" => "desc", "unmapped_type" => "date" } }, "_score"], @query.build_sort)

      @query.phrase = '""'
      assert_equal([{ "bumped_at" => { "order" => "desc", "unmapped_type" => "date" } }, "_score"], @query.build_sort)
    end

    test "sorts using upvotes when the sort is 'top' and feature flag is enabled" do
      query = Search::Queries::DiscussionQuery.new(current_user: @user, repo_id: @repo.id)
      query.sort = %w[top desc]
      assert_equal([{ "total_upvotes" => "desc" }, "_score"], query.build_sort)
    end

    test "sorts by the number of interactions when the sort is 'interactions'" do
      query = Search::Queries::DiscussionQuery.new(current_user: @user, repo_id: @repo.id)
      query.sort = %w[interactions desc]
      assert_equal([{ "num_interactions" => "desc" }, "_score"], query.build_sort)
    end

    test "sorts by the number of reactions when the sort is 'reactions'" do
      query = Search::Queries::DiscussionQuery.new(current_user: @user, repo_id: @repo.id)
      query.sort = %w[reactions desc]
      assert_equal([{ "num_reactions" => "desc" }, "_score"], query.build_sort)
    end

    test "sorts by the number of plus1 reactions when the sort is 'reactions-+1'" do
      query = Search::Queries::DiscussionQuery.new(current_user: @user, repo_id: @repo.id)
      query.sort = %w[reactions-+1 desc]
      assert_equal([{ "reactions.+1" => "desc" }, "_score"], query.build_sort)
    end

    test "sorts by the number of minus1 reactions when the sort is 'reactions--1'" do
      query = Search::Queries::DiscussionQuery.new(current_user: @user, repo_id: @repo.id)
      query.sort = %w[reactions--1 desc]
      assert_equal([{ "reactions.-1" => "desc" }, "_score"], query.build_sort)
    end

    test "sorts by the number of smile reactions when the sort is 'reactions-smile'" do
      query = Search::Queries::DiscussionQuery.new(current_user: @user, repo_id: @repo.id)
      query.sort = %w[reactions-smile desc]
      assert_equal([{ "reactions.smile" => "desc" }, "_score"], query.build_sort)
    end

    test "sorts by the number of heart reactions when the sort is 'reactions-heart'" do
      query = Search::Queries::DiscussionQuery.new(current_user: @user, repo_id: @repo.id)
      query.sort = %w[reactions-heart desc]
      assert_equal([{ "reactions.heart" => "desc" }, "_score"], query.build_sort)
    end

    test "sorts by the number of tada reactions when the sort is 'reactions-tada'" do
      query = Search::Queries::DiscussionQuery.new(current_user: @user, repo_id: @repo.id)
      query.sort = %w[reactions-tada desc]
      assert_equal([{ "reactions.tada" => "desc" }, "_score"], query.build_sort)
    end

    test "sorts by the number of thinking face reactions when the sort is 'reactions-thinking_face'" do
      query = Search::Queries::DiscussionQuery.new(current_user: @user, repo_id: @repo.id)
      query.sort = %w[reactions-thinking_face desc]
      assert_equal([{ "reactions.thinking_face" => "desc" }, "_score"], query.build_sort)
    end
  end

  context "when created with a repository id" do
    test "overrides the normal repository filter" do
      query = Search::Queries::DiscussionQuery.new(phrase: "search @#{@user} -@#{@repo_owner}", repo_id: @repo.id)

      expected = { bool: {
        must: { function_score: {
          query: { query_string: {
            query: "search",
            fields: %w[title^1.5 body comments.body^0.8],
            phrase_slop: 10,
            default_operator: "AND",
            analyzer: "texty_search",
          } },
          score_mode: "sum",
          functions: [
            { exp: { created_at: {
              scale: "42d",
              decay: 0.5,
            } } },
            { exp: { updated_at: {
              scale: "84d",
              decay: 0.5,
            } } },
          ],
        } },
        filter: { bool: { must: { term: { repository_id: @repo.id } } } },
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

    test 'always includes the "public" field' do
      query = Search::Queries::DiscussionQuery.new(phrase: "search", source_fields: %w[state repo_id])
      assert_equal %w[state repo_id public], query.source_fields

      query = Search::Queries::DiscussionQuery.new(phrase: "search", source_fields: [])
      assert_equal %w[public], query.source_fields
    end
  end

  test "prune_discussion prunes a discussion that belongs to an unsearchable repository" do
    doc = { "_id" => @discussion.id.to_s, "_routing" => @discussion.repository_id.to_s }
    query = Search::Queries::DiscussionQuery.new

    # repo shouldn't be disabled, so discussion won't be pruned here
    refute query.prune_discussion(doc, @discussion)

    # the discussion will be pruned in this scenario
    @discussion.stubs(:parent_repo_is_searchable?).returns(false)
    assert query.prune_discussion(doc, @discussion)

    # the pruned discussion should be visible in the job queue now
    assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["bulk_discussions", @discussion.repository.id]
  end

  context "top_filter_only_unlocked" do
    test "filters unlocked discussions when sorting by top if `top_filter_only_unlocked` is true" do
      query = Search::Queries::DiscussionQuery.new(
        phrase: "sort:top",
        repo_id: @repo.id,
        top_filter_only_unlocked: true,
      )

      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [{ term: { locked: false } }, { term: { repository_id: @repo.id } }]
            }
          }
        }
      }
      assert_equal expected, query.build_query
    end

    test "does not filter unlocked discussions when sorting by top if `top_filter_only_unlocked` is false" do
      query = Search::Queries::DiscussionQuery.new(
        phrase: "sort:top",
        repo_id: @repo.id,
        top_filter_only_unlocked: false,
      )

      expected = {
        constant_score: {
          filter: {
            bool: {
              must: { term: { repository_id: @repo.id } }
            }
          }
        }
      }
      assert_equal expected, query.build_query
    end

    test "specifying `is:locked` if `top_filter_only_unlocked` is true does not filter out locked discussions" do
      query = Search::Queries::DiscussionQuery.new(
        phrase: "sort:top is:locked",
        repo_id: @repo.id,
        top_filter_only_unlocked: true,
      )

      expected = {
        constant_score: {
          filter: {
            bool: {
              must: [{ terms: { locked: [true, false] } }, { term: { repository_id: @repo.id } }]
            }
          }
        }
      }
      assert_equal expected, query.build_query
    end

    test "does not filter out locked discussions when sort is not top and `top_filter_only_unlocked` is true" do
      query = Search::Queries::DiscussionQuery.new(
        phrase: "",
        repo_id: @repo.id,
        top_filter_only_unlocked: true,
      )

      expected = {
        constant_score: {
          filter: {
            bool: {
              must: { term: { repository_id: @repo.id } }
            }
          }
        }
      }
      assert_equal expected, query.build_query
    end
  end
end
