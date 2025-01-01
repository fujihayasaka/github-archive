# typed: true
# frozen_string_literal: true

require "test_helper"

class Search::Queries::CommandPalette::RepoQueryTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
  end

  def build_query_doc(phrase)
    query_service = Search::Queries::CommandPalette::RepoQuery.new
    query_service.phrase = phrase
    query_service.build_query
  end

  def assert_fields(phrase, expected_fields)
    query_doc = build_query_doc(phrase)
    query_string = query_doc.dig(:bool, :must, :function_score, :query, :query_string)

    refute_nil query_string, "No query string found within: #{query_doc}"
    assert_equal expected_fields, query_string[:fields]
  end

  context "#query_fields" do
    test "searches within a set of default fields" do
      assert_fields("foo", %w[name^1.2 name.camel name.ngram^0.8 description^0.5])
    end

    test "queries containing a `/` search against name_with_owner" do
      assert_fields("github/foo", %w[name^1.2 name.camel name.ngram^0.8 description^0.5 name_with_owner])
    end

    test "searching within specific fields" do
      assert_fields("in:name foo", %w[name^1.2 name.camel name.ngram^0.8 name_with_owner])
      assert_fields("in:description foo", %w[description])
      assert_fields("in:readme foo", %w[readme])
    end
  end

  context "query_doc" do
    test "doesn't use a score function" do
      query_doc = build_query_doc("foo")
      function_score_functions = query_doc.dig(:bool, :must, :function_score, :functions)

      assert_empty function_score_functions
    end
  end
end
