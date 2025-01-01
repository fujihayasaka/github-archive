# typed: true
# frozen_string_literal: true

require "test_helper"

class Notebook::DiffComponentTest < GitHub::TestCase
  setup do
    @org  = create(:organization)
    @user = create(:user, login: "defunkt")
    @repo = create(:public_repository, owner: @org)
    @feature = create(:feature_with_flipper, :opt_in, slug: "ipynb-diff")
    disable_feature_flag(:notebooks_bypass_fastly, @repo)
    enable_feature_flag("ipynb-diff")
    @user.enable_feature_preview("ipynb-diff")
    @org.enable_feature_preview("ipynb-diff")

    example_repo_snapshot
    example_repo_restore
    @ref = @repo.heads.find_or_build("master")
    @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
      files.add("foo.ipynb", "notebook")
      files.add("foo.js", "")
      files.add("foo.geojson", "")
    end
    @blob = @repo.blob(@ref.sha, "foo.ipynb")
    @diff = GitHub::Diff::Entry.new("foo.ipynb", "foo.ipynb")
  end

  if !GitHub.enterprise? # I am adding tests for enterprise, but we are not ready yet for enterprise.
    context "it properly identifies supported diffs" do
      test "can support the ipynb diff when the feature preview is enabled" do
        blob = @repo.blob(@ref.sha, "foo.ipynb")
        vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: @diff)
        assert vs.class == Notebook::DiffComponent
        assert vs.supports_view?
        assert vs.render_type == :ipynb
      end

      test "correctly doesn't support ipynb diff with the feature preview disabled" do
        @user.disable_feature_preview("ipynb-diff")
        blob = @repo.blob(@ref.sha, "foo.ipynb")
        vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: @diff)
        assert vs.class == Viewscreen::DiffComponent
        refute vs.supports_view?
      end


      test "no support for deleted file" do
        blob = @repo.blob(@ref.sha, "foo.ipynb")
        diff = GitHub::Diff::Entry.new("foo.ipynb", "foo.ipynb")
        diff.stubs(:deleted?).returns(true)

        vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
      end

      test "correctly doesn't support ipynb diff for a logged out user" do
        blob = @repo.blob(@ref.sha, "foo.ipynb")
        diff = GitHub::Diff::Entry.new("foo.ipynb", "foo.ipynb")

        vs = CodeRenderingService.for(blob, :diff, nil, @repo, diff: diff)
        assert vs.class == Viewscreen::DiffComponent
        refute vs.supports_view?
      end
    end

    context "diff url creation" do
      test "uses the users color mode repo id and path to the file" do
        @user.update(color_mode: ColorMode::DARK)
        vs =  CodeRenderingService.for(@blob, :diff, @user, @repo, diff: @diff)
        query = Rack::Utils.parse_query(vs.rich_diff_url(file_view: nil, file_list_view: nil).query)
        assert_equal query["color_mode"], "dark"
        @user.update(color_mode: ColorMode::LIGHT)
        vs =  CodeRenderingService.for(@blob, :diff, @user, @repo, diff: @diff)
        query = Rack::Utils.parse_query(vs.rich_diff_url(file_view: nil, file_list_view: nil).query)
        assert_equal query["color_mode"], "light"

        assert_equal query["repository_id"], @repo.id.to_s
        assert_equal query["path"], "foo.ipynb"
      end

      test "adds bypass_fastly query param if the feature is enabled for a repo" do
        enable_feature_flag(:notebooks_bypass_fastly, @repo)
        vs =  CodeRenderingService.for(@blob, :diff, @user, @repo, diff: @diff)
        query = Rack::Utils.parse_query(vs.rich_diff_url(file_view: nil, file_list_view: nil).query)
        assert_equal query["bypass_fastly"], "true"

        disable_feature_flag(:notebooks_bypass_fastly, @repo)
        vs =  CodeRenderingService.for(@blob, :diff, @user, @repo, diff: @diff)
        query = Rack::Utils.parse_query(vs.rich_diff_url(file_view: nil, file_list_view: nil).query)
        refute_includes query.keys, "bypass_fastly"
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
        assert_match %r(\A(/viewscreen)?/added/ipynb\z), url.path
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
        repo = create(:repository, owner: @org)

        ref1 = repo.heads.find_or_build("master")
        ref1.append_commit({ message: "a new file", committer: repo.owner }, repo.owner) do |files|
          files.add("foo.ipynb", "")
        end
        parent_sha = ref1.sha

        blob = repo.blob(ref1.sha, "foo.ipynb")

        ref1.append_commit({ message: "a change", committer: repo.owner }, repo.owner) do |files|
          files.add("foo.ipynb", "123")
        end

        blob1 = repo.blob(ref1.sha, "foo.ipynb")
        diff = repo.commits.find(ref1.sha).diff.first
        vs = CodeRenderingService.for(blob, :diff, @user, repo, diff: diff)
        url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
        query = Rack::Utils.parse_query(url.query)

        assert_match %r(\A(/notebook)?/diff/ipynb\z), url.path
        assert_includes decode_url(query["enc_url2"]), "#{raw_url_prefix}/#{repo.nwo}/#{ref1.sha}/foo.ipynb"
        assert_includes decode_url(query["enc_url1"]), "#{raw_url_prefix}/#{repo.nwo}/#{parent_sha}/foo.ipynb"

        if GitHub.enterprise?
          GitHub.subdomain_isolation = true
          vs = CodeRenderingService.for(blob, :diff, @user, repo, diff: diff)
          url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
          query = Rack::Utils.parse_query(url.query)

          assert_match %r(\Ahttps:\/\/notebooks\.github\.com/diff/ipynb), url.to_s
        end
      end

      test "it includes correct urls for gists" do
        gist = GistHelpers.generate(
          user: @repo.owner,
          contents: [{
            name: "points.ipynb",
            value: <<-IPYNB
              {
                  "type": "Point",
                  "coordinates": [-97, 30]
              }
            IPYNB
          }],
          description: "pub gist"
        )

        user_id = gist.user_param
        gist_id = gist.repo_name
        base_sha = gist.reload.sha
        file   = "points.ipynb"

        gist.contents = [{
          oid: base_sha,
          name: "points.ipynb",
          value: <<-IPYNB
            {
                "type": "Point",
                "coordinates": [97, -30]
            }
          IPYNB
        }]
        gist.save!

        assert commit = gist.commits.find(gist.reload.sha)
        assert diff = commit.diff
        assert entry = diff.entries[0]
        assert blob = gist.blob(gist.sha, "points.ipynb")

        vs =  CodeRenderingService.for(blob, :diff, @user, gist, diff: entry)
        url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
        query = Rack::Utils.parse_query(url.query)

        assert_match %r(\A/diff/ipynb\z), url.path
        url1 = decode_url(query["enc_url1"])
        url2 = decode_url(query["enc_url2"])
        assert_includes url1, "/gist/#{gist.nwo}/raw/#{base_sha}/points.ipynb"
        assert_includes url2, "/gist/#{gist.nwo}/raw/#{gist.sha}/points.ipynb"

        if GitHub.enterprise?
          GitHub.subdomain_isolation = true
          vs =  CodeRenderingService.for(blob, :diff, @user, gist, diff: entry)
          url = vs.rich_diff_url(file_view: nil, file_list_view: nil)
          assert_match %r(\Ahttps:\/\/notebooks\.github\.com\/diff\/ipynb), url.to_s
        end
      end
    end

    context "toggelable rich diff and notebooks are the default view" do
      test "no toggle for unsupported view" do
        blob = @repo.blob(@ref.sha, "foo.geojson")
        diff = GitHub::Diff::Entry.new("foo.geojson", "foo.geojson")
        vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
        refute vs.rich_view_toggleable?
        refute vs.default_to_rich_diff_view?
      end

      test "no toggle for deleted file" do
        blob = @repo.blob(@ref.sha, "foo.ipynb")
        diff = GitHub::Diff::Entry.new("foo.ipynb", "foo.ipynb")
        diff.stubs(:deleted?).returns(true)

        vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
        refute vs.rich_view_toggleable?
        refute vs.default_to_rich_diff_view?
      end

      test "show toggle for ipynb and default to it" do
        blob = @repo.blob(@ref.sha, "foo.ipynb")
        diff = GitHub::Diff::Entry.new("foo.ipynb", "foo.ipynb")

        vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
        assert vs.rich_view_toggleable?
        assert vs.default_to_rich_diff_view?
      end
    end
  else
    test "Enterprise does not support ipynb diff" do
      blob = @repo.blob(@ref.sha, "foo.ipynb")
      diff = GitHub::Diff::Entry.new("foo.ipynb", "foo.ipynb")
      vs = CodeRenderingService.for(blob, :diff, @user, @repo, diff: diff)
      # We will fall through to the default diff view if notebooks are not enabled
      assert vs.class == Viewscreen::DiffComponent
      assert_not vs.supports_view?
    end

    test "bypass_fastly query param isn't added for Enterprise" do
      enable_feature_flag(:notebooks_bypass_fastly, @repo)
      vs =  CodeRenderingService.for(@blob, :diff, @user, @repo, diff: @diff)
      query = Rack::Utils.parse_query(vs.rich_diff_url(file_view: nil, file_list_view: nil).query)
      refute_includes query.keys, "bypass_fastly"
    end
  end

  # dotcom and enterprise handle this differently
  def raw_url_prefix
    "#{GitHub.scheme}://#{GitHub.urls.raw_host_name || "#{GitHub.host_name}/raw"}"
  end

  def decode_url(url)
    [url].pack("H*").force_encoding("UTF-8")
  end
end
