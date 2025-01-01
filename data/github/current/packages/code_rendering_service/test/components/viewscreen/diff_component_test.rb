# typed: true
# frozen_string_literal: true
require "test_helper"
require "test_helpers/viewscreen_helpers"

class Viewscreen::DiffComponentTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @org  = create(:organization)
    @user = create(:user, login: "defunkt")
    @repo = create(:repository, owner: @org)
    @diff = GitHub::Diff::Entry.new("foo.svg", "foo.svg").freeze
    @render_types = {
      geojson: :geojson,
      stl: :solid,
      pdf: :pdf,
      topojson: :topojson,
      svg: :svg,
      jpg: :img,
      psd: :psd
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
    end
    @blob = @repo.blob(@ref.sha, "foo.svg")
  end

  context "it properly identifies supported diffs" do
    if !GitHub.enterprise?
      Viewscreen::DiffComponent::SUPPORTED_VIEWS.keys.each do |file_type|
        Viewscreen::DiffComponent::SUPPORTED_VIEWS[file_type].each do |diff|
          test "can support the #{file_type} #{diff}" do
            ViewscreenHelper.set_flags
            if file_type == :img
              file_type = :jpg
            end
            blob = @repo.blob(@ref.sha, "foo.#{file_type}")
            vs = CodeRenderingService.for(blob, diff, @user, @repo, diff: @diff)
            assert vs.class == Viewscreen::DiffComponent
            assert vs.supports_view?
            assert vs.render_type == @render_types[file_type]
          end

          test "no support for deleted files #{file_type}" do
            blob = @repo.blob(@ref.sha, "foo.#{file_type}")
            diff = GitHub::Diff::Entry.new("foo.#{file_type}", "foo.#{file_type}")
            diff.stubs(:deleted?).returns(true)

            vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
            refute vs.supports_view?
          end
        end
      end
      Viewscreen::DiffComponent::FLAGGED_FEATURES.each do |file_type|
        test "correctly doesn't support #{file_type}" do
          ViewscreenHelper.disable_flags
          blob = @repo.blob(@ref.sha, "foo.#{file_type}")
          vs = CodeRenderingService.for(blob, file_type, @user, @repo, diff: @diff)
          refute vs.supports_view?
        end
      end
    end
  end

  context "diff url creation" do
    test "uses the users color mode repo id and path to the file" do
      ViewscreenHelper.set_flags
      @user.update(color_mode: ColorMode::DARK)
      vs =  CodeRenderingService.for(@blob, :diff, @user, @repo, diff: @diff)
      query = Rack::Utils.parse_query(vs.rich_diff_url(file_view: nil, file_list_view: nil).query)
      assert_equal query["color_mode"], "dark"
      @user.update(color_mode: ColorMode::LIGHT)
      vs =  CodeRenderingService.for(@blob, :diff, @user, @repo, diff: @diff)
      query = Rack::Utils.parse_query(vs.rich_diff_url(file_view: nil, file_list_view: nil).query)
      assert_equal query["color_mode"], "light"

      assert_equal query["repository_id"], @repo.id.to_s
      assert_equal query["path"], "foo.svg"
    end

    test "a diff that introduces a file returns nil for the base url" do
      repo = create(:repository, owner: @org, from_example: :commits_with_images)
      assert commit = repo.commits.find("27f2e1019acecbf5344448f69db31b01bcbc0e35")
      assert diff = commit.diff
      assert entry = diff.entries[0]
      blob = commit.repository.blob(commit.sha, entry.b_path)

      assert_nil entry.a_path
      assert_equal "d33bed38fe3b88f417251448b945a968951b8b47", entry.a_sha
      vs =  CodeRenderingService.for(@blob, :diff, @user, repo, diff: entry)
      url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
      assert_match %r(\A(/viewscreen)?/added/svg\z), url.path
      query = Rack::Utils.parse_query(url.query)

      assert_nil entry.a_path
      assert_equal "d33bed38fe3b88f417251448b945a968951b8b47", entry.a_sha
      vs =  CodeRenderingService.for(@blob, :diff, @user, repo, diff: entry)
      url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
      assert_match %r(\A(/viewscreen)?/added/svg\z), url.path
      query = Rack::Utils.parse_query(url.query)

      content_url = TreeEntryRenderHelper.raw_blob_url(@user, repo, entry.b_sha, entry.b_path, expires_key: :render, host: GitHub.render_raw_host_name)
      assert_equal content_url, decode_url(query["enc_url"])
    end

    test "a diff that deletes a file returns nil for the head url" do
      repo = create(:repository, owner: @org, from_example: :commits_with_images)
      assert commit = repo.commits.find("6862debd3bdadd83afd227a9441eea45a26b1622")
      assert diff = commit.diff
      assert entry = diff.entries[0]

      assert_nil entry.b_path
      assert_equal "6862debd3bdadd83afd227a9441eea45a26b1622", entry.b_sha

      vs =  CodeRenderingService.for(@blob, :diff, @user, repo, diff: entry)
      query = Rack::Utils.parse_query(vs.rich_diff_url(file_view: nil, file_list_view: nil).query)

      assert_equal "", decode_url(query["enc_url2"])
    end

    test "it includes each url needed for the diff with normal blobs" do
      ViewscreenHelper.set_flags
      repo = create(:repository, owner: @org)

      ref1 = repo.heads.find_or_build("master")
      ref1.append_commit({ message: "a new file", committer: repo.owner }, repo.owner) do |files|
        files.add("foo.svg", "")
      end
      parent_sha = ref1.sha

      blob = repo.blob(ref1.sha, "foo.svg")

      ref1.append_commit({ message: "a change", committer: repo.owner }, repo.owner) do |files|
        files.add("foo.svg", "123")
      end

      blob1 = repo.blob(ref1.sha, "foo.svg")
      diff = repo.commits.find(ref1.sha).diff.first

      GitHub.subdomain_isolation = false
      vs = CodeRenderingService.for(blob, :diff, @user, repo, diff: diff)
      url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
      query = Rack::Utils.parse_query(url.query)

      assert_match %r(\A(/viewscreen)?/diff/svg\z), url.path
      assert_includes decode_url(query["enc_url2"]), "#{raw_url_prefix}/#{repo.nwo}/#{ref1.sha}/foo.svg"
      assert_includes decode_url(query["enc_url1"]), "#{raw_url_prefix}/#{repo.nwo}/#{parent_sha}/foo.svg"

      if GitHub.enterprise?
        GitHub.subdomain_isolation = true
        vs = CodeRenderingService.for(blob, :diff, @user, repo, diff: diff)
        url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
        query = Rack::Utils.parse_query(url.query)

        assert_match %r(\Ahttps:\/\/viewscreen\.github\.com/diff/svg), url.to_s
      end
    end

    test "it includes correct urls for gists" do
      gist = GistHelpers.generate(
        user: @repo.owner,
        contents: [{
          name: "foo.svg",
          value: '<svg height="100" width="100"><circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red" /></svg> '
        }],
        description: "pub gist"
      )

      user_id = gist.user_param
      gist_id = gist.repo_name
      base_sha = gist.reload.sha
      file   = "foo.svg"

      gist.contents = [{
        oid: base_sha,
        name: "foo.svg",
        value: '<svg height="100" width="100"><circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="blue" /></svg> '
      }]
      gist.save!

      assert commit = gist.commits.find(gist.reload.sha)
      assert diff = commit.diff
      assert entry = diff.entries[0]
      assert blob = gist.blob(gist.sha, "foo.svg")

      ViewscreenHelper.set_flags
      vs =  CodeRenderingService.for(blob, :diff, @user, gist, diff: entry)
      url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
      query = Rack::Utils.parse_query(url.query)

      ViewscreenHelper.set_flags
      vs =  CodeRenderingService.for(blob, :diff, @user, gist, diff: entry)
      url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
      query = Rack::Utils.parse_query(url.query)

      assert_match %r(\A(/viewscreen)?/diff/svg\z), url.path
      url1 = decode_url(query["enc_url1"])
      url2 = decode_url(query["enc_url2"])
      assert_includes url1, "/gist/#{gist.nwo}/raw/#{base_sha}/foo.svg"
      assert_includes url2, "/gist/#{gist.nwo}/raw/#{gist.sha}/foo.svg"

      if GitHub.enterprise?
        GitHub.subdomain_isolation = true
        vs =  CodeRenderingService.for(blob, :diff, @user, gist, diff: entry)
        url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
        assert_match %r(\Ahttps:\/\/viewscreen\.github\.com\/diff\/svg), url.to_s
      end
    end
  end

  test "it includes correct urls for git lfs" do
    repo = create(:repository, owner: @org, from_example: :git_lfs)
    assert commit = repo.commits.find("5da59c5085c4a433e31ace06a61034ac6df8f666")
    assert diff = commit.diff
    assert entry = diff.entries[0]
    assert blob = repo.blob(commit.sha, entry.b_path)

    ViewscreenHelper.set_flags
    vs =  CodeRenderingService.for(blob, :diff, @user, repo, diff: entry)
    url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
    query = Rack::Utils.parse_query(url.query)

    assert_match %r(\A(/viewscreen)?/diff/img\z), url.path
    url1 = decode_url(query["enc_url1"])
    url2 = decode_url(query["enc_url2"])
    assert_equal url1, "#{GitHub.alambic_assets_url}/media/#{repo.nwo}/#{entry.a_sha}/diff/v2.jpg"
    assert_equal url2, "#{GitHub.alambic_assets_url}/media/#{repo.nwo}/#{entry.b_sha}/diff/v2.jpg"
  end

  test "with changed diff of v1 => v2 media pointer of same media blob" do
    repo = create(:repository, owner: @org, from_example: :git_lfs)
    assert commit = repo.commits.find("993667b8c1e3614121597072a2626940af671eed")
    assert diff = commit.diff
    assert entry = diff.entries[0]
    assert blob = repo.blob(commit.sha, entry.b_path)

    ViewscreenHelper.set_flags
    vs =  CodeRenderingService.for(blob, :diff, @user, repo, diff: entry)
    url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
    query = Rack::Utils.parse_query(url.query)

    assert_match %r(\A(/render)?/diff/img\z), url.path
    url1 = decode_url(query["enc_url1"])
    url2 = decode_url(query["enc_url2"])
    assert_equal url1, "#{raw_url_prefix}/#{repo.nwo}/#{entry.a_sha}/diff/v1.jpg"
    assert_equal url2, "#{GitHub.alambic_assets_url}/media/#{repo.nwo}/#{entry.b_sha}/diff/v1.jpg"
  end

  # TODO: How do we deal with an updated git lfs pointer for the same blob?
  test "with changed diff of v1 => v2 media pointer of updated media blob" do
    repo = create(:repository, owner: @org, from_example: :git_lfs)
    assert commit = repo.commits.find("186a3517ffbf830f27a429fcaf8e4b9da8e76eb4")
    assert diff = commit.diff
    assert entry = diff.entries[0]
    assert blob = repo.blob(commit.sha, entry.b_path)

    ViewscreenHelper.set_flags
    vs =  CodeRenderingService.for(blob, :diff, @user, repo, diff: entry)
    url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
    query = Rack::Utils.parse_query(url.query)

    assert_match %r(\A(/render)?/diff/img\z), url.path
    url1 = decode_url(query["enc_url1"])
    url2 = decode_url(query["enc_url2"])
    assert_equal url1, "#{raw_url_prefix}/#{repo.nwo}/#{entry.a_sha}/diff/v1-modified.jpg"
    assert_equal url2, "#{GitHub.alambic_assets_url}/media/#{repo.nwo}/#{entry.b_sha}/diff/v1-modified.jpg"
  end

  test "with changed diff of v2 media pointer" do
    repo = create(:repository, owner: @org, from_example: :git_lfs)
    assert commit = repo.commits.find("5da59c5085c4a433e31ace06a61034ac6df8f666")
    assert diff = commit.diff
    assert entry = diff.entries[0]
    assert blob = repo.blob(commit.sha, entry.b_path)

    ViewscreenHelper.set_flags
    vs =  CodeRenderingService.for(blob, :diff, @user, repo, diff: entry)
    url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
    query = Rack::Utils.parse_query(url.query)

    assert_match %r(\A(/render)?/diff/img\z), url.path
    url1 = decode_url(query["enc_url1"])
    url2 = decode_url(query["enc_url2"])
    assert_equal url1, "#{GitHub.alambic_assets_url}/media/#{repo.nwo}/#{entry.a_sha}/diff/v2.jpg"
    assert_equal url2, "#{GitHub.alambic_assets_url}/media/#{repo.nwo}/#{entry.b_sha}/diff/v2.jpg"
  end

  test "with changed diff of image blob to v2 media pointer" do
    repo = create(:repository, owner: @org, from_example: :git_lfs)
    assert commit = repo.commits.find("7fc2efad413509dad64b140e0781a0c6574777ef")
    assert diff = commit.diff
    assert entry = diff.entries[0]
    assert blob = repo.blob(commit.sha, entry.b_path)

    ViewscreenHelper.set_flags
    vs =  CodeRenderingService.for(blob, :diff, @user, repo, diff: entry)
    url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
    query = Rack::Utils.parse_query(url.query)

    assert_match %r(\A(/render)?/diff/img\z), url.path
    url1 = decode_url(query["enc_url1"])
    url2 = decode_url(query["enc_url2"])
    assert_equal url1, "#{raw_url_prefix}/#{repo.nwo}/5da59c5085c4a433e31ace06a61034ac6df8f666/diff/image.jpg"
    assert_equal url2, "#{raw_url_prefix}/#{repo.nwo}/7fc2efad413509dad64b140e0781a0c6574777ef/diff/image.jpg"
  end

  context "diff with file views" do
    test "it includes the file size when present" do
      images_repo = create(:repository, from_example: :commits_with_images)
      img_name = "scrooge.jpg"
      img_a_sha = "27f2e1019acecbf5344448f69db31b01bcbc0e35"
      img_a = images_repo.blob(img_a_sha, img_name)

      img_b_sha = "9d23b637db0020a7318e3c3e7d22c40660cab982"
      img_b = images_repo.blob(img_b_sha, img_name)

      # base the diff off of img_b_sha as the repo will contain both images at that point
      diff = images_repo.commits.find(img_b_sha).diff
      file_list_view = Diff::FileListView.new(diffs: diff, params: {}, current_user: @user)

      # loading the file views will pre-load the blob sizes from RPC headers...
      file_views = file_list_view.each_diff.to_a

      # this should return a hash that looks like { :oid => (size in bytes), ... }
      blob_sizes = file_list_view.blob_sizes

      ViewscreenHelper.set_flags
      vs =  CodeRenderingService.for(img_a, :diff, @user, images_repo, diff: diff.entries[0])
      url = vs.rich_diff_url(file_view: file_views.first, file_list_view: file_list_view)
      query = Rack::Utils.parse_query(url.query)
      # need to make sure both images are present
      assert_equal query["size1"], img_a.size.to_s
      assert_equal query["size2"], img_b.size.to_s
      assert_dogstats_increment(0, "viewscreen_repo.different_repo")
    end
  end

  [:js, :geojson, :topojson, :stl].each do |file_type|
    test "can identify unsupported render requests for #{file_type}" do
      ViewscreenHelper.set_flags

      blob = @repo.blob(@ref.sha, "foo.#{file_type}")
      vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: @diff)
      refute vs.supports_view?
    end
  end

  context "toggelable rich diff" do
    test "no toggle for unsupported view" do
      ViewscreenHelper.set_flags

      blob = @repo.blob(@ref.sha, "foo.geojson")
      diff = GitHub::Diff::Entry.new("foo.geojson", "foo.geojson")
      vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
      refute vs.rich_view_toggleable?
    end

    test "no toggle for images" do
      ViewscreenHelper.set_flags

      blob = @repo.blob(@ref.sha, "foo.jpg")
      diff = GitHub::Diff::Entry.new("foo.jpg", "foo.jpg")
      vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
      refute vs.rich_view_toggleable?
    end

    test "no toggle for deleted file" do
      ViewscreenHelper.set_flags

      blob = @repo.blob(@ref.sha, "foo.jpg")
      diff = GitHub::Diff::Entry.new("foo.jpg", "foo.jpg")
      diff.stubs(:deleted?).returns(true)

      vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
      refute vs.rich_view_toggleable?
    end

    test "no toggle for binary file" do
      blob = @repo.blob(@ref.sha, "foo.jpg")
      diff = GitHub::Diff::Entry.new("foo.jpg", "foo.jpg")
      diff.stubs(:binary?).returns(true)

      ViewscreenHelper.set_flags
      vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
      refute vs.rich_view_toggleable?
    end

    test "show toggle for supported view" do
      ViewscreenHelper.set_flags

      blob = @repo.blob(@ref.sha, "foo.svg")
      diff = GitHub::Diff::Entry.new("foo.svg", "foo.svg")

      vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
      assert vs.rich_view_toggleable?
    end
  end

  context "default_to_rich_diff_view?" do
    test "false for unsupported view" do
      ViewscreenHelper.set_flags

      blob = @repo.blob(@ref.sha, "foo.geojson")
      diff = GitHub::Diff::Entry.new("foo.geojson", "foo.geojson")
      vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
      refute vs.default_to_rich_diff_view?
    end

    test "false for deleted file" do
      ViewscreenHelper.set_flags

      blob = @repo.blob(@ref.sha, "foo.jpg")
      diff = GitHub::Diff::Entry.new("foo.jpg", "foo.jpg")
      diff.stubs(:deleted?).returns(true)

      vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
      refute vs.default_to_rich_diff_view?
    end

    test "true for binary file" do
      blob = @repo.blob(@ref.sha, "foo.jpg")
      diff = GitHub::Diff::Entry.new("foo.jpg", "foo.jpg")
      diff.stubs(:binary?).returns(true)

      ViewscreenHelper.set_flags
      vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
      assert vs.default_to_rich_diff_view?
    end

    test "true for supported view" do
      ViewscreenHelper.set_flags

      blob = @repo.blob(@ref.sha, "foo.svg")
      diff = GitHub::Diff::Entry.new("foo.svg", "foo.svg")

      vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
      assert vs.default_to_rich_diff_view?
    end
  end

  # dotcom and enterprise handle this differently
  sig { returns(String) }
  def raw_url_prefix
    "#{GitHub.scheme}://#{GitHub.urls.raw_host_name || "#{GitHub.host_name}/raw"}"
  end

  sig { params(url: T.nilable(String)).returns(String) }
  def decode_url(url)
    [url].pack("H*").force_encoding("UTF-8")
  end
end
