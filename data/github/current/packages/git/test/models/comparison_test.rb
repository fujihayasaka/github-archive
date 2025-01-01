# typed: true
# frozen_string_literal: true

require "test_helper"

class ComparisonTest < GitHub::TestCase

  fixtures do
    @user = create(:user, login: "turtle")
    @repo = create(:repository, name: "comparison_test", owner: @user, from_example: :comparison_fork)

    @head_sha   = "a270ea0fdfba2bd5a33934e5184784cddce87f38"   # master
    @parent_sha = "49bc45359806bb53b70aa558c0ee9371292924f8"   # master^
    @far_sha    = "afae62531bd8c918f58116eba786a1385492a5d3"   # master~8
    @topic_sha  = "480d4f47447129f015cb327536c522ca683939a1"   # topic
    @main_sha   = "0000000000000000000000000000000000000000"   # main-😀

    master2 = @repo.heads.create("master2", @parent_sha, @repo.owner)

    # master2's tree should match that of `master` exactly
    master2.append_commit({ committer: @repo.owner, message: "same changes as master" }, @repo.owner) do |files|
      files.remove("file11")
      files.remove("file18")
    end

    # add changes for branches with emojis
    main = @repo.heads.create("main-😀", @main_sha, @repo.owner)
    main.append_commit({ committer: @repo.owner, message: "testing emojis" }, @repo.owner) do |files|
      files.add("test1.txt", "change")
    end
    feature = @repo.heads.create("feature-😀", @main_sha, @repo.owner)
    feature.append_commit({ committer: @repo.owner, message: "testing emojis" }, @repo.owner) do |files|
      files.add("test2.txt", "change")
    end

    @repo.heads.create("same-as-master", @repo.heads.find("master").target_oid, @repo.owner)

    coauthor_ref = @repo.heads.create("coauthors", @topic_sha, @repo.owner)
    message = <<~MSG
    co-authored commit

    co-authored-by: Homer Simpson <hsimpson@github.com>
    MSG

    coauthor_ref.append_commit({ message: message, committer: @repo.owner, author: { name: "Lisa Simpson", email: "lsimpson@github.com" } }, @repo.owner)
    coauthor_ref.append_commit({ message: "text", committer: @repo.owner, author: { name: "Maggie Simpson", email: "msimpson@github.com" } }, @repo.owner)
  end

  context "#async_diff" do
    context "with summary false" do
      test "returns a cached full text diff" do
        comparison = GitHub::Comparison.from_range(@repo, "master..topic")
        diff = comparison.async_diff.sync
        refute_predicate diff, :use_summary?
        assert_equal diff, comparison.async_diff.sync
      end
    end

    context "with summary true" do
      test "returns a cached summary diff" do
        comparison = GitHub::Comparison.from_range(@repo, "master..topic")
        diff = comparison.async_diff(summary: true).sync
        assert_predicate diff, :use_summary?
        assert_equal diff, comparison.async_diff(summary: true).sync
      end
    end

    test "summary and text diffs are two different objects" do
      comparison = GitHub::Comparison.from_range(@repo, "master..topic")

      # regular first
      regular = comparison.async_diff(summary: false).sync

      #summary explicitly second
      summary = comparison.async_diff(summary: true).sync

      refute_equal regular, summary
    end
  end

  context ".from_range" do
    context "two dot" do
      test "compares between start and end commit" do
        comparison = GitHub::Comparison.from_range(@repo, "master..topic")

        assert_predicate comparison, :valid?
        assert_predicate comparison, :direct_compare?
        assert_equal @repo.heads.find("master").target_oid, comparison.diffs.sha1
      end
    end

    context "three dot" do
      test "compares between merge base and end commit" do
        comparison = GitHub::Comparison.from_range(@repo, "master...topic")
        assert_equal "8abd54838e6ecf23cdb60fd1110f3772a878c76c", comparison.diffs.sha1
        refute_predicate comparison, :direct_compare?

        comparison = GitHub::Comparison.from_range(@repo, "master…topic")
        assert_equal "8abd54838e6ecf23cdb60fd1110f3772a878c76c", comparison.diffs.sha1
        refute_predicate comparison, :direct_compare?
      end
    end

    context "no dot" do
      test "compares between merge base of topic and default branch and topic" do
        assert_raises GitHub::Comparison::InvalidRangeError do
          GitHub::Comparison.from_range(@repo, "topic")
        end
      end
    end
  end

  context ".from_range_or_ref" do
    context "two dot" do
      test "compares between start and end commit" do
        comparison = GitHub::Comparison.from_range_or_ref(@repo, "master..topic", user: @user)

        assert_predicate comparison, :valid?
        assert_predicate comparison, :direct_compare?
        assert_equal @repo.heads.find("master").target_oid, comparison.diffs.sha1
      end
    end

    context "three dot" do
      test "compares between merge base and end commit" do
        comparison = GitHub::Comparison.from_range_or_ref(@repo, "master...topic", user: @user)
        assert_equal "8abd54838e6ecf23cdb60fd1110f3772a878c76c", comparison.diffs.sha1
        refute_predicate comparison, :direct_compare?

        comparison = GitHub::Comparison.from_range_or_ref(@repo, "master…topic", user: @user)
        assert_equal "8abd54838e6ecf23cdb60fd1110f3772a878c76c", comparison.diffs.sha1
        refute_predicate comparison, :direct_compare?
      end
    end

    context "no dot" do
      test "compares between merge base of topic and default branch and topic" do
        comparison = GitHub::Comparison.from_range_or_ref(@repo, "topic", user: @user)
        assert_equal "8abd54838e6ecf23cdb60fd1110f3772a878c76c", comparison.diffs.sha1
        refute_predicate comparison, :direct_compare?
      end

      test "compares between merge base of topic and default branch from fork" do
        @source = create(:repository, name: "medellin", owner: @user)
        @user2 = create(:user, login: "user2")
        @fork = create(:fork_repository, forker: @user2, fork_repo: @source)

        comparison = GitHub::Comparison.from_range_or_ref(@fork, "topic", user: @user)
        assert_equal @source.name, comparison.base_repo.name
        assert_equal @fork.name, comparison.head_repo.name
        assert_equal comparison.base_ref, "master"
        assert_equal comparison.head_ref, "topic"
      end
    end
  end


  context "#empty?" do
    context "direct compare" do
      test "false if diff is unavailable/timed out" do
        GitRPC::Client.any_instance.stubs(:native_read_diff_toc).raises(GitRPC::Timeout)
        comparison = GitHub::Comparison.from_range(@repo, "master..master2")
        refute_predicate comparison, :empty?
      end

      test "false if diff has contents" do
        comparison = GitHub::Comparison.from_range(@repo, "master..topic")
        refute_predicate comparison, :empty?
      end

      test "true if diff available but has nothing in it" do
        comparison = GitHub::Comparison.from_range(@repo, "master..master2")
        assert_predicate comparison, :empty?
      end
    end

    context "regular compare" do
      test "true if no common ancestor" do
        commit = @repo.commits.create({ message: "disconnected commit", committer: @repo.owner }) do |files|
          files.add("secret", "text\n")
        end
        comparison = GitHub::Comparison.from_range(@repo, "master...#{commit.oid}")
        assert_predicate comparison, :empty?
      end

      test "true if there are no commits" do
        comparison = GitHub::Comparison.from_range(@repo, "master...behind")
        assert_predicate comparison, :empty?
      end
    end
  end

  test "initializing with a repo, base, and head sha" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    assert_equal "master", compare.base
    assert_equal "topic",  compare.head
    assert_equal @repo,    compare.repo
  end

  test "validating with nil base" do
    compare = GitHub::Comparison.deprecated_build(@repo, nil, "topic")
    assert_nil compare.base
    assert_equal "topic", compare.head
    assert_equal @repo,   compare.repo
    refute compare.valid?
  end

  test "validating with nil head" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", nil)
    assert_nil compare.head
    assert_equal "master", compare.base
    assert_equal @repo,    compare.repo
    refute compare.valid?
  end

  test "calculating SHA1s for base and head refs" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    assert_equal @head_sha,  compare.base_sha
    assert_equal @topic_sha, compare.head_sha
  end

  test "#async_author_count" do
    compare = GitHub::Comparison.build(base_repo: @repo, base_revision: "master", head_revision: "coauthors")

    assert_equal 5, compare.async_author_count.sync
  end

  test "fetching commits" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    assert_equal 3, compare.commits.size
    assert_equal @topic_sha, compare.commits.last.oid
    assert_equal "fb8529318277cb4dc3148ed5d0e15a61fa9d0591", compare.commits.first.oid
  end

  test "fetching commits with a limit" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic", limit: 2)
    assert_equal 2, compare.commits.size
  end

  test "knowing when the limit is exceeded" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic", limit: 2)
    assert compare.commit_limit_exceeded?
  end

  test "knowing when the commit limit is not exceeded" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic", limit: 10)
    assert !compare.commit_limit_exceeded?
  end

  test "fetching a condensed diff" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    assert_kind_of GitHub::Diff, compare.diffs
  end

  test "determining the merge-base commit" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    assert_equal "8abd54838e6ecf23cdb60fd1110f3772a878c76c", compare.merge_base
  end

  test "merge_base_commit when there is a merge-base" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    assert_equal "8abd54838e6ecf23cdb60fd1110f3772a878c76c", compare.merge_base_commit.oid
  end

  test "merge_base_commit when there is not a merge-base" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "no-merge-base")
    assert_nil compare.merge_base_commit
  end

  test "Diff correctly handles no merge-base" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "no-merge-base")
    assert_nil compare.diffs.sha1
  end

  test "knowing when there's a common ancestors between the two refs" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    refute_nil compare.merge_base
    assert compare.common_ancestor?
  end

  test "knowing when there's not a common ancestors between the two refs" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "no-merge-base")
    assert_nil compare.merge_base
    assert !compare.common_ancestor?
  end

  test "determining the relationship between the head and base refs" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    behind, ahead = compare.relationship
    assert_equal 5, behind
    assert_equal 3, ahead
  end

  test "detecting when head is ahead of base" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    assert compare.ahead?
    assert_equal 3, compare.ahead_by
  end

  test "detecting when head is not ahead of base" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", @head_sha)
    assert !compare.ahead?
    assert_equal 0, compare.ahead_by
  end

  test "detecting when head is behind base" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    assert compare.behind?
    assert_equal 5, compare.behind_by
  end

  test "detecting when head is not behind base" do
    compare = GitHub::Comparison.deprecated_build(@repo, "topic", @topic_sha)
    assert !compare.behind?
    assert_equal 0, compare.behind_by
  end

  test "detecting when head and base have diverged" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    assert_equal 3, compare.ahead_by
    assert_equal 5, compare.behind_by
    assert compare.diverged?
  end

  test "determing the comparison's status" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "ahead")
    assert_equal "ahead", compare.status
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "behind")
    assert_equal "behind", compare.status
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    assert_equal "diverged", compare.status
    compare = GitHub::Comparison.deprecated_build(@repo, @head_sha, "master")
    assert_equal "identical", compare.status
  end

  test "determining the base and head user logins when normal refs are given" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    assert_equal "turtle", compare.base_user_login
    assert_equal "turtle", compare.head_user_login
  end

  test "determining the base and head users when normal refs are given" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    assert_equal @user, compare.base_user
    assert_equal @user, compare.head_user
  end

  test "#pull_requestable? when the base and head are valid branches" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")

    assert compare.valid?
    assert compare.pull_requestable?
  end

  test "#pull_requestable? when one of the endpoints is a SHA1" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", @topic_sha)

    assert compare.valid?
    refute compare.pull_requestable?
  end

  test "#pull_requestable? when the endpoints do not have a common ancestor" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "no-merge-base")

    assert compare.valid?
    refute compare.pull_requestable?
  end

  test "#pull_requestable? when there are no commits between the endpoints" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "same-as-master")

    assert compare.valid?
    refute compare.pull_requestable?
  end

  test "master to topic branch url" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")
    assert_equal "/turtle/comparison_test/compare/master...topic", compare.to_path
  end

  test "topic branch with hash urls" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic#v1")
    assert_equal "/turtle/comparison_test/compare/master...topic%23v1", compare.to_path
  end

  test "topic branch with forward slash urls" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic/v1")
    assert_equal "/turtle/comparison_test/compare/master...topic/v1", compare.to_path
  end

  test "topic branch with semicolon urls" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic;v1")
    assert_equal "/turtle/comparison_test/compare/master...topic;v1", compare.to_path
  end

  test "topic branch with plus urls" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic+v1")
    assert_equal "/turtle/comparison_test/compare/master...topic+v1", compare.to_path
  end

  test "topic branch with period urls" do
    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic.v1")
    assert_equal "/turtle/comparison_test/compare/master...topic.v1", compare.to_path
  end

  context "#to_diff" do
    test "times out based on remaining time" do
      comparison = GitHub::Comparison.from_range(@repo, "master..topic")
      comparison.to_diff

      comparison.instance_variable_set("@timer", GitHub::TimeoutCounter.new(0.0000000001))
      assert_raises(GitRPC::Timeout) do
        comparison.to_diff
      end
    end
  end

  context "#to_patch" do
    test "times out based on remaining time" do
      comparison = GitHub::Comparison.from_range(@repo, "master..topic")
      comparison.to_patch

      comparison.instance_variable_set("@timer", GitHub::TimeoutCounter.new(0.0000000001))
      assert_raises(GitRPC::Timeout) do
        comparison.to_patch
      end
    end
  end

  context "#viewable_by?" do
    test "false if the user doesn't have access to the repository" do
      repo = create(:private_repository, owner: @user)
      rando = create(:user)

      compare = GitHub::Comparison.deprecated_build(repo, "master", "master")
      refute compare.viewable_by?(rando)
    end

    test "true if the user has access to the repository" do
      compare = GitHub::Comparison.deprecated_build(@repo, "master", "master")
      assert compare.viewable_by?(@user)
    end

    test "false if the installation doesn't have access to the repository" do
      other_repo = create(:private_repository, owner: @user)
      app = create(:integration, default_permissions: { "contents" => "read" })

      access = app.grant(@user)
      @user.oauth_access = access

      compare = GitHub::Comparison.deprecated_build(other_repo, "master", "master")
      refute compare.viewable_by?(@user)
    end

    test "true if the installation has access to the repository" do
      other_repo = create(:private_repository, owner: @user)
      app = create(:integration, default_permissions: { "contents" => "read" })
      installation = make_integration_installation(target: @user, repository: other_repo, integration: app)

      access = app.grant(@user)
      @user.oauth_access = access

      compare = GitHub::Comparison.deprecated_build(other_repo, "master", "master")
      assert compare.viewable_by?(@user)
    end

    test "false if the site-scoped installation doesn't have access to the repository" do
      app = create_unlimited_global_integration(
        permissions: {
          "metadata" => :read,
          "contents" => :read,
        },
      )
      disable_feature_flag(:disabled_global_apps, app)

      other_repo = create(:private_repository, owner: @user)
      access = app.grant(@user)
      app.grant_repository_scoped_installation_on(access, repository_id: @repo.id)
      @user.oauth_access = access

      compare = GitHub::Comparison.deprecated_build(other_repo, "master", "master")
      refute compare.viewable_by?(@user)
    end

    test "true if the site-scoped installation has access to the repository" do
      app = create_unlimited_global_integration(
        permissions: {
          "metadata" => :read,
          "contents" => :read,
        },
      )
      disable_feature_flag(:disabled_global_apps, app)

      other_repo = create(:private_repository, owner: @user)
      access = app.grant(@user)
      app.grant_repository_scoped_installation_on(access, repository_id: other_repo.id)
      @user.oauth_access = access

      compare = GitHub::Comparison.deprecated_build(other_repo, "master", "master")
      assert compare.viewable_by?(@user)
    end
  end

  test "hydro object should have UTF-8 encoding when comparing branches" do
    main_branch = "main-😀"
    feature_branch = "feature-😀"

    comparison = GitHub::Comparison.from_range_or_ref(@repo, "#{main_branch}..#{feature_branch}", limit: 250, user: @user)

    expected_for_hydro = {
      base_repo: "turtle/comparison_test",
      base_ref: main_branch,
      head_repo: "turtle/comparison_test",
      head_ref: feature_branch,
      number_of_commits: 1,
      number_of_files: 1,
      number_of_contributors: 1
    }

    # UTF-8
    assert_equal expected_for_hydro, comparison.click_tracking_attributes
    assert_equal Encoding::UTF_8, comparison.click_tracking_attributes[:base_ref].encoding
    assert_equal Encoding::UTF_8, comparison.click_tracking_attributes[:head_ref].encoding

    # ASCII-8BIT
    refute_equal main_branch.b, comparison.click_tracking_attributes[:base_ref]
    refute_equal feature_branch.b, comparison.click_tracking_attributes[:head_ref]
  end

  test "alias for base_ref and head_ref should have raw encoding when comparing branches" do
    main_branch = "main-😀"
    feature_branch = "feature-😀"

    comparison = GitHub::Comparison.from_range_or_ref(@repo, "#{main_branch}..#{feature_branch}", limit: 250, user: @user)

    assert_equal main_branch.b, comparison.base_ref
    assert_equal feature_branch.b, comparison.head_ref
    assert_equal Encoding::ASCII_8BIT, comparison.base_ref.encoding
    assert_equal Encoding::ASCII_8BIT, comparison.head_ref.encoding
  end
end

class ComparisonCrossRepositoryTest < GitHub::TestCase

  fixtures do
    @ari = create(:user, login: "ari")
    @bwalsh = create(:user, login: "bwalsh")
    @source = create(:repository, name: "medellin", owner: @ari, from_example: :comparison_source)
    @fork = create(:fork_repository, forker: @bwalsh, fork_repo: @source, from_example: :comparison_fork)
    example_repo_snapshot
  end

  setup do
    example_repo_snapshot
    @head_sha   = "a270ea0fdfba2bd5a33934e5184784cddce87f38"   # ari/master
    @topic_sha  = "480d4f47447129f015cb327536c522ca683939a1"   # bwalsh/topic
  end

  def default_comparison
    GitHub::Comparison.build(
      base_repo: @source,
      head_repo: @fork,
      base_revision: "master",
      head_revision: "topic",
    )
  end

  test "determining the head user login with an extended ref" do
    compare = GitHub::Comparison.deprecated_build(@source, "master", "bwalsh:topic")
    assert_equal "ari",    compare.base_user_login
    assert_equal "master", compare.base_ref
    assert_equal "bwalsh", compare.head_user_login
    assert_equal "topic",  compare.head_ref
  end

  test "knows when it's crossing repos" do
    compare = GitHub::Comparison.deprecated_build(@fork, "ari:master", "topic")
    assert compare.cross_repository?
  end

  test "knows when it's not crossing repos" do
    compare = GitHub::Comparison.deprecated_build(@fork, "master", "topic")
    assert !compare.cross_repository?
  end

  test "sets up GIT_ALTERNATE_OBJECT_DIRECTORIES" do
    repo1 = create(:repository, name: "repo1", owner: @ari, from_example: :comparison_source)
    # partially create a fork but don't finish the orchestration, so the shared storage is not yet enabled
    # rubocop:disable GitHub/UseCreateForkRepositoryFactory
    repo2, _ = repo1.fork(forker: @bwalsh)
    refute repo1.network.shared_storage_enabled?

    compare = GitHub::Comparison.deprecated_build(repo2, "ari:master", "topic")
    repo = compare.compare_repository
    alternates = ["#{repo1.shard_path}/objects"]
    assert_equal alternates, repo.rpc.options[:alternates]
  end

  test "sets up GIT_ALTERNATE_OBJECT_DIRECTORIES when shared storage enabled" do
    @fork.enable_shared_storage
    @source.enable_shared_storage
    assert @source.network.shared_storage_enabled?

    compare = GitHub::Comparison.deprecated_build(@fork, "ari:master", "topic")
    repo = compare.compare_repository
    alternates = ["#{@source.shard_path}/objects", "#{@source.network.shared_storage_path}/objects"]
    assert_equal alternates, repo.rpc.options[:alternates]
  end

  test "calculating SHA1s for base and head refs" do
    compare = GitHub::Comparison.deprecated_build(@fork, "ari:master", "bwalsh:topic")
    assert_equal @head_sha, compare.base_sha
    assert_equal @topic_sha, compare.head_sha
  end

  test "fetching commits" do
    compare = GitHub::Comparison.deprecated_build(@fork, "ari:master", "topic")
    assert_equal 3, compare.commits.size
    assert_equal @topic_sha, compare.commits.last.oid
    assert_equal "fb8529318277cb4dc3148ed5d0e15a61fa9d0591", compare.commits.first.oid
  end

  test "fetching a condensed diff" do
    compare = GitHub::Comparison.deprecated_build(@fork, "ari:master", "topic")
    assert_kind_of GitHub::Diff, compare.diffs
    assert_equal 18, compare.diffs.size
  end

  test "returning nil SHA when a ref can't be resolved" do
    compare = GitHub::Comparison.deprecated_build(@fork, "master", "DONTEXIST")
    assert_nil compare.head_sha
  end

  test "#merged? on a comparison where the head is ahead but is also hella behind" do
    repo = create(:repository, from_example: :hella_behind_yet_still_ahead)

    comparison = GitHub::Comparison.deprecated_build(repo, "master", "topic")

    assert !comparison.merged?
  end

  test "master to cross repo topic branch url" do
    compare = GitHub::Comparison.deprecated_build(@source, "master", "bwalsh:topic")
    assert_equal "/ari/medellin/compare/master...bwalsh:topic", compare.to_path
  end

  test "topic cross repo branch with hash urls" do
    compare = GitHub::Comparison.deprecated_build(@source, "master", "bwalsh:topic#v1")
    assert_equal "/ari/medellin/compare/master...bwalsh:topic%23v1", compare.to_path
  end

  test "topic cross repo branch with forward slash urls" do
    compare = GitHub::Comparison.deprecated_build(@source, "master", "bwalsh:topic/v1")
    assert_equal "/ari/medellin/compare/master...bwalsh:topic/v1", compare.to_path
  end

  test "topic cross repo branch with semicolon urls" do
    compare = GitHub::Comparison.deprecated_build(@source, "master", "bwalsh:topic;v1")
    assert_equal "/ari/medellin/compare/master...bwalsh:topic;v1", compare.to_path
  end

  test "topic cross repo branch with plus urls" do
    compare = GitHub::Comparison.deprecated_build(@source, "master", "bwalsh:topic+v1")
    assert_equal "/ari/medellin/compare/master...bwalsh:topic+v1", compare.to_path
  end

  test "topic cross repo branch with period urls" do
    compare = GitHub::Comparison.deprecated_build(@source, "master", "bwalsh:topic.v1")
    assert_equal "/ari/medellin/compare/master...bwalsh:topic.v1", compare.to_path
  end

  test "forked topic branch to cross repo parent" do
    compare = GitHub::Comparison.deprecated_build(@source, "bwalsh:master", "topic")
    assert_equal "/ari/medellin/compare/bwalsh:master...topic", compare.to_path
  end

  test "#valid? is false in a public repo comparison when the head commit is in the cache but not in the base repository" do
    example_repo_snapshot

    # Use the cache for the GitRPC cache.
    enable_cache_storage

    metadata = { message: "blah", committer: @fork.owner }
    commit = @fork.heads.find("topic").append_commit(metadata, @fork.owner) {}

    # commit should not be in the base repo
    refute @source.rpc.object_exists?(commit.oid, "commit")

    # but it should be in the cache
    assert @source.rpc.cache.get(commit.gitrpc_cache_key)

    comparison = GitHub::Comparison.deprecated_build(@source, "master", commit.oid)
    refute comparison.valid?

    reset_cache
    disable_cache_storage
    example_repo_restore
  end

  context "#async_covers_commit?" do
    test "true for commits inside the range of the pull" do
      comparison = default_comparison
      head_commit = @fork.heads.find("topic").target
      assert comparison.async_covers_commit?(head_commit.oid).sync
      assert comparison.async_covers_commit?(head_commit.parent_oids.first).sync
    end

    test "true for the merge base of the pull request" do
      comparison = default_comparison
      assert comparison.async_covers_commit?(comparison.merge_base).sync
    end

    test "true for the commit prior to the first introduced by the pull request" do
      comparison = default_comparison
      prior_to_head_commit = @fork.heads.find("topic").target.parent_oids.first
      assert comparison.async_covers_commit?(prior_to_head_commit).sync
    end

    test "false for commits that are not part of the pull request" do
      comparison = default_comparison
      base_commit = @source.commits.find(comparison.merge_base)
      refute comparison.async_covers_commit?(base_commit.parent_oids.first).sync
    end
  end
end

class ComparisonCrossWorkspaceTest < GitHub::TestCase
  fixtures do
    @actor = create(:user)
    @org = create(:organization, admin: @actor)
    @repo = create(:repository, owner: @org, from_example: :simple)

    @advisory = create(:repository_advisory, repository: @repo, author: @actor)

    only = [RepositoryCloneJob]
    @workspace_repo = perform_enqueued_jobs(only: only) do
      GitHub.context.push(actor_id: @actor.id)
      RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @actor).tap(&:save!).tap(&:reload)
    end

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "is valid when no branch is ahead" do
    comparison = GitHub::Comparison.from_range(
      @workspace_repo, "#{@workspace_repo.owner}:master...#{@repo.owner}:master"
    )

    assert_equal @workspace_repo, comparison.repo
    assert_equal @repo, comparison.base_repo
    assert_equal @workspace_repo, comparison.head_repo

    assert_equal "master", comparison.base_revision
    assert_equal "master", comparison.head_revision

    assert_predicate comparison, :valid?
  end

  test "is valid when head branch is ahead" do
    ref = @workspace_repo.heads.find("master")
    commit = ref.append_commit({ message: "foobar", committer: @actor }, @actor) do |files|
      files.add("README.md", "change")
    end

    comparison = GitHub::Comparison.from_range(
      @workspace_repo, "#{@repo.owner}:master...#{@workspace_repo.owner}:master"
    )

    assert_predicate comparison, :valid?
    assert_equal commit.oid, comparison.head_sha
  end

  test "is valid after workspace fetches from ahead base branch" do
    disable_feature_flag(:disable_xnetwork_fetch)
    ref = @repo.heads.find("master")
    commit = ref.append_commit({ message: "foobar", committer: @actor }, @actor) do |files|
      files.add("README.md", "change")
    end

    comparison = GitHub::Comparison.from_range(
      @workspace_repo, "#{@repo.owner}:master...#{@workspace_repo.owner}:master"
    )

    refute_predicate comparison, :valid?

    @workspace_repo.fetch_workspace_base_ref!(base_sha: comparison.base_sha)
    assert_predicate comparison, :valid?
    assert_equal commit.oid, comparison.base_sha
  end

  test "returns correct qualified ref strings" do
    comparison = GitHub::Comparison.from_range(
      @workspace_repo, "#{@repo.owner}:master2...#{@workspace_repo.owner}:master"
    )

    assert_equal comparison.qualified_head_ref, "#{@workspace_repo.owner}:master"
    assert_equal comparison.qualified_head_ref(include_repo: true), "#{@workspace_repo.owner}:#{@workspace_repo.name}:master"
    assert_equal comparison.qualified_base_ref, "#{@repo.owner}:master2"
    assert_equal comparison.qualified_base_ref(include_repo: true), "#{@repo.owner}:#{@repo.name}:master2"
  end

  test "is valid with pull request" do
    ref = @workspace_repo.heads.find("master")
    ref.append_commit({ message: "blah", committer: @actor }, @actor) do |files|
      files.add("README.md", "change")
    end

    pull_request = PullRequest.new(
      repository:      @workspace_repo,
      base_repository: @repo,
      base_user:       @repo.owner,
      base_ref:        "master",
      head_repository: @workspace_repo,
      head_user:       @workspace_repo.owner,
      head_ref:        "master",
      issue:           create(:issue, user: @actor, repository: @workspace_repo),
      user:            @actor,
    )

    assert_predicate pull_request, :valid?

    comparison = GitHub::Comparison.build(
      base_repo: pull_request.base_repository,
      head_repo: pull_request.head_repository,
      base_revision: "master",
      head_revision: "master",
      pull: pull_request,
    )

    assert_predicate comparison, :valid?
  end
end

class ComparisonUserTest < GitHub::TestCase
  test "returns correct login for base and head users in multi-tenant environment" do
    on_multi_tenant_enterprise
    enable_feature_flag(:tenant_namespacing)
    @user = create(:emu)
    @business = @user.enterprise_managed_business
    @org = create(:organization, business: @business, admin: @user)
    @repo = create(:repository, owner: @org, admin: @user, from_example: :comparison_fork)
    GitHub::CurrentTenant.set(@business)

    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")

    assert_equal @org.display_login, compare.head_user_login
    assert_equal @org.display_login, compare.head_user.display_login
    assert_equal @org.display_login, compare.base_user_login
    assert_equal @org.display_login, compare.base_user.display_login
    GitHub::CurrentTenant.remove
  end

  test "returns correct login for base and head users in dotcom environment" do
    @user = create(:user)
    @org = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org, admin: @user, from_example: :comparison_fork)

    compare = GitHub::Comparison.deprecated_build(@repo, "master", "topic")

    assert_equal @org.display_login, compare.head_user_login
    assert_equal @org.display_login, compare.head_user.display_login
    assert_equal @org.display_login, compare.base_user_login
    assert_equal @org.display_login, compare.base_user.display_login
  end
end
