# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/viewscreen_helpers"

class Notebook::ViewComponentTest < GitHub::TestCase
  fixtures do
    @org  = create(:organization)
    @user = create(:user, login: "defunkt")
    @repo = create(:repository, owner: @org)
    disable_feature_flag(:notebooks_bypass_fastly, @repo)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
    @ref = @repo.heads.find_or_build("master")
    @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
      files.add("foo.ipynb", "")
    end
    @blob = @repo.blob(@ref.sha, "foo.ipynb")
  end

  test "host_url uses the tenant-relative host in proxima", skip_enterprise: true do
    emu_user = create :emu
    emu_business = emu_user.enterprise_managed_business
    on_multi_tenant_enterprise(tenant: emu_business) do
      GitHub.stubs(:deployed_to).returns("cool-proxima-stamp")
      GitHub.stubs(:host_name).returns("ghe.com")

      notebook = CodeRenderingService.for(@blob, :view, @user, @repo)

      assert_equal notebook.host_url, "https://notebooks.#{emu_business.slug}.ghe.com"
    end
  end

  context "host_url supports dev lab" do
    if !GitHub.enterprise?
      old = GitHub.employee_unicorn?

      [ #is_lab  expected_url
        [false, "://notebooks.githubusercontent.com"],
        [true, "://notebooks-lab.service.iad.github.net"]
      ].each do |is_lab, url|
        test "where lab = #{is_lab}" do
          ViewscreenHelper.set_flags
          notebook = CodeRenderingService.for(@blob, :view, @user, @repo)
          begin
            GitHub.employee_unicorn = is_lab
            assert notebook.host_url.ends_with?(url)
          ensure
            GitHub.employee_unicorn = old
          end
        end
      end
    else
      test "when in enterprise" do
        ViewscreenHelper.set_flags
        notebook = CodeRenderingService.for(@blob, :view, @user, @repo)
        begin
          GitHub.employee_unicorn = false
          assert notebook.host_url.include?("/notebooks")
        ensure
          GitHub.employee_unicorn = false
        end
      end
    end
  end

  context "it properly identifies supported views" do
    test "can support the ipynb view" do
      ViewscreenHelper.set_flags
      blob = @repo.blob(@ref.sha, "foo.ipynb")
      vs = CodeRenderingService.for(blob, :view, @user, @repo)
      assert vs.class == Notebook::ViewComponent
      assert vs.supports_view?
      assert vs.render_type == :ipynb
    end
  end

  test "creates proper urls for blob views" do
    ViewscreenHelper.set_flags

    # Could not get this working properly with minitest, and stubbing `request` seemed like a huge pain
    useragent =
      Class.new do
        define_method(:id) { "chrome" }
        define_method(:version) { "67" }
        define_method(:platform) { Class.new { define_method(:id) { "mac" } }.new }
        define_method(:device) { Class.new { define_method(:id) { "unknown_device" } }.new }
      end.new

    notebook = CodeRenderingService.for(@blob, :view, @user, @repo, opts: { parsed_useragent: useragent })

    url = notebook.url_for_display(commit_oid: @blob.sha)
    query = Rack::Utils.parse_query(url.query)

    assert_equal query["nwo"], @repo.nwo
    assert_includes query["commit"], @blob.sha
    assert_includes query["repository_type"], @repo.class.name
    assert_includes query["browser"], useragent.id
    assert_includes query["version"], useragent.version
    assert_includes query["device"], useragent.device.id
    assert_includes query["platform"], useragent.platform.id
    refute_includes query.keys, "bypass_fastly"

    content_url = TreeEntryRenderHelper.raw_blob_url(@user, @repo, @blob.sha, "foo.ipynb", expires_key: :render, host: GitHub.render_raw_host_name)

    assert_includes decode_url(query["enc_url"]), content_url

    if !GitHub.enterprise?
      enable_feature_flag(:notebooks_bypass_fastly, @repo)
      notebook = CodeRenderingService.for(@blob, :view, @user, @repo, opts: { parsed_useragent: useragent })
      url = notebook.url_for_display(commit_oid: @blob.sha)
      query = Rack::Utils.parse_query(url.query)
      assert_equal query["bypass_fastly"], "true"
    end
  end

  context "it creates proper urls for gists" do
    test "it includes correct urls for gists" do
      gist = GistHelpers.generate(
        user: @user,
        contents: [{
          name: "points.ipynb",
          value: "Some notebook code"
        }],
        description: "Public gist"
      )
      ViewscreenHelper.set_flags
      blob = gist.blob(gist.sha, "points.ipynb")
      vs =  CodeRenderingService.for(blob, :view, @user, gist)
      url = vs.url_for_display(commit_oid: gist.sha)
      content_url = TreeEntryRenderHelper.raw_gist_url(@user, blob.repository, gist.sha, "points.ipynb")
      query = Rack::Utils.parse_query(url.query)
      assert_includes decode_url(query["enc_url"]), content_url
    end

    test "it includes correct urls for gists when current repository is nil" do
      gist = GistHelpers.generate(
        user: @user,
        contents: [{
          name: "points.ipynb",
          value: "Some notebook code"
        }],
        description: "Public gist"
      )
      ViewscreenHelper.set_flags
      blob = gist.blob(gist.sha, "points.ipynb")
      vs =  CodeRenderingService.for(blob, :view, @user)
      url = vs.url_for_display(commit_oid: gist.sha)
      content_url = TreeEntryRenderHelper.raw_gist_url(@user, blob.repository, gist.sha, "points.ipynb")
      query = Rack::Utils.parse_query(url.query)
      assert_includes decode_url(query["enc_url"]), content_url
    end
  end

  def decode_url(url)
    [url].pack("H*").force_encoding("UTF-8")
  end
end
