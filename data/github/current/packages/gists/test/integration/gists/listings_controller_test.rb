# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gist_controller_helpers"

class GistsListingsControllerHttpTest < GitHub::IntegrationTestCase

  skip_in_multitenant_mode

  include GistsControllerTestHelpers
  extend GistsControllerTestSetup

  fixtures &fixtures_block
  setup &global_setup_block

  context "discover gists page" do
    test "renders" do
      get "/gist/discover"

      assert_response :success
      assert_template "gists/listings/discover"
    end

    test "atom requests are rendered" do
      get "/gist/discover.atom"

      assert_response :success
      assert_template "gists/listings/feed"
      assert_equal "application/atom+xml", response.media_type
      assert_match "<title>Public Gists</title>", response.body
    end

    test "handles timeout errors" do
      Gist.any_instance.stubs(:title).raises(ApplicationHelper::GitTemplateTimeout)

      get "/gist/discover"

      assert_response :success
      assert_includes response.body, "Timeout rendering snippet for #{@pub_user.display_login}"
    end

    test "handles timeout errors that occur inside a git rpc" do
      # Simulate the bertrpc/gitrpc wrap/unwrap/wrap sequence:
      # 1. BertRPC captures the timeout exception in `send_message`, wraps it and encodes it
      exception = GitRPC::Failure.wrap(ApplicationHelper::GitTemplateTimeout.new("boom")).encode
      # 2. GitRPC receives the wrapped exception as a return value, decodes it back into an
      #    exception and re-wraps it in order to raise it
      exception = GitRPC::Failure.wrap(GitRPC::Failure.decode(exception))

      GitRPC::Backend.any_instance.stubs(:send_message).raises(exception)

      get "/gist/discover"

      assert_response :success
      assert_includes response.body, "Timeout rendering snippet for #{@pub_user.display_login}"
    end


    test "contains meta descriptions" do
      get "/gist/discover"

      descriptions = assert_select("meta[name='description']")
      assert_equal 1, descriptions.size

      description = descriptions.first
      assert_match("GitHub Gist", description["content"])

      og_description = assert_select("meta[property='og:description']").first
      assert_match("GitHub Gist", og_description["content"])
    end

    test "404s when requested with the unknown format" do
      get "gist/discover.php"
      assert_response :not_found
    end
  end

  context "forked gists page" do
    test "renders" do
      @pub_gist.fork @priv_user

      get "/gist/forked"

      assert_response :success
      assert_template "gists/listings/discover"
    end

    test "atom requests are rendered" do
      get "/gist/forked.atom"

      assert_response :success
      assert_template "gists/listings/feed"
      assert_equal "application/atom+xml", response.media_type
      assert_match "<title>Forked Gists</title>", response.body
    end

    test "handles timeout errors" do
      @pub_gist.fork @priv_user
      Gist.any_instance.stubs(:title).raises(ApplicationHelper::GitTemplateTimeout)

      get "/gist/forked"

      assert_response :success
      assert_includes response.body, "Timeout rendering snippet for #{@pub_user.display_login}"
    end

    test "404s when requested with the unknown format" do
      get "gist/forked.php"
      assert_response :not_found
    end
  end

  context "starred gists page" do
    test "renders" do
      get "/gist/starred"

      assert_response :success
      assert_template "gists/listings/discover"
    end

    test "atom requests are rendered" do
      get "/gist/starred.atom"

      assert_response :success
      assert_template "gists/listings/feed"
      assert_equal "application/atom+xml", response.media_type
      assert_match "<title>Starred Gists</title>", response.body
    end

    test "handles timeout errors" do
      @priv_user.star(@pub_gist)
      Gist.any_instance.stubs(:title).raises(ApplicationHelper::GitTemplateTimeout)

      get "/gist/starred"

      assert_response :success
      assert_includes response.body, "Timeout rendering snippet for #{@pub_user.display_login}"
    end

    test "404s when requested with the unknown format" do
      get "gist/starred.php"
      assert_response :not_found
    end
  end

  context "legacy redirects" do
    test "/mine" do
      get "/gist/mine"
      assert_response 302
      assert_redirected_to "http://github.com/gist"

      as @pub_user
      get "/gist/mine"
      assert_response 302
      assert_redirected_to "http://github.com/gist/#{@pub_user.to_param}"
    end

    test "/my_forked" do
      get "/gist/mine/forked"
      assert_response 302
      assert_redirected_to "http://github.com/gist"

      as @pub_user
      get "/gist/mine/forked"
      assert_response 302
      assert_redirected_to "http://github.com/gist/#{@pub_user.to_param}/forked"
    end

    test "/my_starred" do
      get "/gist/mine/starred"
      assert_response 302
      assert_redirected_to "http://github.com/gist"

      as @pub_user
      get "/gist/mine/starred"
      assert_response 302
      assert_redirected_to "http://github.com/gist/#{@pub_user.to_param}/starred"
    end
  end
end
