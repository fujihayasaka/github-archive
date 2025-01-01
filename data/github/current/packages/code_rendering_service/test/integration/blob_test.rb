# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gist_controller_helpers"
require "test_helpers/viewscreen_helpers"

## TODO: I am kind of just dumping integration tests in here, we may want to move them around to
# better organize them based on the page in github ie gists, diffs etc. We also will need to look at
# the GRAPHQL and API responses and make sure they are consistent. Render is really under tested which makes
# me nervous.
class ViewScreenBlobShowIntegrationTest < GitHub::IntegrationTestCase
  include GistsControllerTestHelpers
  include GitHub::ReactPayloadHelper

  fixtures do
    @org  = create(:organization)
    @user = create(:user, login: "defunkt")

    @repo = create(:repository, owner: @org)

  end

  setup do
    example_repo :post_receive_job_test, @repo
    GitHub.flipper[:notifications_async_gist_subscription_button].disable
  end

  def viewscreen_url(file_type, type = "view")
    if GitHub.enterprise?
      "https://github.com/viewscreen/#{type}/#{file_type}?"
    elsif TestEnv.test_in_multitenancy_mode?
      "https://viewscreen.#{GitHub::CurrentTenant.get&.slug}.github.com/#{type}/#{file_type}?"
    else
      "https://viewscreen.githubusercontent.com/#{type}/#{file_type}?"
    end
  end

  def notebooks_url(file_type, type = "view")
    if GitHub.enterprise?
      "https://github.com/notebooks/#{type}/#{file_type}?"
    elsif TestEnv.test_in_multitenancy_mode?
      "https://notebooks.#{GitHub::CurrentTenant.get&.slug}.github.com/#{type}/#{file_type}?"
    else
      "https://notebooks.githubusercontent.com/#{type}/#{file_type}?"
    end
  end

  context "show pages displays the iframe on the blob show page for all supported formats" do
    test "pdf" do
      ViewscreenHelper.set_flags
      @ref = @repo.heads.find_or_build("master")
      @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
        files.add("foo.pdf", "")
      end

      as @user
      get "/#{@repo.name_with_display_owner}/blob/master/foo.pdf"

      assert_response :ok

      assert_react_payload_match [:blob, :displayUrl], viewscreen_url("pdf")
      assert_react_payload_equal [:blob, :renderedFileInfo, :renderFileType], "pdf"
    end

    test "geojson" do
      ViewscreenHelper.set_flags

      @ref = @repo.heads.find_or_build("master")
      @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
        files.add("feature.geojson", '{"type": "FeatureCollection"}')
      end

      as @user
      get "/#{@repo.name_with_display_owner}/blob/master/feature.geojson"

      assert_react_payload_match [:blob, :displayUrl], viewscreen_url("geojson")
      assert_react_payload_equal [:blob, :renderedFileInfo, :renderFileType], "geojson"
    end

    test "solid" do
      ViewscreenHelper.set_flags
      @ref = @repo.heads.find_or_build("master")
      @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
        files.add("foo.stl", "SOLID test\nENDSOLID test\n")
      end
      as @user
      get "/#{@repo.name_with_display_owner}/blob/master/foo.stl"

      assert_react_payload_match [:blob, :displayUrl], viewscreen_url("solid")
      assert_react_payload_equal [:blob, :renderedFileInfo, :renderFileType], "solid"
    end

    test "svg" do
      ViewscreenHelper.set_flags
    end
  end

  test "it does not show the notebook iframe for jupyter notebooks when notebook feature flag is on" do
    ViewscreenHelper.set_flags
    @ref = @repo.heads.find_or_build("master")
    @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
      files.add("foo.ipynb", "notebook")
    end
    as @user
    get "/#{@repo.name_with_display_owner}/blob/master/foo.ipynb"
    assert_react_payload_match [:blob, :displayUrl], notebooks_url("ipynb")
  end

  context "Commit page" do
    # https://github.com/github/renderables/commit/c120bc2fd6a1c1509933f9af7f23f04cc7d7e5cd?short_path=29b7830#diff-29b78307f1fd45199fa669f9c51e294783c311e3f4f3b24b24435b902a773fa8
  end

  context "images" do
    # github/renderables@cc410c2?short_path=29b7830#diff-29b78307f1fd45199fa669f9c51e294783c311e3f4f3b24b24435b902a773fa8
  end

  context "gist show page displays the iframe on the blob show page for all supported formats" do

    # it seems implausible that someone could create a jpg, psd, or stl file via the
    # gist textbox, so these formats, while possible, are untested.

    test "svg", skip_in_multitenant_mode: true do
      ViewscreenHelper.set_flags
      @gist = GistHelpers.generate user: @user,
        contents: [{ name: "foo.svg", value: '<svg xmlns="http://www.w3.org/2000/svg"/>' }]

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@user, @gist)
      end

      as @user
      with_cache_enabled do
        get gist_url_for(@gist)
      end

      assert_response :ok

      assert_select ".render-viewer" do |el|
        assert_includes el.first["src"], viewscreen_url("svg")
      end
    end

    # topojson is identical to geojson

    test "geojson", skip_in_multitenant_mode: true do
      ViewscreenHelper.set_flags
      @gist = GistHelpers.generate user: @user,
        contents: [{ name: "foo.geojson", value: "{}" }]

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@user, @gist)
      end

      as @user
      with_cache_enabled do
        get gist_url_for(@gist)
      end

      assert_response :ok

      assert_select ".render-viewer" do |el|
        assert_includes el.first["src"], viewscreen_url("geojson")
      end
    end

    test "ipynb", skip_in_multitenant_mode: true do
      ViewscreenHelper.set_flags
      @gist = GistHelpers.generate user: @user,
        contents: [{ name: "foo.ipynb", value: "{}" }]

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@user, @gist)
      end

      as @user
      with_cache_enabled do
        get gist_url_for(@gist)
      end

      assert_response :ok

      assert_select ".render-viewer" do |el|
        assert_includes el.first["src"], notebooks_url("ipynb")
      end
    end

    # For EMUs, the Gist user page will always 404, so we don't need to test blob rendering
    test "users home page", skip_with_all_emus: true do
      ViewscreenHelper.set_flags
      @gist = GistHelpers.generate user: @user,
        contents: [{ name: "foo.ipynb", value: "{}" }]

      @gist = GistHelpers.generate user: @user,
        contents: [{ name: "foo.geojson", value: "{}" }]

      @gist = GistHelpers.generate user: @user,
        contents: [{ name: "foo.md", value: "# Hello world" }]
      as @user

      with_cache_enabled do
        get "gist/#{@user.display_login}"
      end

      assert_response :ok

      assert_select ".render-viewer" do |el|
        assert_includes el.first["src"], viewscreen_url("geojson")
        assert_includes el.last["src"], notebooks_url("ipynb")
      end
    end

    test "404 for EMUs and multi-tenant" do
      ViewscreenHelper.set_flags
      gist = GistHelpers.generate user: @user,
        contents: [{ name: "foo.ipynb", value: "{}" }]

      as @user
      with_cache_enabled do
        get "gist/#{@user.display_login}"
      end

      assert_response :not_found
    end if TestEnv.test_in_multitenancy_mode? || TestEnv.test_with_all_emus?
  end

  context "edit preview" do
    test "shows a render iframe for geojson previewing" do
      ViewscreenHelper.set_flags
      as @user
      new_geojson = %{
  {
      "type": "Point",
      "coordinates": [-97, 30]
  }
}

      @ref = @repo.heads.find_or_build("master")
      @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
        files.add("foo.geojson", "")
      end

      post "/#{@repo.name_with_display_owner}/preview/master/foo.geojson", params: { code: new_geojson, blobname: "foo.geojson" }

      assert_response :success
      html = @response.body
      assert html =~ /iframe/, "Should contain an iframe for render"
      assert_select ".render-viewer" do |el|
        assert_includes el.first["src"], viewscreen_url("geojson")
      end

    end

    test "does not show render iframe for stl previewing" do
      ViewscreenHelper.set_flags
      as @user
      new_stl = %{
  solid name
    facet normal 0.0 -1.0 0.0
      outer loop
        vertex 0.0 0.0 0.0
        vertex 50.0 0.0 0.0
        vertex 0.0 0.0 50.0
      endloop
    endfacet
  endsolid
  }

      @ref = @repo.heads.find_or_build("master")
      @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
        files.add("foo.stl", "")
      end

      post "/#{@repo.name_with_display_owner}/preview/master/foo.stl", params: { code: new_stl, blobname: "foo.stl" }

      assert_response :success
      html = @response.body
      assert html !~ /iframe/, "Should not contain an iframe for render"
    end
  end
end
