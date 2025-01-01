# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class SubmoduleTest < GitHub::TestCase
  fixtures do
    @user = create :user, login: "login303"
    gist_contents = [{ name: "1", value: "random content" }]
    @gist = GistHelpers.generate contents: gist_contents, user: @user
    @user_param = @gist.user_param
    @gist_param = @gist.to_param

    @legacy_gist = GistHelpers.generate contents: gist_contents, user: @user
    @legacy_gist.update_column :repo_name, @legacy_gist.id
    @legacy_gist_param = @legacy_gist.to_param

    @repo = create(:repository, name: "public-repo", owner: @user)
  end

  test "async_subproject_commit_oid" do
    example_repo :tree_with_submod, @repo
    submodule = @repo.submodule(@repo.default_oid, "test/foo")
    result = submodule.async_subproject_commit_oid.sync
    assert(result)
    actual_target_oid = @repo.rpc.ls_tree(@repo.default_oid, path: "test/foo")["entries"][0][2]
    assert_equal(actual_target_oid, result)
  end

  test "async_subproject_commit_oid for broken repo" do
    example_repo :tree_with_submod, @repo
    # break this submodule in a way that the git client itself wouldn't dream
    # of doing by deleting the dir the submodule lives in while leaving the
    # .gitmodules file intact.
    @repo.heads["master"].append_commit({ message: "break repo", committer: @user }, @user) do |files|
      files.remove("test/foo")
    end
    submodule = @repo.submodule(@repo.default_oid, "test/foo")
    assert submodule # still exists in .gitmodules so it's retrivable even
    # though we broke its spot in the repo :)
    result = submodule.async_subproject_commit_oid.sync
    assert_nil result # gracefully fails to find anything
  end

  test "parses repo urls" do
    [
      # Dev mode clone URL
      "http://#{GitHub.host_name}/#{@repo.nwo}.git",

      # Not really a gist although it was previously identified as one
      "http://#{GitHub.host_name}/#{@user_param}/#{@gist_param}.git",

      # Dotcom View URL
      "https://#{GitHub.host_name}/#{@repo.nwo}",

      # Dotcom Clone URL
      "https://#{GitHub.host_name}/#{@repo.nwo}.git",

      # Dotcom SSH Clone URL
      "git@#{GitHub.host_name}:#{@repo.nwo}.git",

      # Relative URL that (potentially) maps to another repo from the same owner
      "../other-repo",

      # Relative URL that (potentially) maps to another nwo
      "../../other-repo/other-user",
    ].each do |repo_submodule_url|
      submodule = build(:submodule, repo: @repo, url: repo_submodule_url)

      assert submodule.repo?,
        "Expected Submodule#repo? to be true for #{repo_submodule_url}, but it was false."
      refute submodule.gist?,
        "Expected Submodule#gist? to be false for #{repo_submodule_url}, but it was true."
      refute submodule.wiki?,
        "Expected Submodule#wiki? to be false for #{repo_submodule_url}, but it was true."
    end
  end

  test "checks if url is web linkable" do
    assert build(:submodule, repo: @repo, url: "git@#{GitHub.host_name}:#{@repo.nwo}.git").url_is_linkable?
    assert build(:submodule, repo: @repo, url: "https://#{GitHub.host_name}/#{@repo.nwo}.git").url_is_linkable?
    assert build(:submodule, repo: @repo, url: "../other-repo").url_is_linkable?
    assert build(:submodule, repo: @repo, url: "../other-repo.git").url_is_linkable?
    assert build(:submodule, repo: @repo, url: "../../other-user/other-repo").url_is_linkable?
    assert build(:submodule, repo: @repo, url: "../../other-user/other-repo.git").url_is_linkable?
    refute build(:submodule, repo: @repo, url: "git@private.server:#{@repo.nwo}.git").url_is_linkable?
  end

  test "creates web linkable url" do
    assert_equal "#{GitHub.url}/#{@repo.nwo}",
      build(:submodule, repo: @repo, url: "https://#{GitHub.host_name}/#{@repo.nwo}.git").linkable_url
    assert_equal "#{GitHub.url}/#{@repo.nwo}",
      build(:submodule, url: "git@#{GitHub.host_name}:#{@repo.nwo}.git").linkable_url
    assert_equal "#{GitHub.url}/#{@repo.owner.login}/other-repo",
      build(:submodule, repo: @repo, url: "../other-repo").linkable_url
    assert_equal "#{GitHub.url}/#{@repo.owner.login}/other-repo",
      build(:submodule, repo: @repo, url: "../other-repo.git").linkable_url
    assert_equal "#{GitHub.url}/other-user/other-repo",
      build(:submodule, repo: @repo, url: "../../other-user/other-repo").linkable_url
    assert_equal "#{GitHub.url}/other-user/other.repo",
      build(:submodule, repo: @repo, url: "../../other-user/other.repo").linkable_url
    assert_equal "#{GitHub.url}/other-user/other-repo",
      build(:submodule, repo: @repo, url: "../../other-user/other-repo.git").linkable_url
    refute build(:submodule, url: "git@private.server:#{@repo.nwo}.git").linkable_url
  end

  test "doesn't make bad links" do
    [
      "#{GitHub.url}/\r/example.com",
      "../../\r/example.com",
      "../\rexample.com",
      "#{GitHub.url}/\r/𝟢xacb",
      "../../\r/𝟢xacb",
      "../\r/𝟢xacb",
    ].each do |url|
      submodule = build(:submodule, repo: @repo, url: url)
      assert_nil submodule.user, "Expected Submodule#user to be nil for #{url}, but it was not."
      assert_nil submodule.repo, "Expected Submodule#repo to be nil for #{url}, but it was not."
      assert_nil submodule.gist, "Expected Submodule#gist to be nil for #{url}, but it was not."
    end
  end

  test "parses wiki urls" do
    [
      # Dev mode clone URL
      "http://#{GitHub.host_name}/#{@repo.nwo}.wiki.git",

      # Dotcom Clone URL
      "https://#{GitHub.host_name}/#{@repo.nwo}.wiki.git",
    ].each do |wiki_submodule_url|
      submodule = build(:submodule, repo: @repo, url: wiki_submodule_url)

      assert submodule.wiki?,
        "Expected Submodule#wiki? to be true for #{wiki_submodule_url}, but it was false."
      refute submodule.gist?,
        "Expected Submodule#gist? to be false for #{wiki_submodule_url}, but it was true."
      refute submodule.repo?
      "Expected Submodule#repo? to be false for #{wiki_submodule_url}, but it was true."
    end
  end

  test "parses gist urls" do
    if GitHub.subdomain_isolation?
      gists = [
        # Dotcom View URL
        "https://#{GitHub.gist_host_name}/#{@user_param}/#{@gist_param}",
        "https://#{GitHub.gist_host_name}/#{@user_param}/#{@legacy_gist_param}",

        # Sans protocol
        "#{GitHub.gist_host_name}/#{@user_param}/#{@gist_param}",
        "#{GitHub.gist_host_name}/#{@user_param}/#{@legacy_gist_param}",

        # Dotcom Clone URL
        "https://#{GitHub.gist_host_name}/#{@gist_param}.git",
        "https://#{GitHub.gist_host_name}/#{@legacy_gist_param}.git",

        # SSH Clone URL
        "git@#{GitHub.gist_host_name}:#{@gist_param}.git",
        "git@#{GitHub.gist_host_name}:/#{@gist_param}.git",
        "git@#{GitHub.gist_host_name}:#{@legacy_gist_param}.git",
        "git@#{GitHub.gist_host_name}:/#{@legacy_gist_param}.git",
      ]
    else
      gists = [
        # Dev mode clone URL
        "http://#{GitHub.gist_host_name}/gist/#{@gist_param}.git",
        "http://#{GitHub.gist_host_name}/gist/#{@legacy_gist_param}.git",

        # Dotcom View URL
        "https://#{GitHub.gist_host_name}/gist/#{@user_param}/#{@gist_param}",
        "https://#{GitHub.gist_host_name}/gist/#{@user_param}/#{@legacy_gist_param}",

        # Sans protocol
        "#{GitHub.gist_host_name}/gist/#{@user_param}/#{@gist_param}",
        "#{GitHub.gist_host_name}/gist/#{@user_param}/#{@legacy_gist_param}",

        # Dotcom Clone URL
        "https://#{GitHub.gist_host_name}/gist/#{@gist_param}.git",
        "https://#{GitHub.gist_host_name}/gist/#{@legacy_gist_param}.git",

        # SSH Clone URL
        "git@#{GitHub.gist_host_name}:gist/#{@gist_param}.git",
        "git@#{GitHub.gist_host_name}:/gist/#{@gist_param}.git",
        "git@#{GitHub.gist_host_name}:gist/#{@legacy_gist_param}.git",
        "git@#{GitHub.gist_host_name}:/gist/#{@legacy_gist_param}.git",
      ]
    end
    gists.each do |gist_submodule_url|
      submodule = build(:submodule, repo: @repo, url: gist_submodule_url)

      assert submodule.gist?,
        "Expected Submodule#gist? to be true for #{gist_submodule_url}, but it was false."
      refute submodule.wiki?,
        "Expected Submodule#wiki? to be false for #{gist_submodule_url}, but it was true."
      refute submodule.repo?,
        "Expected Submodule#repo? to be false for #{gist_submodule_url}, but it was true."
    end
  end
end
