# typed: true
# frozen_string_literal: true
require "test_helper"
require "test_helpers/viewscreen_helpers"

class Viewscreen::ViewComponentTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @org  = create(:organization)
    @user = create(:user, login: "defunkt")
    @repo = create(:repository, owner: @org)

    @render_types = {
      geojson: :geojson,
      stl: :solid,
      pdf: :pdf,
      topojson: :topojson,
      svg: :svg,
      jpg: :img,
      psd: :psd,
      mermaid: :mermaid,
      mmd: :mermaid
    }
    example_repo_snapshot
  end

  setup do
    example_repo_restore

    @ref = @repo.heads.find_or_build("master")
    @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
      files.add("foo.pdf", "")
      files.add("foo.svg", "")
      files.add("foo.geojson", '{"type": "FeatureCollection"}')
      files.add("foo.topojson", '{"type": "FeatureCollection"}')
      files.add("foo.stl", "SOLID test\nENDSOLID test\n")
      files.add("foo.ipynb", "notebook")
      files.add("foo.js", "")
      files.add("foo.jpg", "")
      files.add("foo.psd", "")
      files.add("foo.mermaid", "")
      files.add("foo.mmd", "")
    end
    @blob = @repo.blob(@ref.sha, "foo.svg")
  end

  test "host_url uses the stamp-relative host in proxima", skip_enterprise: true do
    emu_user = create :emu
    emu_business = emu_user.enterprise_managed_business
    on_multi_tenant_enterprise(tenant: emu_business) do
      GitHub.stubs(:deployed_to).returns("cool-proxima-stamp")
      GitHub.stubs(:host_name).returns("ghe.com")

      vs = CodeRenderingService.for(@blob, :view, @user, @repo)

      assert_equal vs.host_url, "https://viewscreen.#{emu_business.slug}.ghe.com"
    end
  end

  if GitHub.enterprise?
    test "supports views" do
      view = :view

      blob = @repo.blob(@ref.sha, "foo.stl")

      vs = CodeRenderingService.for(blob, view, @user, @repo)
      assert vs.supports_view?, "Expected #{vs.class} to support #{view}"
      assert vs.render_type == :solid, "Expected #{vs.render_type} to be :solid"
    end

    test "uses the github hostname in the iframe url" do
      view = :view

      blob = @repo.blob(@ref.sha, "foo.stl")
      vs = CodeRenderingService.for(blob, view, @user, @repo)
      refute_predicate GitHub, :subdomain_isolation?
      assert_match %r|\Ahttps://github\.com/viewscreen/view/solid\?|, vs.url_for_display(commit_oid: "00decaf").to_s
    end
  end

  if !GitHub.enterprise?
    context "it properly identifies supported views" do
      Viewscreen::ViewComponent::SUPPORTED_VIEWS.keys.each do |file_type|
        Viewscreen::ViewComponent::SUPPORTED_VIEWS[file_type].each do |view|
          test "can support the #{file_type} #{view}" do
            ViewscreenHelper.set_flags

            file_type = normalize_file_type(file_type)

            blob = @repo.blob(@ref.sha, "foo.#{file_type}")
            vs = CodeRenderingService.for(blob, view, @user, @repo)
            assert vs.class == Viewscreen::ViewComponent
            assert vs.supports_view?
            assert vs.render_type == @render_types[file_type]
          end
        end
      end
    end

    context "host_url supports dev lab" do
      old = GitHub.employee_unicorn?

      [ #is_lab  expected_url
        [true, "://viewscreen-lab.service.iad.github.net"],
        [false, "://viewscreen.#{GitHub.user_content_host_name}"]
      ].each do |is_lab, url|
        test "where lab = #{is_lab}" do
          ViewscreenHelper.set_flags
          vs = CodeRenderingService.for(@blob, :view, @user, @repo)
          begin
            GitHub.employee_unicorn = is_lab
            assert vs.host_url.ends_with?(url)
          ensure
            GitHub.employee_unicorn = old
          end
        end
      end
    end

    context "view url creation" do
      test "uses the viewscreen subdomain in the iframe url" do
        view = :view

        blob = @repo.blob(@ref.sha, "foo.stl")
        vs = CodeRenderingService.for(blob, view, @user, @repo)

        assert_match %r|\Ahttps://viewscreen\.githubusercontent\.com/view/solid\?|, vs.url_for_display(commit_oid: "00decaf").to_s
      end

      test "uses the users color mode" do
        ViewscreenHelper.set_flags
        @user.update(color_mode: ColorMode::DARK)
        vs = CodeRenderingService.for(@blob, :view, @user, @repo)
        assert_includes vs.url_for_display(commit_oid: @blob.sha).query, "color_mode=dark"
        @user.update(color_mode: ColorMode::LIGHT)
        vs = CodeRenderingService.for(@blob, :view, @user, @repo)
        assert_includes vs.url_for_display(commit_oid: @blob.sha).query, "color_mode=light"
        assert_includes vs.url_for_display(commit_oid: @blob.sha).query, "repository_id=#{@repo.id}"
        assert_includes vs.url_for_display(commit_oid: @blob.sha).query, "path=foo.svg"
      end

      test "logged_in parameter is set appropriately" do
        ViewscreenHelper.set_flags

        vs = CodeRenderingService.for(@blob, :view, nil, @repo)
        assert_includes vs.url_for_display(commit_oid: @blob.sha).query, "logged_in=false"

        vs = CodeRenderingService.for(@blob, :view, @user, @repo)
        assert_includes vs.url_for_display(commit_oid: @blob.sha).query, "logged_in=true"
      end

      test "it includes the correct url for blobs" do
        ViewscreenHelper.set_flags

        # Could not get this working properly with minitest, and stubbing `request` seemed like a huge pain
        useragent =
          Class.new do
            define_method(:id) { "chrome" }
            define_method(:version) { "67" }
            define_method(:platform) { Class.new { define_method(:id) { "mac" } }.new }
            define_method(:device) { Class.new { define_method(:id) { "unknown_device" } }.new }
          end.new

        vs =  CodeRenderingService.for(@blob, :view, @user, @repo, opts: { parsed_useragent: useragent })

        url = vs.url_for_display(commit_oid: @blob.sha)
        query = Rack::Utils.parse_query(url.query)

        assert_equal query["nwo"], @repo.nwo
        assert_includes query["commit"], @blob.sha
        assert_includes query["repository_type"], @repo.class.name
        assert_includes query["browser"], useragent.id
        assert_includes query["version"], useragent.version
        assert_includes query["device"], useragent.device.id
        assert_includes query["platform"], useragent.platform.id

        content_url = TreeEntryRenderHelper.raw_blob_url(@user, @repo, @blob.sha, "foo.svg", expires_key: :render, host: GitHub.render_raw_host_name)

        assert_includes decode_url(query["enc_url"]), content_url
      end

      test "it correctly passes an empty hash when parsed_useragent is not supplied" do
        ViewscreenHelper.set_flags
        vs =  CodeRenderingService.for(@blob, :view, @user, @repo, opts: {})
        url = vs.url_for_display(commit_oid: @blob.sha)
        query = Rack::Utils.parse_query(url.query)

        refute_includes query, "device"
        refute_includes query, "browser"
        refute_includes query, "platform"
        refute_includes query, "version"
      end

      test "it includes correct urls for gists" do
        gist = GistHelpers.generate(
          user: @user,
          contents: [{
            name: "points.geojson",
            value: <<-GEOJSON
              {
                  "type": "Point",
                  "coordinates": [-97, 30]
              }
            GEOJSON
          }],
          description: "Public gist"
        )
        ViewscreenHelper.set_flags
        blob = gist.blob(gist.sha, "points.geojson")
        vs =  CodeRenderingService.for(blob, :view, @user, gist)
        url = vs.url_for_display(commit_oid: gist.sha)
        content_url = TreeEntryRenderHelper.raw_gist_url(@user, blob.repository, gist.sha, "points.geojson")
        query = Rack::Utils.parse_query(url.query)
        assert_includes decode_url(query["enc_url"]), content_url
      end

      test "it includes correct urls for gists when current repository is nil" do
        gist = GistHelpers.generate(
          user: @user,
          contents: [{
            name: "points.geojson",
            value: <<-GEOJSON
              {
                  "type": "Point",
                  "coordinates": [-97, 30]
              }
            GEOJSON
          }],
          description: "Public gist"
        )
        ViewscreenHelper.set_flags
        blob = gist.blob(gist.sha, "points.geojson")
        vs =  CodeRenderingService.for(blob, :view, @user)
        url = vs.url_for_display(commit_oid: gist.sha)
        content_url = TreeEntryRenderHelper.raw_gist_url(@user, blob.repository, gist.sha, "points.geojson")
        query = Rack::Utils.parse_query(url.query)
        assert_includes decode_url(query["enc_url"]), content_url
      end

      test "includes a docs host name" do
        ViewscreenHelper.set_flags
        vs = CodeRenderingService.for(@blob, :view, @user, @repo)
        assert_includes vs.url_for_display(commit_oid: @blob.sha).query, "docs_host=#{CGI.escape(GitHub.help_url)}"
      end
    end

    context "it properly identifies supported diffs" do
      Viewscreen::DiffComponent::SUPPORTED_VIEWS.keys.each do |file_type|
        Viewscreen::DiffComponent::SUPPORTED_VIEWS[file_type].each do |diff|
          test "can support the #{file_type} #{diff}" do
            ViewscreenHelper.set_flags
            if file_type == :img
              file_type = :jpg
            end
            blob = @repo.blob(@ref.sha, "foo.#{file_type}")
            diff = GitHub::Diff::Entry.new("foo.#{file_type}", "foo.#{file_type}")
            vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
            assert vs.class == Viewscreen::DiffComponent
            assert vs.supports_view?
            assert vs.render_type == @render_types[file_type]
          end
        end
      end
    end

    test "can identify unsupported render requests for files and view type combinations" do
      ViewscreenHelper.set_flags
      blob = @repo.blob(@ref.sha, "foo.js")
      vs = CodeRenderingService.for(blob, :view, @user, @repo)
      refute vs.supports_view?
      assert vs.render_type.nil?
    end
  end # !GitHub.enterprise?

  # dotcom and enterprise handle this differently
  sig { returns(String) }
  def raw_url_prefix
    "#{GitHub.scheme}://#{GitHub.urls.raw_host_name || "#{GitHub.host_name}/raw"}"
  end

  sig { params(url: String).returns(String) }
  def decode_url(url)
    [url].pack("H*").force_encoding("UTF-8")
  end

  sig { params(file_type: Symbol).returns(Symbol) }
  def normalize_file_type(file_type)
    case file_type
    when :solid then :stl
    when :mmd then :mermaid
    when :img then :jpg
    else file_type
    end
  end
end
