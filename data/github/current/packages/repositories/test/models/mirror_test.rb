# typed: true
# frozen_string_literal: true

require "test_helper"

class MirrorTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @remote =
      create(:repository,
        owner: create(:user, login: "apache"),
        name: "httpd",
      )
    @repo =
      create(:repository,
        owner: create(:user, login: "somescro"),
        name: "httpd",
      )
  end

  setup do
    GitHub.cache.clear
    GitHub.cache.allow = /./
    example_repo :simple, @repo
    GitHub::flipper[:repository_mirror_limit_deleted_refs].disable(@repo)
  end

  test "url is required" do
    mirror = @repo.create_mirror(url: nil)
    refute mirror.valid?
  end

  test "http mirrors are ok" do
    mirror = @repo.create_mirror(url: "http://example.org/httpd3.git")
    assert mirror.valid?
  end

  test "git mirrors are ok" do
    mirror = @repo.create_mirror(url: "git://example.com/httpd2.git")
    assert mirror.valid?
  end

  test "github mirrors are not ok" do
    mirror = @repo.create_mirror(url: "git://#{GitHub.host_name}/httpd2.git")
    refute mirror.valid?
  end

  test "ftp mirrors are not ok" do
    mirror = @repo.create_mirror(url: "ftp://example.org/httpd.git")
    refute mirror.valid?
  end

  test "whitespace is stripped from the URL before validation" do
    mirror = @repo.create_mirror(url: "  http://example.org/httpd3.git  ")
    assert_equal "http://example.org/httpd3.git", mirror.url
    assert mirror.valid?
  end

  test "updates the mirror record's timestamp" do
    before = 10.seconds.ago
    mirror = @repo.create_mirror(url: "git://example.hax/httpd.git", created_at: before, updated_at: before)
    updated = mirror.updated_at
    mirror.perform
    assert mirror.updated_at > updated
  end

  [nil, "robut"].each do |pusher|
    test "mirrors with pusher set to #{pusher.inspect}" do
      GitHub.mirror_pusher = pusher

      mirror = @repo.create_mirror(url: "git://example.org/httpd.git")
      GitRPC::Client.any_instance.expects(:fetch_for_mirror)
                                 .times(GitHub.dgit_default_copies)
                                 .with { |_, _, _, env| env["GIT_PUSHER"] == pusher }
                                 .returns({})
      mirror.perform!
    end
  end

  test "mirrors a real repo" do
    example_repo :simple, @repo
    example_repo :mirror_test, @remote
    @repo.correct_hooks_symlink
    refute_same_elements @repo.all_refs.map(&:qualified_name), @remote.all_refs.map(&:qualified_name), "repos should be different before mirror"
    mirror = @repo.create_mirror(url: "git://example.org/httpd.git")

    deletes = %w{refs/heads/-gh-pages refs/heads/cr-line-endings refs/tags/v1 refs/tags/v2}
    adds = %w{refs/heads/ahead refs/heads/behind refs/heads/topic refs/tags/foo-tag}
    changes = %w{refs/heads/master}

    ref_args = deletes.map  { |ref| [ref, @repo.refs[ref].sha, GitHub::NULL_OID] }
    ref_args += adds.map    { |ref| [ref, GitHub::NULL_OID, @remote.all_refs[ref].sha] }
    ref_args += changes.map { |ref| [ref, @repo.refs[ref].sha, @remote.refs[ref].sha] }

    Timecop.freeze do
      3.times do   # repeat to make sure no-ops are ok
        # Use a fresh copy of the repo and mirror, like
        # the job does, so that any instance variables aren't
        # hanging on from the last run.
        mirror = Repository.find(@repo.id).mirror
        mirror.stubs(:url).returns(@remote.local_url)
        T.must(mirror).perform!

        # Make sure @remote and @repo now have exactly the same refs
        @repo.clear_ref_cache
        remote_non_pulls = @remote.all_refs.select { |ref| ref.qualified_name.start_with?("refs/heads", "refs/tags") }
        assert_same_elements remote_non_pulls.map(&:qualified_name), @repo.all_refs.map(&:qualified_name)
        remote_non_pulls.each do |ref|
          assert_equal ref.sha, @repo.all_refs[ref.qualified_name].sha
        end

        # Make sure no temp refs stuck around.
        assert_equal [], @repo.all_refs.select { |ref| ref.qualified_name.index("__gh__") }

      end

      unless GitHub.enterprise?
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          assert_hydro_published_partial({
            path: @repo.shard_path,
            pusher: "hubot",
            ref_updates: ref_args.map { |ref, before, after| { ref: ref, before: before, after: after } },
            pushed_at: Time.current,
          }, schema: "github.repositories.v1.Pushed")
        end


      end
    end
  end

  test "doesn't clobber svn or pull refs" do
    example_repo :simple, @repo
    example_repo :mirror_test, @remote
    mirror = @repo.create_mirror(url: "git://example.org/httpd.git")
    mirror.stubs(:url).returns(@remote.local_url)

    test_refs = %w[refs/pull/1/head refs/pull/1/merge refs/__gh__/svn/v4 refs/__gh__/svn/v4-beta5]
    oid = @repo.refs["master"].sha
    assert oid, "master shouldn't be nil"
    test_refs.each do |name|
      @repo.refs.create(name, oid, @repo.owner)
    end

    mirror.perform!

    # Make sure the test refs didn't get clobbered.
    @repo.reset_refs
    repo_refs = IO.popen(["git", "ls-remote", @repo.shard_path]).read
    test_refs.each do |name|
      assert !@remote.all_refs.include?(name), "remote shouldn't have #{name}"
      assert @repo.all_refs[name], "local ref #{name} is missing"
      assert_equal oid, @repo.all_refs[name].sha
      assert repo_refs.index(name), "#{name} not found in ls-remotes output: #{repo_refs.inspect}"
    end
  end

  test "doesn't mirror pull refs" do
    example_repo :simple, @repo
    example_repo :mirror_test, @remote
    mirror = @repo.create_mirror(url: "git://example.org/httpd.git")
    mirror.stubs(:url).returns(@remote.local_url)

    local_oid = @repo.refs["master"].sha
    assert local_oid, "master shouldn't be nil"
    local_refs = %w[refs/pull/1/head refs/pull/1/merge refs/pull/2/head refs/pull/2/merge]
    local_refs.each do |name|
      @repo.refs.create(name, local_oid, @repo.owner)
    end

    remote_oid = @remote.refs["master"].sha
    assert remote_oid, "master shouldn't be nil"
    remote_refs = %w[refs/pull/2/head refs/pull/2/merge refs/pull/3/head refs/pull/3/merge]
    remote_refs.each do |name|
      @remote.refs.create(name, remote_oid, @remote.owner)
    end

    mirror.perform!

    # Make sure the local pull refs were preserved, and the remote pull
    # refs were not copied.
    @repo.reset_refs
    repo_refs = IO.popen(["git", "ls-remote", @repo.shard_path]).read
    local_refs.each do |name|
      assert_equal local_oid, @repo.all_refs[name].sha
      assert repo_refs.index(name), "#{name} not found in ls-remotes output: #{repo_refs.inspect}"
    end
    absent_refs = remote_refs - local_refs
    absent_refs.each do |name|
      assert_nil @repo.all_refs[name], "#{name} should not be present"
      assert_nil repo_refs.index(name), "#{name} should not be in ls-remotes output: #{repo_refs.inspect}"
    end
  end

  test "only mirrors heads, tags, and branch_heads" do
    example_repo :simple, @repo
    example_repo :mirror_test, @remote

    mirror = @repo.create_mirror(url: "git://example.org/httpd.git")
    mirror.stubs(:url).returns(@remote.local_url)

    remote_oid = @remote.refs["master"].sha
    assert remote_oid, "master shouldn't be nil"
    ignore_remote_refs = %w[refs/changes/a refs/changes/other]
    ignore_remote_refs.each do |name|
      @remote.refs.create(name, remote_oid, @remote.owner)
    end

    @remote.refs.create("refs/branch-heads/hello", remote_oid, @remote.owner)

    mirror.perform!

    # Make sure the local pull refs were preserved, and the remote pull
    # refs were not copied.
    @repo.reset_refs

    ignore_remote_refs.each do |ref|
      assert_nil @repo.all_refs[ref]
    end

    assert @repo.all_refs["refs/branch-heads/hello"], "branch-heads ref should be present"
  end

  test "maintains correct HEAD reference with limited refs" do
    example_repo :simple, @repo
    example_repo :mirror_test, @remote

    mirror = @repo.create_mirror(url: "git://example.org/httpd.git")
    mirror.stubs(:url).returns(@remote.local_url)

    remote_oid = @remote.refs["master"].sha
    assert remote_oid, "master shouldn't be nil"

    mirror.perform!

    # Make sure the local pull refs were preserved, and the remote pull
    # refs were not copied.
    @repo.reset_refs
    assert_equal "master", @repo.default_branch
  end

  ["refs/heads/master", "refs/heads/cr-line-endings", "c1800491d95c42b4e96fb83f31fe8d9230c62907"].each do |local_head|
    ["refs/heads/master", "refs/heads/topic", "846f56a60795f112b506eecea9c6d98b25accb5a"].each do |remote_head|
      test "mirrors remote HEAD local=#{local_head} remote=#{remote_head}" do
        example_repo :simple, @repo
        example_repo :mirror_test, @remote
        @repo.rpc.fs_write("HEAD", make_head(local_head))
        @remote.rpc.fs_write("HEAD", make_head(remote_head))
        mirror = @repo.create_mirror(url: "git://example.org/httpd.git")
        mirror.stubs(:url).returns(@remote.local_url)
        mirror.perform!

        if remote_head !~ /^refs/  # detached remote HEAD defaults to main locally
          assert_equal "refs/heads/main", @repo.get_default_branch
        else
          # Check OIDs for all refs, including HEAD
          remote_refs = IO.popen(["git", "ls-remote", @remote.shard_path]).readlines.delete_if do |str|
            str =~ %r{\trefs/} && !(str =~ %r{\trefs/(heads|tags)})
          end.join
          repo_refs   = IO.popen(["git", "ls-remote", @repo.shard_path]).read
          assert_equal remote_refs, repo_refs
          # Check symbolic value of HEAD
          remote_refpath = @remote.get_default_branch
          repo_refpath   = @repo.get_default_branch
          assert_equal remote_refpath, repo_refpath
        end
      end
    end
  end

  def make_head(val)
    if val =~ /^[0-9a-f]{40}$/
      "#{val}\n"
    elsif val =~ /^refs\//
      "ref: #{val}\n"
    else
      raise "wat HEAD value #{val.inspect}"
    end
  end
end
