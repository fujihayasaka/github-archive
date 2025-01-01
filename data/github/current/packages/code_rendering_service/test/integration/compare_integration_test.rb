# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/viewscreen_helpers"

class CodeRenderingServiceCompareIntegrationTest < GitHub::IntegrationTestCase

  fixtures do
    @org  = create(:organization)
    @user = create(:user, login: "defunkt")
    @repo = create(:repository, owner: @org)
    @feature = create(:feature_with_flipper, :opt_in, slug: "ipynb-diff")

    example_repo_snapshot
  end

  setup do
    example_repo_restore
    example_repo :post_receive_job_test, @repo
    GitHub.subdomain_isolation = true
    GitHub.user_content_host_name = "githubusercontent.com"
  end

  def viewscreen_url(file_type, type = "view")
    "#{Viewscreen.host_url}/#{type}/#{file_type}?"
  end


  context "compare page" do
    test "add a new file" do
      # https://github.com/github/renderables/compare/master...gwincr11-patch-3

      @ref = @repo.heads.find_or_build("new_branch")
      @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
        files.add("foo.svg", "")
      end
      short_path = "7ccb48102f98bcf574a8b4267a4bcf31113fc23179569697a26d76cd10b7760e"[0, 7] # Digest::SHA256.hexdigest("foo.svg")

      as @user
      get "/#{@repo.name_with_display_owner}/compare/file-list", params: { range: "master...new_branch", short_path: short_path }

      assert_response :ok

      assert_select ".render-viewer" do |el|
        assert_includes el.first["src"], viewscreen_url("svg", type = "added")
      end
    end

    test "edit an existing file" do
      GitHub::Diff::Entry.any_instance.stubs(:added?).returns(false)
      @ref = @repo.heads.find_or_build("master")
      @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
        files.add("foo.svg", "")
      end
      @ref = @repo.heads.find_or_build("new_branch")
      @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
        files.add("foo.svg", "change")
      end

      short_path = "7ccb48102f98bcf574a8b4267a4bcf31113fc23179569697a26d76cd10b7760e"[0, 7] # Digest::SHA256.hexdigest("foo.svg")
      as @user
      get "/#{@repo.name_with_display_owner}/compare/file-list", params: { range: "master...new_branch", short_path: short_path }

      assert_response :ok

      assert_select ".render-viewer" do |el|
        assert_includes el.first["src"], viewscreen_url("svg", type = "diff")
      end
    end
  end

  if !GitHub.enterprise?
    context "pull request files changed", skip_with_all_emus: true do
      test "pull request show files notebooks url when the user is opted into the feature preview" do
        GitHub.flipper["ipynb-diff"].enable
        @user.enable_feature_preview("ipynb-diff")

        repo = create(:repository, owner: @user, from_example: :renderables)

        issue = create(:issue, repository: repo)
        create(:pull_request,
          repository: repo,
          base_repository: repo,
          base_user: repo.owner,
          base_ref: "notebook-add",
          head_repository: repo,
          head_user: repo.owner,
          head_ref: "update-notebook",
          issue: issue,
        )

        as repo.owner
        get "/#{repo.name_with_display_owner}/diffs/0?base_sha=a0552eac2099695fe50c8b92e944ee3618dab862&commentable=true&pull_number=1&sha1=a0552eac2099695fe50c8b92e944ee3618dab862&sha2=c234156d96f106111a408a2307098feceb19901b&short_path=9782d30"
        assert_select ".render-viewer" do |el|
          assert_includes el.first["src"], "enc_url1"
          assert_includes el.first["src"], "enc_url2"
        end
      end

      test "pull request does not show files notebooks url when the user is logged out" do
        GitHub.flipper["ipynb-diff"].enable(@user)

        repo = create(:public_repository, owner: @user, from_example: :renderables)

        issue = create(:issue, repository: repo)
        create(:pull_request,
          repository: repo,
          base_repository: repo,
          base_user: repo.owner,
          base_ref: "notebook-add",
          head_repository: repo,
          head_user: repo.owner,
          head_ref: "update-notebook",
          issue: issue,
        )

        get "/#{repo.name_with_display_owner}/diffs/0?base_sha=a0552eac2099695fe50c8b92e944ee3618dab862&commentable=true&pull_number=1&sha1=a0552eac2099695fe50c8b92e944ee3618dab862&sha2=c234156d96f106111a408a2307098feceb19901b&short_path=9782d30"
        refute_select ".render-viewer"
      end

      test "pull request does not show files notebooks url when the user is not opted into the feature preview" do
        GitHub.flipper["ipynb-diff"].disable(@user)

        repo = create(:public_repository, owner: @user, from_example: :renderables)

        issue = create(:issue, repository: repo)
        create(:pull_request,
          repository: repo,
          base_repository: repo,
          base_user: repo.owner,
          base_ref: "notebook-add",
          head_repository: repo,
          head_user: repo.owner,
          head_ref: "update-notebook",
          issue: issue,
        )

        as repo.owner
        get "/#{repo.name_with_display_owner}/diffs/0?base_sha=a0552eac2099695fe50c8b92e944ee3618dab862&commentable=true&pull_number=1&sha1=a0552eac2099695fe50c8b92e944ee3618dab862&sha2=c234156d96f106111a408a2307098feceb19901b&short_path=9782d30"
        refute_select ".render-viewer"
      end
    end
  end

  if GitHub.enterprise?
    test "page without viewscreen uses Viewscreen on Enterprise" do
      ViewscreenHelper.disable_flags
      @ref = @repo.heads.find_or_build("new_branch")
      @ref.append_commit({ message: "a change", committer: @repo.owner }, @repo.owner) do |files|
        files.add("foo.svg", "")
      end
      short_path = "7ccb48102f98bcf574a8b4267a4bcf31113fc23179569697a26d76cd10b7760e"[0, 7] # Digest::SHA256.hexdigest("foo.svg")

      as @user
      get "/#{@repo.name_with_display_owner}/compare/file-list", params: { range: "master...new_branch", short_path: short_path }

      assert_response :ok

      assert_select ".render-viewer" do |el|
        assert_includes el.first["src"], viewscreen_url("svg", type = "added")
      end
    end
  end
end
