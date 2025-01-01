# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gist_controller_helpers"

class GistsStatelessControllerHttpTest < GitHub::IntegrationTestCase
  include GistsControllerTestHelpers
  extend GistsControllerTestSetup

  fixtures &fixtures_block
  setup &global_setup_block

  context "show page" do
    test "renders a JSON embed when requested with JS format" do
      gist = GistHelpers.generate contents: @create_contents

      get "#{gist_url_for(gist)}.json"

      assert_response :success
      assert_equal "application/json", response.media_type

      response = JSON.parse @response.body
      assert_equal %w(description public created_at files owner div stylesheet),
                   response.keys

      assert_includes response["div"], "Hello!"
      assert_match %r{gist\-embed-\w+\.css}, response["stylesheet"]
      assert response["stylesheet"].starts_with?("http"), "expected direct link to stylesheet"
    end

    test "supports showing a specific file for JSON embeds" do
      gist = GistHelpers.generate contents: [
        { name: "file1.txt", value: "contents1" },
        { name: "file2.txt", value: "contents2" },
      ]

      get "#{gist_url_for(gist)}.json", params: { file: "file2.txt" }

      response = JSON.parse @response.body
      assert_equal %w(description public created_at files owner div stylesheet),
                   response.keys

      assert_equal %w(file2.txt), response["files"]
      assert_includes response["div"], "contents2"
      refute_includes response["div"], "contents1"
    end

    test "renders a JSONP embed when requested with JS format" do
      gist = GistHelpers.generate contents: @create_contents

      get "#{gist_url_for(gist)}.json", params: { callback: "myCallback" }

      assert_response :success
      assert_equal "application/javascript", response.media_type

      assert @response.body.starts_with?("/**/myCallback(")
      assert_includes response.body, "Hello!"
      assert_match %r{gist\-embed-\w+\.css}, response.body
    end

    test "supports showing a specific file for JSONP embeds" do
      gist = GistHelpers.generate contents: [
        { name: "file1.txt", value: "contents1" },
        { name: "file2.txt", value: "contents2" },
      ]

      get "#{gist_url_for(gist)}.json", params: { callback: "myCallback", file: "file2.txt" }

      assert_includes response.body, "contents2"
      refute_includes response.body, "contents1"
    end
  end
end
