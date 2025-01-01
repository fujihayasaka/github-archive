# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gist_controller_helpers"

class GistsSearchesControllerHttpTest < GitHub::IntegrationTestCase

  skip_in_multitenant_mode

  include GistsControllerTestHelpers
  extend GistsControllerTestSetup

  fixtures do
    setup_search
    instance_eval(&self.class.fixtures_block)

    @starred_gist = GistHelpers.generate(user: @priv_user,
      contents: @create_contents,
      description: "Can't believe it's not butter.")
    @pub_user.star(@starred_gist)

    make_searchable(@pub_gist, @starred_gist)
  end

  setup do
    instance_eval(&self.class.global_setup_block)

    as @pub_user
  end

  teardown_once do
    teardown_search
  end

  context "GET /search" do
    test "renders the new search page when no query is passed" do
      get "/gist/search"

      assert_response :success
      assert_template "gists/searches/new"
    end

    test "renders the results page when a query is passed" do
      get "/gist/search", params: { q: "foo" }

      assert_response :success
      assert_template "gists/searches/show"
    end

    test "renders the 404 above pagination limit" do
      get "/gist/search", params: { q: "foo", p: 100 }

      assert_response :success

      get "/gist/search", params: { q: "foo", p: 101 }

      assert_response :not_found
    end

    test "shows the search results" do
      get "/gist/search", params: { q: "butter" }

      assert_response :success
      assert_includes response.body, @pub_gist.title
    end

    test "disable xhr requests" do
      get "/gist/search", params: { q: "butter" }, xhr: true

      assert_response :not_acceptable
    end
  end

  context "GET /search/quick" do
    test "renders the search results" do
      get "/gist/search/quick", params: { q: "butter" }, xhr: true

      assert_response :success
      assert_template "gists/searches/quick"

      assert_select ".gist-quicksearch-result-group", count: 2 do |elements|
        assert_select elements.first, "h2", count: 1, text: "Starred"

        assert_select elements.first, "div", count: 1, text: /#{@starred_gist.name_with_title}/
        assert_select elements.last, "h2", count: 1, text: "Yours"
        assert_select elements.last, "div", count: 1, text: /#{@pub_gist.name_with_title}/
      end
    end

    test "requires xhr requests" do
      get "/gist/search/quick", params: { q: "butter" }

      assert_response :not_acceptable
    end

    test "requires auth" do
      post "/logout"

      get "/gist/search/quick", params: { q: "butter" }, xhr: true

      assert_response :unauthorized
    end
  end

  context "quicksearch" do
    test "is enabled if the user is logged in" do
      get "/gist"

      assert_response :success

      if !GitHub.flipper[:gist_header_a11y_quicksearch].enabled?
        assert_includes response.body, "data-quicksearch-url=\"/gist/search/quick\""
      end
    end

    test "is disabled if the user is NOT logged in" do
      post "/logout"

      get "/gist"
      follow_redirect! if response.redirect?

      assert_response :success
      refute_includes response.body, "data-quicksearch-url=\"/gist/search/quick\""
    end
  end
end
