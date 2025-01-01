# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gist_controller_helpers"

class GistsControllerCreateGistHttpTest < GitHub::IntegrationTestCase
  include GistsControllerTestHelpers
  extend GistsControllerTestSetup

  skip_with_all_emus

  fixtures(&fixtures_block)
  setup(&global_setup_block)

  context "create a gist" do
    test "works" do
      as @pub_user

      assert_difference "Gist.count" do
        post "gist", params: { gist: { "contents" => @contents, "public" => "0" } }
      end

      assert_response 302
    end

    test "works for an anonymous user" do
      GitHub.override(:anonymous_gist_creation_enabled, true) do
        assert_difference "Gist.count" do
          post "gist", params: { gist: { "contents" => @contents, "public" => "1" } }
        end

        assert_response 302
      end
    end

    test "creating a gist without specifying a filename" do
      as @pub_user

      contents_with_no_name = [{ "name" => "", "value" => "### HEADER" }]

      assert_difference "Gist.count" do
        post "gist", params: { gist: { "contents" => contents_with_no_name, "public" => "0" } }
      end

      assert_response 302
    end

    test "creating a secret gist" do
      as @pub_user

      post "gist", params: { gist: { "public" => 0, "contents" => @contents } }

      repo_name = @response.location.split("/").last
      gist = Gist.find_by_repo_name!(repo_name)
      assert gist.secret?
    end

    test "creating a secret does not work if user is trade restricted" do
      @pub_user.trade_controls_restriction.full!

      as @pub_user

      post "gist", params: { gist: { "public" => 0, "contents" => @contents } }

      assert_includes response.body, TradeControls::Notices.notice_as_plaintext(:billing_account_restricted)
    end

    test "creating a public gist" do
      as @pub_user

      post "gist", params: { gist: { "public" => 1, "contents" => @contents } }

      repo_name = @response.location.split("/").last
      gist = Gist.find_by_repo_name!(repo_name)
      assert gist.public?
    end

    test "creating a gist without specifying filename gets correct default title" do
      as @pub_user

      post "gist", params: { gist: { "public" => 0, "contents" => @contents } }

      repo_name = @response.location.split("/").last
      gist = Gist.find_by_repo_name!(repo_name)
      error_text =  "If you changed the default_title for gists, please update the title "\
                    "regex in app/assets/modules/github/google-analytics-overrides.js in the pageTitle() method. " \
                    "This avoids leaking secret Gist IDs to Google Analytics"
      assert_equal gist.send(:default_title), "gist:#{repo_name}", error_text
    end

    test "creating a gist with an invalid public value" do
      as @pub_user

      post "gist", params: { gist: { "public" => "cheese", "contents" => @contents } }

      repo_name = @response.location.split("/").last
      gist = Gist.find_by_repo_name!(repo_name)
      refute gist.secret?, "Expected gist.secret? to be false, but it was #{gist.secret?}"
    end

    test "creating a gist without specifying a public value defaults to secret" do
      as @pub_user

      post "gist", params: { gist: { "contents" => @contents } }

      repo_name = @response.location.split("/").last
      gist = Gist.find_by_repo_name!(repo_name)
      assert gist.secret?
    end

    test "creating a gist with two files (specifying filename)" do
      as @pub_user

      contents = @contents + [{ "name" => "foobar.md", "value" => "### FOOTER YO" }]

      post "gist", params: { gist: { "public" => 1, "contents" => contents } }

      repo_name = @response.location.split("/").last
      gist = Gist.find_by_repo_name!(repo_name)
      assert_equal 2, gist.files.count
    end

    test "creating a gist with two files (no filenames)" do
      as @pub_user

      contents = [{ "name" => "", "value" => "### HEADER YO" },
                      { "name" => "", "value" => "### FOOTER YO" }]

      post "gist", params: { gist: { "public" => 1, "contents" => contents } }

      repo_name = @response.location.split("/").last
      gist = Gist.find_by_repo_name!(repo_name)
      assert_equal 2, gist.files.count

      names = gist.files.map(&:name)
      assert_includes names, "gistfile1.txt"
      assert_includes names, "gistfile2.txt"
    end

    test "replacing newlines from a form POST" do
      as @pub_user

      contents = [{ "name" => "", "value" => "with some newlines \r\n" }]

      post "gist", params: { gist: { "public" => 1, "contents" => contents } }

      repo_name = @response.location.split("/").last
      gist = Gist.find_by_repo_name!(repo_name)
      content = gist.files[0].data

      assert_equal(content, "with some newlines \n")
    end

    test "ignore whitespace in filenames" do
      as @pub_user

      contents = [{ "name" => " leading.rb", "value" => "stuff!" },
                  { "name" => "trailing.rb ", "value" => "more stuff!" },
                  { "name" => " both.rb ", "value" => "even more stuff!" }]
      post "gist", params: { gist: { "public" => 1, "contents" => contents } }

      repo_name = @response.location.split("/").last
      gist = Gist.find_by_repo_name!(repo_name)
      assert_equal 3, gist.files.count

      names = gist.files.map(&:name).sort
      assert_equal ["both.rb", "leading.rb", "trailing.rb"], names
    end

    [".git", ".GIT", ".", ".."].each do |bad_filename|
      test "creating a gist with the filename #{bad_filename} fails" do
        as @pub_user

        contents = [{ "name" => bad_filename, "value" => "#{bad_filename} test" }]

        post "gist", params: { gist: {
          "description" => "My description!",
          "contents" => contents,
          "public" => "1",
        } }

        assert_select ".flash.flash-error",
        /Whoops, files can't contain malformed path components./
      end
    end

    test "shows errors about why creation failed" do
      as @pub_user

      desc_that_is_too_long = "漢" * 2048
      post "gist", params: { gist: {
        "description" => desc_that_is_too_long,
        "contents" => @contents,
        "public" => "1",
      } }
      assert_select ".flash.flash-error", "Description is too long (maximum is 256 characters)"
    end

    test "failed creation doesn't lose user content" do
      as @pub_user

      @contents[0]["value"] = "NEW-VALUE"

      desc_that_is_too_long = "漢" * 2048
      post "gist", params: { gist: {
        "description" => desc_that_is_too_long,
        "contents" => @contents,
        "public" => "1",
      } }

      assert_select ".flash.flash-error", "Description is too long (maximum is 256 characters)"

      assert_includes response.body, "NEW-VALUE"
    end
  end
end
