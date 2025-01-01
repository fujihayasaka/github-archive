# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesCommitQueryTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")
    @twp     = create(:user, login: "TwP", plan: "medium", email: "twp@example.com")

    @facebox = create(:repository, name: "facebox", owner: @defunkt)
    @grit    = create(:repository, name: "grit", owner: @mojombo)
  end

  setup do
    @query = Search::Queries::CommitQuery.new(current_user: @defunkt)

    example_repo :defunkt_facebox, @facebox
    example_repo :mojombo_grit, @grit
  end

  context "query params" do
    test "it will only query commits" do
      assert_equal("commit", @query.query_params[:type])
    end

    test "generates routing information" do
      @query.phrase = "search @defunkt @mojombo/grit"
      assert_equal("#{@grit.id},#{@facebox.id}", @query.query_params[:routing])
    end

    test "generates no routing information for global queries" do
      query = Search::Queries::CommitQuery.new(current_user: @twp, phrase: "search")
      assert_nil query.routing
    end

    test "does not fail over unknown merge boolean value" do
      @query.phrase = "merge:no"
      expected = { constant_score: { filter: {
        bool: { must: [
          { term: { is_merge: false } },
          { term: { public: true } },
        ], must_not: { term: { is_commit_state_doc: true } } },
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

      # Qualifiers
      author_query = Search::Queries::CommitQuery.new(phrase: "foo author:#{private_user}", current_user: private_user)
      # CommitQuery doesn't use UserFilter, so it doesn't invalidate the query
      # So we have to dig into the query to see if it has the filter clause
      assert author_query.query_doc.dig(:bool, :must).any? { |clause| clause.dig(:term, :author_id) == private_user.id }

      committer_query = Search::Queries::CommitQuery.new(phrase: "foo committer:#{private_user}", current_user: private_user)
      # CommitQuery doesn't use UserFilter, so it doesn't invalidate the query
      # So we have to dig into the query to see if it has the filter clause
      assert committer_query.query_doc.dig(:bool, :must).any? { |clause| clause.dig(:term, :committer_id) == private_user.id }

      user_query = Search::Queries::CommitQuery.new(phrase: "foo user:#{private_user}", current_user: private_user)
      assert_predicate user_query, :valid_query?

      org_query = Search::Queries::CommitQuery.new(phrase: "foo org:#{private_user}", current_user: private_user)
      assert_predicate org_query, :valid_query?

      owner_query = Search::Queries::CommitQuery.new(phrase: "foo owner:#{private_user}", current_user: private_user)
      assert_predicate owner_query, :valid_query?

      # No qualifier, just the user login
      text_query = Search::Queries::CommitQuery.new(phrase: private_user.login, current_user: private_user)
      assert_predicate text_query, :valid_query?
    end

    test "filtering by private profile user when viewer is not the user" do
      enable_feature_flag(:invalidate_private_profile_searches)
      private_user = create(:user, private_profile: true)
      # Repo for `user:` searches
      create(:repository, owner: private_user)
      viewer = create(:user)

      # Qualifiers
      author_query = Search::Queries::CommitQuery.new(phrase: "foo author:#{private_user}", current_user: viewer)
      # CommitQuery doesn't use UserFilter, so it doesn't invalidate the query
      # So we have to dig into the query to see if it has the filter clause
      refute author_query.query_doc.dig(:bool, :must)&.any? { |clause| clause.dig(:term, :author_id) == private_user.id }

      committer_query = Search::Queries::CommitQuery.new(phrase: "foo committer:#{private_user}", current_user: viewer)
      # CommitQuery doesn't use UserFilter, so it doesn't invalidate the query
      # So we have to dig into the query to see if it has the filter clause
      refute committer_query.query_doc.dig(:bool, :must)&.any? { |clause| clause.dig(:term, :committer_id) == private_user.id }

      user_query = Search::Queries::CommitQuery.new(phrase: "foo user:#{private_user}", current_user: viewer)
      refute_predicate user_query, :valid_query?

      org_query = Search::Queries::CommitQuery.new(phrase: "foo org:#{private_user}", current_user: viewer)
      refute_predicate org_query, :valid_query?

      owner_query = Search::Queries::CommitQuery.new(phrase: "foo owner:#{private_user}", current_user: viewer)
      refute_predicate owner_query, :valid_query?

      # No qualifier, just the user login
      text_query = Search::Queries::CommitQuery.new(phrase: private_user.login, current_user: private_user)
      assert_predicate text_query, :valid_query?
    end
  end

  context "valid query" do
    test "empty phrase query returns not valid query" do
      query = Search::Queries::CommitQuery.new(current_user: @twp, phrase: " ")
      refute_predicate query, :valid_query?
    end

    test "phrase query returns valid query" do
      query = Search::Queries::CommitQuery.new(current_user: @twp, phrase: "test is:public")
      assert_predicate query, :valid_query?
    end
  end
end
