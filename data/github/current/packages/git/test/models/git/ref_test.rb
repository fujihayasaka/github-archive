# typed: true
# frozen_string_literal: true

require "test_helper"

class GitRefTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user, login: "rick")
    @other_user = create(:user)
    @encodings_repo = create(:repository, owner: @user, from_example: :encodings)
    @encodings_repo.add_member @other_user, action: :write

    # create a branch to assert on.
    @encodings_repo.extended_refs.create("refs/heads/ref-update-test", @encodings_repo.heads.read("test-branch~").sha, @user)

    @refs_test_repo = create :repository, owner: @user, from_example: :refs_test

    # these mirror the refs structure in the refs_test.git example repository
    @expected_refs = {
      "refs/heads/master"            => "1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec",
      "refs/heads/diverge"           => "2ce644d5f6badcfb2320dc54702c9b9f686888fb",
      "refs/heads/lazy_delegator"    => "86264f45ff4bcd3da195f5c83f7e414ed4a71628",
      "refs/tags/rakefile"           => "72fde8c9ca87a1c992ce992bab13c3c4f13cddb9",
      "refs/tags/v1.0"               => "02a2cfc6b8fcecfa7f045bdc014eb2ae7191fb2d",
    }
    @target_oid = @expected_refs["refs/heads/master"]
    @other_oid = @expected_refs["refs/heads/diverge"]

    example_repo_snapshot
  end

  setup do
    example_repo_restore
    @encodings_repo.unlock!
    @encodings_repo.protected_branches.delete_all
    @encodings_repo.save!

    @ref = Git::Ref.new(@refs_test_repo, "refs/heads/master", @expected_refs["refs/heads/master"])
    @tag_ref = Git::Ref.new(@refs_test_repo, "refs/tags/v1.0", @expected_refs["refs/tags/v1.0"])
    @branch_ref = Git::Ref.new(@refs_test_repo, "refs/heads/lazy_delegator", @expected_refs["refs/heads/lazy_delegator"])
    @new_ref = Git::Ref.new(@refs_test_repo, "refs/heads/new-branch")
    @blob_ref = Git::Ref.new(@refs_test_repo, "refs/tags/rakefile", @expected_refs["refs/tags/rakefile"])
  end

  context "#default_branch?" do
    test "default branches are default even when unicode" do
      @encodings_repo.update_default_branch("unicode-文字化け".b)
      ref = @encodings_repo.refs.find("unicode-文字化け".b)
      assert ref.default_branch?
    end
  end

  context "#update" do
    test "updating a ref successfully" do
      example_repo :refs_test, @refs_test_repo

      target = @refs_test_repo.objects.read(@other_oid)
      Timecop.freeze do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          @ref.update(target, @user)

          assert_equal @other_oid, @refs_test_repo.refs["master"].target_oid
          assert_equal @other_oid, @refs_test_repo.ref_to_sha("master")

          assert_equal target, @ref.target
          assert_equal target.oid, @ref.target_oid

          assert_hydro_published_partial({
            path: @refs_test_repo.shard_path,
            pusher: @user.login,
            pushed_at: Time.current,
            ref_updates: [{ ref: @ref.qualified_name, before: @target_oid, after: @other_oid }] },
            schema: "github.repositories.v1.Pushed")
        end
      end
    end

    test "updating a ref handles git_error in rule engine" do
      example_repo :refs_test, @refs_test_repo
      RuleEngine::Rules::UpdateRule.any_instance.stubs(:evaluate).raises(GitRPC::ObjectMissing)

      ruleset = create(:repository_ruleset, :targets_all_branches, source: @refs_test_repo)
      create(:repository_rule_configuration, :update, repository_ruleset: ruleset)

      target = @refs_test_repo.objects.read(@other_oid)

      assert_raises(Git::Ref::ProtectedBranchUpdateError) do
        @ref.update(target, @user)
      end
    end

    test "updating a ref with :post_receive false" do
      @ref.repository.stubs(:backups_enabled?).returns(true)
      @refs_test_repo.update_attribute(:pushed_at, 1.day.ago)

      example_repo :refs_test, @refs_test_repo

      target = @refs_test_repo.objects.read(@other_oid)

      assert_enqueued_jobs(1, only: RepositoryBackupNgJob, queue: :gitbackups_perform) do
        @ref.update(target, @user, post_receive: false)

        assert_equal @other_oid, @refs_test_repo.refs["master"].target_oid
        assert_equal @other_oid, @refs_test_repo.ref_to_sha("master")

        assert_equal target, @ref.target
        assert_equal target.oid, @ref.target_oid
      end

      enqueued_job = enqueued_jobs.find { |j| j[:job] == RepositoryBackupNgJob }
      enqueued_args = enqueued_job["arguments"]
      assert_equal @refs_test_repo.id, enqueued_args[0]
      assert_equal "repository", enqueued_args[1]["value"]
      assert_in_delta Time.now, enqueued_args[2]["pushed_at"]["value"].to_time, 5.seconds

      @refs_test_repo.reload
      assert @refs_test_repo.pushed_at > 1.hour.ago
    end

    test "updating a ref anonymously" do
      anonymous = { name: "Anonymous", email: "anonymous@github.com" }
      gist = Gist::Creator.create!(user: @user, contents: [{ name: "foo", value: "bar" }])
      example_repo :refs_test, gist

      ref = Git::Ref.new(gist, "refs/heads/master", @target_oid)
      target = gist.objects.read(@other_oid)

      Timecop.freeze do
        args = [gist.shard_path, nil, [[ref.qualified_name, @target_oid, @other_oid]], Time.current, nil, nil]
        assert_enqueued_with(job: GistPushJob, args: args, queue: "gist_push") do
          ref.update(target, anonymous)

          assert_equal @other_oid, gist.refs["master"].target_oid
          assert_equal @other_oid, gist.ref_to_sha("master")

          assert_equal target, ref.target
          assert_equal target.oid, ref.target_oid
        end
      end
    end

    test "updating a ref that doesnt exist yet" do
      example_repo :refs_test, @refs_test_repo
      target = @refs_test_repo.objects.read(@other_oid)
      assert @new_ref.update(target, @user)
      assert_equal @other_oid, @refs_test_repo.refs[@new_ref.qualified_name].target_oid
      assert_equal @other_oid, @refs_test_repo.ref_to_sha(@new_ref.qualified_name)
    end

    test "updating a ref fails with bad CAS update" do
      assert_enqueued_jobs 0 do
        example_repo :refs_test, @refs_test_repo
        @refs_test_repo.expects(:clear_ref_cache).never
        RefUpdater.update_ref(@refs_test_repo, @ref.qualified_name, @other_oid)
        target = @refs_test_repo.objects.read(@target_oid)
        exception = assert_raises(Git::Ref::ComparisonMismatch) { @ref.update(target, @user) }
        assert_equal "github-ref-errors", exception.failbot_context[:app]
        assert_match %r{(refs/heads/master )?is at 2ce644d5f6badcfb2320dc54702c9b9f686888fb but expected 1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec}, exception.message
      end
    end

    test "updating a ref that doesn't exist with a SHA-like name fails" do
      example_repo :refs_test, @refs_test_repo
      target = @refs_test_repo.objects.read(@other_oid)
      ref = Git::Ref.new(@refs_test_repo, "refs/heads/d554d883b545180e2abdb51fbab5f204ba6ec638")

      assert_raises(Git::Ref::InvalidName) do
        ref.update(target, @user)
      end

      assert_nil @refs_test_repo.heads.find("d554d883b545180e2abdb51fbab5f204ba6ec638")
    end

    context "options[:force]" do
      test "non-fast-forwardable update accepted when no value passed (default is force=true)" do
        oid_before = @encodings_repo.refs.read("ref-update-test").sha
        non_fast_forwardable_oid = @encodings_repo.heads.read("test-branch~~").sha

        assert_equal(oid_before, @encodings_repo.refs.read("ref-update-test").sha)
        @encodings_repo.refs["ref-update-test"].update(non_fast_forwardable_oid, @user)
        assert_equal(non_fast_forwardable_oid, @encodings_repo.refs.read("ref-update-test").sha)
      end

      test "non-fast-forwardable update accepted when force=true" do
        oid_before = @encodings_repo.refs.read("ref-update-test").sha
        non_fast_forwardable_oid = @encodings_repo.heads.read("test-branch~~").sha

        assert_equal(oid_before, @encodings_repo.refs.read("ref-update-test").sha)
        @encodings_repo.refs["ref-update-test"].update(non_fast_forwardable_oid, @user, force: true)
        assert_equal(non_fast_forwardable_oid, @encodings_repo.refs.read("ref-update-test").sha)
      end

      test "non-fast-forwardable update rejected when force=false" do
        oid_before = @encodings_repo.refs.read("ref-update-test").sha
        non_fast_forwardable_oid = @encodings_repo.heads.read("test-branch~~").sha

        assert_equal(oid_before, @encodings_repo.refs.read("ref-update-test").sha)
        assert_raises(Git::Ref::NotFastForward) do
          @encodings_repo.refs["ref-update-test"].update(non_fast_forwardable_oid, @user, force: false)
        end
        assert_equal(oid_before, @encodings_repo.refs.read("ref-update-test").sha)
      end

      test "fast-forwardable update allowed when force=false" do
        oid_before = @encodings_repo.refs.read("ref-update-test").sha
        fast_forwardable_oid = @encodings_repo.refs.read("test-branch").sha

        assert_equal(oid_before, @encodings_repo.refs.read("ref-update-test").sha)
        @encodings_repo.refs["ref-update-test"].update(fast_forwardable_oid, @user, force: false)
        assert_equal(fast_forwardable_oid, @encodings_repo.refs.read("ref-update-test").sha)
      end

      test "fast-forwardable update allowed when force=true" do
        oid_before = @encodings_repo.refs.read("ref-update-test").sha
        fast_forwardable_oid = @encodings_repo.refs.read("test-branch").sha

        assert_equal(oid_before, @encodings_repo.refs.read("ref-update-test").sha)
        @encodings_repo.refs["ref-update-test"].update(fast_forwardable_oid, @user, force: true)
        assert_equal(fast_forwardable_oid, @encodings_repo.refs.read("ref-update-test").sha)
      end
    end
  end

  context "#deleteable?" do
    test "is true for a non-default ref in a writable repository" do
      ref = @encodings_repo.refs.find("ref-update-test")
      assert_predicate ref, :deleteable?
    end

    test "is false when the ref does not exist" do
      ref = @encodings_repo.refs.build("does-not-exist")
      refute_predicate ref, :deleteable?
    end

    test "is false for the default branch" do
      ref = @encodings_repo.refs.build("master")
      refute_predicate ref, :deleteable?
    end

    test "is false if the repository is not writable" do
      @encodings_repo.lock_for_migration
      @encodings_repo.save!
      ref = @encodings_repo.refs.find("ref-update-test")
      refute_predicate ref, :deleteable?
    end

    test "is true when no deleter is provided and branch is protected" do
      @encodings_repo.protect_branch("ref-update-test", creator: @user, block_deletions: false, entry_point: :test_case)
      ref = @encodings_repo.refs.find("ref-update-test")
      assert_predicate ref, :deleteable?
    end

    test "is false when no deleter is provided and branch deletions are blocked" do
      # branch deletions are blocked by default
      @encodings_repo.protect_branch("ref-update-test", creator: @user, entry_point: :test_case)
      ref = @encodings_repo.refs.find("ref-update-test")
      refute_predicate ref, :deleteable?
    end

    test "is false when no deleter is provided, allows branch deletions, and the branch is locked for non-admins" do
      @encodings_repo.protect_branch("ref-update-test", creator: @user, block_deletions: false, lock_branch: true, entry_point: :test_case)
      ref = @encodings_repo.refs.find("ref-update-test")
      refute_predicate ref, :deleteable?
    end

    context "when the branch is protected, allows branch deletions, and is locked for non-admins" do
      test "is false when deleter is a non-admin" do
        @encodings_repo.protect_branch("ref-update-test", creator: @user, block_deletions: false, lock_branch: true, entry_point: :test_case)
        ref = @encodings_repo.refs.find("ref-update-test")
        refute ref.deleteable?(deleter: @other_user)
      end

      test "is true when deleter is admin" do
        @encodings_repo.protect_branch("ref-update-test", creator: @user, block_deletions: false, lock_branch: true, entry_point: :test_case)
        ref = @encodings_repo.refs.find("ref-update-test")
        assert ref.deleteable?(deleter: @user)
      end

    end

    context "when the branch is protected, allows branch deletions, and is locked for everyone" do
      test "is false when deleter is a non-admin" do
        @encodings_repo.protect_branch(
          "ref-update-test",
          creator: @user,
          block_deletions: false,
          lock_branch: true,
          enforce_admins: true,
          entry_point: :test_case
        )
        ref = @encodings_repo.refs.find("ref-update-test")
        refute ref.deleteable?(deleter: @other_user)
      end

      test "is true when deleter is admin" do
        @encodings_repo.protect_branch(
          "ref-update-test",
          creator: @user,
          block_deletions: false,
          lock_branch: true,
          enforce_admins: true,
          entry_point: :test_case
        )
        ref = @encodings_repo.refs.find("ref-update-test")
        refute ref.deleteable?(deleter: @user)
      end
    end

    test "is false if the branch is being renamed" do
      create(:repository_branch_rename, repository: @encodings_repo, old_name: "ref-update-test")
      ref = @encodings_repo.refs.find("ref-update-test")
      refute_predicate ref, :deleteable?
    end

    test "is false when the ref doesn't target a commit" do
      refute_predicate @new_ref, :deleteable?
    end

    test "is false when repository is archived" do
      @refs_test_repo.set_archived
      refute_predicate @branch_ref, :deleteable?
    end
  end

  context "#deleteable_to_complete_rename?" do
    test "is true for a non-default ref in a writable repository" do
      ref = @encodings_repo.refs.find("ref-update-test")
      assert_predicate ref, :deleteable_to_complete_rename?
    end

    test "is false when the ref does not exist" do
      ref = @encodings_repo.refs.build("does-not-exist")
      refute_predicate ref, :deleteable_to_complete_rename?
    end

    test "is false for the default branch" do
      ref = @encodings_repo.refs.build("master")
      refute_predicate ref, :deleteable_to_complete_rename?
    end

    test "is false if the repository is not writable" do
      @encodings_repo.lock_for_migration
      @encodings_repo.save!
      ref = @encodings_repo.refs.find("ref-update-test")
      refute_predicate ref, :deleteable_to_complete_rename?
    end

    test "is true if the branch is protected and does not allow branch deletion" do
      @encodings_repo.protect_branch("ref-update-test", creator: @user, entry_point: :test_case)
      ref = @encodings_repo.refs.find("ref-update-test")
      assert_predicate ref, :deleteable_to_complete_rename?
    end

    test "is true if the branch is protected and allows branch deletion" do
      @encodings_repo.protect_branch("ref-update-test", creator: @user, block_deletions: false, entry_point: :test_case)
      ref = @encodings_repo.refs.find("ref-update-test")
      assert_predicate ref, :deleteable_to_complete_rename?
    end

    test "is true if the branch is protected and locked" do
      @encodings_repo.protect_branch("ref-update-test", creator: @user, block_deletions: false, lock_branch: true, entry_point: :test_case)
      ref = @encodings_repo.refs.find("ref-update-test")
      assert_predicate ref, :deleteable_to_complete_rename?
    end

    test "is true if the branch is being renamed" do
      create(:repository_branch_rename, repository: @encodings_repo, old_name: "ref-update-test")
      ref = @encodings_repo.refs.find("ref-update-test")
      assert_predicate ref, :deleteable_to_complete_rename?
    end
  end

  context ".new" do
    test "initializing with fully qualified name and no prefix" do
      ref = Git::Ref.new(@refs_test_repo, "refs/heads/master", @target_oid)
      assert_equal "refs/heads/master", ref.qualified_name
      assert_equal "master", ref.name
      assert_equal "refs/heads/", ref.prefix
      assert_equal @target_oid, ref.target_oid
    end

    test "initializing with short name and prefix" do
      ref = Git::Ref.new(@refs_test_repo, "master", @target_oid, "refs/heads/")
      assert_equal "refs/heads/master", ref.qualified_name
      assert_equal "master", ref.name
      assert_equal "refs/heads/", ref.prefix
      assert_equal @target_oid, ref.target_oid
    end

    test "initializing with unrecognized prefixed name and no prefix" do
      ref = Git::Ref.new(@refs_test_repo, "refs/stuff/yeah", @target_oid)
      assert_equal "refs/stuff/yeah", ref.qualified_name
      assert_equal "refs/stuff/yeah", ref.name
      assert_nil ref.prefix
      assert_equal @target_oid, ref.target_oid
    end

    test "initializing with a target object" do
      target = @refs_test_repo.objects.read(@target_oid)
      Git::Ref.new(@refs_test_repo, "refs/heads/master", target)
    end

    test "repo and ref name are required" do
      assert_raises(ArgumentError) { Git::Ref.new(nil, "refs/heads/master") }
      assert_raises(ArgumentError) { Git::Ref.new(@refs_test_repo, nil) }
    end
  end

  context "#append_commit" do
    test "appending a commit to a ref" do
      example_repo :refs_test, @refs_test_repo

      @refs_test_repo.rpc.config_store("core.logAllRefUpdates", true)  # this is off by default

      committer = create(:user)
      message   = "this is a cool commit"
      path      = "brandnewfile"
      content   = "cool content"

      metadata = { message: message, committer: committer }
      @ref.append_commit(metadata, @user) do |files|
        files.add(path, content)
      end

      refute_equal @target_oid,  @ref.target_oid
      assert_equal    [@target_oid], @ref.target.parent_oids

      commit = @ref.target
      assert_equal message, commit.message
      assert_equal committer.git_author_name,  commit.committer_name
      assert_equal committer.git_author_email, commit.committer_email
      assert_equal committer.git_author_name,  commit.author_name
      assert_equal committer.git_author_email, commit.author_email

      blob = @ref.repository.blob(@ref.target_oid, path)
      assert_equal content, blob.data

      @target_oid = @ref.target_oid

      committer = create(:user)
      message   = "this is another cool commit"
      path      = "newerfile"
      content   = "cooler content"
      reflog_data = { via: "test" }

      metadata = { message: message, committer: committer }
      @ref.append_commit(metadata, @user, reflog_data: reflog_data) do |files|
        files.add(path, content)
      end

      refute_equal @target_oid,  @ref.target_oid
      assert_equal    [@target_oid], @ref.target.parent_oids

      commit = @ref.target
      assert_equal message, commit.message
      assert_equal committer.git_author_name,  commit.committer_name
      assert_equal committer.git_author_email, commit.committer_email
      assert_equal committer.git_author_name,  commit.author_name
      assert_equal committer.git_author_email, commit.author_email

      blob = @ref.repository.blob(@ref.target_oid, path)
      assert_equal content, blob.data

      reflog = @ref.repository.reflog(@ref.qualified_name)
      assert_equal 2, reflog.length

      assert_nil reflog.last.via
      assert_equal reflog_data[:via], reflog.first.via
    end

    test "updates pull reflog data from GitHub.context by default" do
      GitHub.context.push(from: "ref test", user_agent: "Mozilla something or other", actor_ip: "42.137.0.1")
      example_repo :refs_test, @refs_test_repo

      @refs_test_repo.rpc.config_store("core.logAllRefUpdates", true)  # this is off by default

      committer = create(:user)
      GitHub.context.push(actor: committer.login)
      message   = "this is a cool commit"
      path      = "brandnewfile"
      content   = "cool content"

      metadata = { message: message, committer: committer }
      @ref.append_commit(metadata, committer) do |files|
        files.add(path, content)
      end

      reflog = @ref.repository.reflog(@ref.qualified_name)
      assert_equal "ref test", reflog.first.via
      assert_equal committer.login, reflog.first.user_login
      assert_equal "Mozilla something or other", reflog.first.user_agent
      assert_equal "42.137.0.1", reflog.first.real_ip
    end

    test "updates can override aspects of default reflog data by providing their own but pull in defaults for the rest" do
      GitHub.context.push(from: "ref test", actor: "AAAAA", user_agent: "Mozilla something or other", actor_ip: "42.137.0.1")
      example_repo :refs_test, @refs_test_repo

      @refs_test_repo.rpc.config_store("core.logAllRefUpdates", true)  # this is off by default

      committer = create(:user)
      message   = "this is a cool commit"
      path      = "brandnewfile"
      content   = "cool content"
      reflog_data = { via: "override test" }
      metadata = { message: message, committer: committer }
      @ref.append_commit(metadata, @user, reflog_data: reflog_data) do |files|
        files.add(path, content)
      end

      reflog = @ref.repository.reflog(@ref.qualified_name)
      assert_equal "override test", reflog.first.via
      assert_equal "Mozilla something or other", reflog.first.user_agent
      assert_equal "42.137.0.1", reflog.first.real_ip
    end

    test "updates pass the appropriate reflog data to check_custom_hooks" do
      GitHub.context.push(from: "ref test", actor: @refs_test_repo.owner.login, user_agent: "Mozilla something or other", actor_ip: "42.137.0.1")

      Repository.any_instance.expects(:check_custom_hooks).with do |_old_oid, _new_oid, _qualified_name, options|
        options[:reflog_data][:via] == "ref test" &&
        options[:reflog_data][:user_login] == @refs_test_repo.owner.login &&
        options[:reflog_data][:user_agent] == "Mozilla something or other" &&
        options[:reflog_data][:real_ip] == "42.137.0.1" &&
        options[:reflog_data][:repo_name] == @refs_test_repo.full_name &&
        options[:reflog_data][:repo_public] == @refs_test_repo.public?
      end

      ref = Git::Ref.new(@refs_test_repo, "master", @target_oid, "refs/heads/")

      committer = create(:user)
      message   = "this is a cool commit"
      path      = "brandnewfile"
      content   = "cool content"

      metadata = { message: message, committer: committer }

      ref.append_commit(metadata, @user) do |files|
        files.add(path, content)
      end
    end
  end

  context "#exist?" do
    test "returns true if repo has the ref" do
      assert @ref.exist?
    end

    test "returns false if repo doesn't have the ref" do
      assert !@new_ref.exist?
    end
  end

  context "#well_formed?" do
    test "returns true if it passes check-ref-format" do
      assert @ref.well_formed?
    end

    test "returns false if it fails check-ref-format" do
      ref = Git::Ref.new(@refs_test_repo, "refs/heads/m a s t e r")
      assert !ref.well_formed?
    end

    test "class method" do
      refute Git::Ref.well_formed?("master\nwhoops")
    end
  end

  context "#valid?" do
    test "returns true if the ref exists" do
      assert @ref.valid?
    end

    test "returns false if the ref does not exist" do
      assert !@new_ref.valid?
    end
  end

  context "#target" do
    test "returns a commit" do
      assert object = @ref.target, "couldn't load target object #{@ref.target_oid}"
      assert object.is_a?(Commit)
      assert_equal @ref.target_oid, object.oid
    end

    test "returns nil for a new ref that does not point to a commit yet" do
      assert_nil @new_ref.target
    end

    test "raises for a ref that points to a bad commit" do
      bad_ref = Git::Ref.new(@refs_test_repo, "refs/heads/bad", ("1" * 40))
      assert_raises(GitRPC::ObjectMissing) { bad_ref.target }
    end
  end

  context "#name" do
    test "short name for branch ref" do
      assert_equal "master", @ref.name
    end

    test "short name for tag ref" do
      assert_equal "v1.0", @tag_ref.name
    end
  end

  context "#commit" do
    test "access a ref's resolved commit" do
      assert_raises(Git::Ref::UnresolveableCommit) { @blob_ref.commit }
      assert @ref.commit
      assert @tag_ref.commit
    end
  end

  context "#commit?" do
    test "check if a ref's commit is resolveable" do
      refute @blob_ref.commit?
      assert @ref.commit?
      assert @tag_ref.commit?
    end
  end

  context "#create" do
    test "creating a ref successfully" do
      example_repo :refs_test, @refs_test_repo

      ref = Git::Ref.new(@refs_test_repo, "refs/heads/new-branch")

      Timecop.freeze do
        expected_args = [@refs_test_repo.shard_path, @user.login, [[ref.qualified_name, GitHub::NULL_OID, @other_oid]], Time.current, nil, nil, nil, {}]
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          ref.create(@other_oid, @user)

          assert @refs_test_repo.refs.exist?("new-branch")
          assert_equal @other_oid, @refs_test_repo.refs["new-branch"].target_oid
          assert_equal @other_oid, @refs_test_repo.ref_to_sha("new-branch")

          assert_hydro_published_partial({
            path: @refs_test_repo.shard_path,
            pusher: @user.login,
            pushed_at: Time.current,
            ref_updates: [{ ref: ref.qualified_name, before: GitHub::NULL_OID, after: @other_oid }] },
            schema: "github.repositories.v1.Pushed")
        end
      end
    end

    test "creating a ref anonymously" do
      anonymous = { name: "Anonymous", email: "anonymous@github.com" }
      gist = Gist::Creator.create!(user: @user, contents: [{ name: "foo", value: "bar" }])
      example_repo :refs_test, gist

      ref = Git::Ref.new(gist, "refs/heads/new-branch")
      Timecop.freeze do
        args = [gist.shard_path, nil, [[ref.qualified_name, GitHub::NULL_OID, @other_oid]], Time.current, nil, nil]
        assert_enqueued_with(job: GistPushJob, args: args, queue: "gist_push") do
          ref.create(@other_oid, anonymous)

          assert gist.refs.exist?("new-branch")
          assert_equal @other_oid, gist.refs["new-branch"].target_oid
          assert_equal @other_oid, gist.ref_to_sha("new-branch")
        end
      end
    end

    test "creating a ref that already exists fails" do
      example_repo :refs_test, @refs_test_repo
      assert_raises(Git::Ref::ExistsError) { @ref.create(@other_oid, @user) }
      assert_equal @target_oid, @refs_test_repo.refs["refs/heads/master"].target_oid
    end

    test "creating a branch with a SHA-like name fails" do
      ref = Git::Ref.new(@refs_test_repo, "refs/heads/d554d883b545180e2abdb51fbab5f204ba6ec638")

      assert_raises(Git::Ref::InvalidName) do
        ref.create(@refs_test_repo.heads.find("master").target_oid, @user)
      end

      ref = Git::Ref.new(@refs_test_repo, "refs/heads/d554d883b545180e2abdb51fbab5f204ba6ec638/with_trailing_path")

      assert_raises(Git::Ref::InvalidName) do
        ref.create(@refs_test_repo.heads.find("master").target_oid, @user)
      end

      assert_nil @refs_test_repo.heads.find("d554d883b545180e2abdb51fbab5f204ba6ec638")
    end

    test "creating a tag with a SHA-like name fails" do
      ref = Git::Ref.new(@refs_test_repo, "refs/tags/d554d883b545180e2abdb51fbab5f204ba6ec638")

      assert_raises(Git::Ref::InvalidName) do
        ref.create(@refs_test_repo.heads.find("master").target_oid, @user)
      end

      ref = Git::Ref.new(@refs_test_repo, "refs/tags/d554d883b545180e2abdb51fbab5f204ba6ec638/with_trailing_path")

      assert_raises(Git::Ref::InvalidName) do
        ref.create(@refs_test_repo.heads.find("master").target_oid, @user)
      end

      assert_nil @refs_test_repo.tags.find("d554d883b545180e2abdb51fbab5f204ba6ec638")
    end

    test "creating some other ref with a SHA-like name is OK for now" do
      master_oid = @refs_test_repo.heads.find("master").target_oid
      ref = Git::Ref.new(@refs_test_repo, "refs/specialstuff/d554d883b545180e2abdb51fbab5f204ba6ec638")

      ref.create(master_oid, @user)

      assert_equal master_oid, @refs_test_repo.extended_refs.find("refs/specialstuff/d554d883b545180e2abdb51fbab5f204ba6ec638").target_oid
    end
  end

  context "#protected_branch" do
    test "only fetches protected branch info once if nil is memoized" do
      ProtectedBranch.expects(:for_repository_with_branch_names).once.returns([])

      assert_nil @branch_ref.protected_branch
      assert_nil @branch_ref.protected_branch
    end
  end

  context "#delete" do
    test "deleting a ref successfully" do
      example_repo :refs_test, @refs_test_repo

      Timecop.freeze do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          assert @ref.delete(@user)
          assert_nil @refs_test_repo.rpc.read_refs[@ref.qualified_name]
          assert_hydro_published_partial({
            path: @refs_test_repo.shard_path,
            pusher: @user.login,
            pushed_at: Time.current,
            ref_updates: [{ ref: @ref.qualified_name, before: @target_oid, after: GitHub::NULL_OID }] },
            schema: "github.repositories.v1.Pushed")
        end
      end
    end

    test "deleting a ref anonymously" do
      anonymous = { name: "Anonymous", email: "anonymous@github.com" }
      gist = Gist::Creator.create!(user: @user, contents: [{ name: "foo", value: "bar" }])
      example_repo :refs_test, gist

      ref = Git::Ref.new(gist, "refs/heads/master", @target_oid)
      Timecop.freeze do
        args = [gist.shard_path, nil, [[ref.qualified_name, @target_oid, GitHub::NULL_OID]], Time.current, nil, nil]
        assert_enqueued_with(job: GistPushJob, args: args, queue: "gist_push") do
          assert ref.delete(anonymous)
          assert_nil gist.rpc.read_refs[ref.qualified_name]
        end
      end
    end

    test "deleting a ref writes audit log data" do
      example_repo :refs_test, @refs_test_repo
      @ref.delete(@user, reflog_data: { via: "carrier-pigeon" })

      paths = DGit.paths_for_repo(@refs_test_repo)
      audit_logs = Hash[paths.map do |path|
        [path, File.read("#{path}/audit_log")]
      end]
      audit_logs.each do |path, data|
        assert_equal 1, data.split("\n").size, "#{path}/audit log should be one line:\n#{data.inspect}"
        %w{refs/heads/master "via":"carrier-pigeon"}.each do |str|
          assert_includes data, str
        end
      end
      assert_equal 1, audit_logs.values.uniq.size, "audit logs differed: #{audit_logs}"
    end

    test "deleting a missing ref" do
      assert_enqueued_jobs 0 do
        example_repo :refs_test, @refs_test_repo
        @refs_test_repo.expects(:clear_ref_cache).never
        assert_raises(Git::Ref::NotFound) { @new_ref.delete(@user) }
      end
    end

    test "deleting a ref that doesn't match the expected value" do
      assert_enqueued_jobs 0 do
        example_repo :refs_test, @refs_test_repo
        @refs_test_repo.expects(:clear_ref_cache).never
        RefUpdater.update_ref(@refs_test_repo, @ref.qualified_name, @other_oid)
        exception = assert_raises(Git::Ref::ComparisonMismatch) { @ref.delete(@user) }
        assert_match %r{(refs/heads/master )?is at 2ce644d5f6badcfb2320dc54702c9b9f686888fb but expected 1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec}, exception.message
      end
    end

  end

  context "#revert" do
    test "revert" do
      ref      = @refs_test_repo.heads.find("master")
      metadata = { message: "blah", committer: @refs_test_repo.owner }

      commit_to_revert = ref.append_commit(metadata, @refs_test_repo.owner) do |files|
        files.add("blah.txt", "blahblahblah")
      end

      refute_nil @refs_test_repo.blob(commit_to_revert.oid, "blah.txt")

      revert_commit, error = ref.revert_commit(@refs_test_repo.owner, commit_to_revert.oid)

      master_oid = @refs_test_repo.refs.find("master").target_oid

      assert_nil   error
      assert_nil   @refs_test_repo.blob(master_oid, "blah.txt")
      assert_equal revert_commit.oid, master_oid
      assert_equal [commit_to_revert.oid], revert_commit.parent_oids
    end

    test "revert when the ref has changed" do
      ref      = @refs_test_repo.heads.find("master")
      metadata = { message: "blah", committer: @refs_test_repo.owner }

      commit_to_revert = ref.append_commit(metadata, @refs_test_repo.owner) do |files|
        files.add("blah.txt", "blahblahblah")
      end

      refute_nil @refs_test_repo.blob(commit_to_revert.oid, "blah.txt")

      # grab a different ref object so the original one gets out of sync
      # when we make an additional commit
      ref_copy = Repositories::Public.find_active!(@refs_test_repo.id).heads.find("master")
      metadata = { message: "something else", committer: @refs_test_repo.owner }

      new_commit = ref_copy.append_commit(metadata, @refs_test_repo.owner) do |files|
        files.add("something_else.txt", "yea")
      end

      # the original ref object didn't change and is now out of sync
      assert_equal commit_to_revert.oid, ref.target_oid

      # but reverting magically works anyway
      revert_commit, error = ref.revert_commit(@refs_test_repo.owner, commit_to_revert.oid)

      master_oid = @refs_test_repo.refs.find("master").target_oid

      assert_nil   error
      assert_equal revert_commit.oid, master_oid
      assert_equal revert_commit.oid, ref.target_oid
      assert_nil   @refs_test_repo.blob(master_oid, "blah.txt")
      assert_equal [new_commit.oid], revert_commit.parent_oids
    end

    test "revert with a conflict" do
      ref = @refs_test_repo.heads.find("master")

      metadata = { message: "blah", committer: @refs_test_repo.owner }

      first_commit = ref.append_commit(metadata, @refs_test_repo.owner) do |files|
        files.add("blah.txt", "blahblahblah")
      end

      second_commit = ref.append_commit(metadata, @refs_test_repo.owner) do |files|
        files.add("blah.txt", "other blah blah blah yea")
      end

      revert_commit, error = ref.revert_commit(@refs_test_repo.owner, first_commit.oid)

      @refs_test_repo.reload

      assert_equal :merge_conflict, error
      assert_nil   revert_commit
      assert_equal second_commit.oid, @refs_test_repo.heads.find("master").target_oid
    end
  end

  context "#merge" do
    test "merge" do
      merger = create(:user)
      grit = create(:repository, from_example: :mojombo_grit)

      ref = grit.heads.find("master")

      # make sure ref cache is loaded, so we can verify
      # that it gets cleared/refreshed after the merge.
      assert_equal "1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec", ref.target_oid

      Timecop.freeze do
        merge_commit, error, error_message = ref.merge(
          merger,
          "lazy_delegator",
          commit_message: "Test merge commit",
          post_receive: true,
        )

        assert_nil   error
        assert_nil   error_message
        assert_equal "Test merge commit", merge_commit.message
        assert_equal %w[1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec 86264f45ff4bcd3da195f5c83f7e414ed4a71628],
                    merge_commit.parent_oids.sort
        assert_equal merge_commit.oid, grit.ref_to_sha("master")

        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          assert_hydro_published_partial(
            { path: grit.shard_path, pusher: merger.login, pushed_at: Time.current, ref_updates: [{ ref: "refs/heads/master", before: "1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec", after: merge_commit.oid }] },
            schema: "github.repositories.v1.Pushed",
            partition_key: grit.id
          )
        end

      end
    end

    test "merge when the head is already merged" do
      merger = create(:user)
      grit = create(:repository, from_example: :mojombo_grit)

      ref = grit.heads.find("master")

      assert_equal "1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec", ref.target_oid

      merge_commit, error, error_message = ref.merge(merger, "mojombo")

      assert_nil   merge_commit
      assert_equal :already_merged, error
      assert_equal "Already merged", error_message
    end

    test "merge when there is a merge conflict" do
      base_ref = @refs_test_repo.heads.find("master")
      head_ref = @refs_test_repo.heads.create("topic", base_ref.target_oid, @refs_test_repo.owner)

      metadata = { message: "blah", committer: @refs_test_repo.owner }

      base_ref.append_commit(metadata, @refs_test_repo.owner) do |files|
        files.add("blah.txt", "blahblahblah")
      end

      head_ref.append_commit(metadata, @refs_test_repo.owner) do |files|
        files.add("blah.txt", "other blah blah blah yea")
      end

      merge_commit, error, error_message = base_ref.merge(@refs_test_repo.owner, "topic")

      assert_nil   merge_commit
      assert_equal :merge_conflict, error
      assert_equal "Merge conflict", error_message
    end
  end

  context "#update" do
    test "retrying write_ref until succeeding" do
      ref = @refs_test_repo.heads.find("master")

      lock_path = "#{@refs_test_repo.shard_path}/refs/heads/master.lock"
      error = "fatal: Unable to create '#{lock_path}': File exists.\n\nIf no other git process is currently running, this probably means a\ngit process crashed in this repository earlier. Make sure no other git\nprocess is running and remove the file manually to continue.\n"

      expect_update_ref("refs/heads/master", ref.target.parent_oids.first, ref.target.oid, error, true)

      new_oid = ref.target.parent_oids.first
      ref.update(new_oid, @refs_test_repo.owner)
      assert_equal new_oid, ref.target.oid
    end

    test "retrying write_ref the default number of times until failure" do
      ref = @refs_test_repo.heads.find("master")

      lock_path = "#{@refs_test_repo.shard_path}/refs/heads/master.lock"
      error = "fatal: Unable to create '#{lock_path}': File exists.\n\nIf no other git process is currently running, this probably means a\ngit process crashed in this repository earlier. Make sure no other git\nprocess is running and remove the file manually to continue.\n"

      expect_update_ref("refs/heads/master", ref.target.parent_oids.first, ref.target.oid, error, false)

      assert_raises(Git::Ref::UpdateFailedSensitive) do
        ref.update(ref.target.parent_oids.first, @refs_test_repo.owner)
      end
    end
  end

  def expect_update_ref(expect_name, expect_new, expect_old, error_msg, expect_success)
    times = expect_success ? 2 : 10

    returns = T.let([{ checksum: "ignored", refs_status: { expect_name => "lock exists" }, err: "not nil" }], T::Array[T::Hash[Symbol, T.untyped]])
    if expect_success
      returns << { checksum: "ignored", refs_status: {}, err: nil }  # succeed the second time
    end
    expected_changes = [[expect_name, expect_old, expect_new]]
    GitHub::DGit::ThreePhaseCommitClient.any_instance.expects(:commit).
      times(times).with(expected_changes, is_a(Hash), is_a(String)).returns(*returns)
  end

  context "#fetch_and_merge" do
    test "fetches tip of base branch from parent repo into forked repo" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      forked_repo.owner = @refs_test_repo.owner
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }
      new_commit = @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner)

      assert_raises GitRPC::ObjectMissing do
        forked_repo.rpc.read_commits([new_commit.oid])
      end

      ref = forked_repo.heads.find("master")
      refute_nil ref
      ref.fetch_and_merge(actor: @refs_test_repo.owner)

      assert_nothing_raised do
        forked_repo.rpc.read_commits([new_commit.oid])
      end
    end

    test "if we are ahead, creates a UI-signed commit on the branch that merges the fetched commit and the previous branch tip" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      forked_repo.owner = @refs_test_repo.owner
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }
      new_commit_oid = @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner).oid
      forked_repo.refs
        .create("refs/heads/the-branch", forked_repo.refs["master"].commit.oid, forked_repo.owner)
        .append_commit(commit_meta, forked_repo.owner) do |files|
          files.add("ahead.txt", "stay ahead (so we have a merge commit instead of a fast-forward)")
        end
      previous_branch_oid = forked_repo.refs["the-branch"].commit.oid

      ref = forked_repo.heads.find("the-branch")
      refute_nil ref
      result = ref.fetch_and_merge(actor: @refs_test_repo.owner)

      merge_commit_oid = forked_repo.reload.refs["the-branch"].commit.oid
      merge_commit = forked_repo.commits.find(merge_commit_oid)

      assert_same_elements [new_commit_oid, previous_branch_oid], merge_commit.parent_oids
      assert_equal "Merge branch 'rick:master' into the-branch", merge_commit.message
      assert_predicate merge_commit, :signed_by_github?

      assert_equal "Successfully fetched and merged from upstream rick:master.", result[:message]
      assert_equal "merge", result[:merge_type]
      assert_equal "rick:master", result[:base_branch]
    end

    test "if we are ahead and behind, with discard_changes set to true, it performs a regular fetch and sets the branch to the upstream tip" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      forked_repo.owner = @refs_test_repo.owner
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }

      @refs_test_repo.refs["master"]
        .append_commit(commit_meta, forked_repo.owner) do |files|
          files.add("behind.txt", "behind")
        end

      upstream_commit_oid = @refs_test_repo.reload.refs["master"].commit.oid

      forked_repo.refs["master"]
        .append_commit(commit_meta, forked_repo.owner) do |files|
          files.add("ahead.txt", "ahead but discard later")
        end

      previous_branch_oid = forked_repo.refs["master"].commit.oid

      ref = forked_repo.heads.find("master")
      refute_nil ref
      result = ref.fetch_and_merge(actor: forked_repo.owner, discard_changes: true)

      new_fork_branch_oid = forked_repo.reload.refs["master"].commit.oid

      assert_equal upstream_commit_oid, new_fork_branch_oid
      assert_equal "Successfully discarded changes and synchronized branch to match upstream rick:master.", result[:message]
      assert_equal "fast-forward", result[:merge_type]
      assert_equal "rick:master", result[:base_branch]
    end

    test "if we are not ahead, fast-forwards (= fetches, then sets the branch to the upstream tip)" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      forked_repo.owner = @refs_test_repo.owner
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }
      upstream_commit_oid = @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner).oid
      previous_branch_oid = forked_repo.refs["master"].commit.oid
      forked_repo.refs.create("refs/heads/the-branch", previous_branch_oid, forked_repo.owner)

      ref = forked_repo.heads.find("the-branch")
      refute_nil ref
      result = ref.fetch_and_merge(actor: @refs_test_repo.owner)

      assert_equal upstream_commit_oid, forked_repo.reload.refs["the-branch"].commit.oid

      assert_equal "Successfully fetched and fast-forwarded from upstream rick:master.", result[:message]
      assert_equal "fast-forward", result[:merge_type]
      assert_equal "rick:master", result[:base_branch]
    end

    test "kicks off push processing (so webhooks, pages builds, etc. work) when we do a regular fetch-and-merge" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }
      @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner)
      forked_repo.refs
        .create("refs/heads/the-branch", forked_repo.refs["master"].commit.oid, forked_repo.owner)
        .append_commit(commit_meta, forked_repo.owner) do |files|
          files.add("ahead.txt", "stay ahead (so we have a merge commit instead of a fast-forward)")
        end
      previous_branch_oid = forked_repo.refs["the-branch"].commit.oid

      Timecop.freeze do
        ref = forked_repo.heads.find("the-branch")
        refute_nil ref
        ref.fetch_and_merge(actor: forked_repo.owner)
        merge_commit_oid = forked_repo.reload.refs["the-branch"].commit.oid

        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          assert_hydro_published_partial({
            path: forked_repo.shard_path,
            pusher: forked_repo.owner.login,
            ref_updates: [{ ref: "refs/heads/the-branch", before: previous_branch_oid, after: merge_commit_oid }],
            pushed_at: Time.current
          },
          schema: "github.repositories.v1.Pushed"
        )
        end
      end
    end

    test "kicks off push processing (so webhooks, pages builds, etc. work) when we do a fast-forward" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }
      upstream_commit_oid = @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner).oid
      previous_branch_oid = forked_repo.refs["master"].commit.oid
      forked_repo.refs.create("refs/heads/the-branch", previous_branch_oid, forked_repo.owner)

      Timecop.freeze do
        ref = forked_repo.heads.find("the-branch")
        refute_nil ref
        ref.fetch_and_merge(actor: forked_repo.owner)

        merge_commit_oid = forked_repo.reload.refs["the-branch"].commit.oid
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          assert_hydro_published_partial({
            path: forked_repo.shard_path,
            pusher: forked_repo.owner.login,
            ref_updates: [{ ref: "refs/heads/the-branch", before: previous_branch_oid, after: merge_commit_oid }],
            pushed_at: Time.current
          },
          schema: "github.repositories.v1.Pushed"
        )
        end

      end

      assert_equal upstream_commit_oid, forked_repo.reload.refs["the-branch"].commit.oid
    end

    test "merges even if the branch was force-pushed to a (mergeable) history with no common ancestor" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      orphaned_commit = forked_repo.commits.create({ committer: forked_repo.owner, message: "Orphaned Commit" }) do |files|
        files.add("file-from-fork.txt", "A file from orphaned fork")
      end
      assert_empty orphaned_commit.parent_oids
      forked_repo.refs.create("refs/heads/the-branch", orphaned_commit, forked_repo.owner)
      @refs_test_repo.refs["master"].append_commit({ committer: @refs_test_repo.owner, message: "Upstream Commit" }, @refs_test_repo.owner) do |files|
        files.add("file-from-upstream.txt", "A file from the upstream")
      end

      ref = forked_repo.heads.find("the-branch")
      refute_nil ref
      ref.fetch_and_merge(actor: forked_repo.owner)

      merge_commit_oid = forked_repo.reload.refs["the-branch"].commit.oid
      assert_equal "A file from orphaned fork", forked_repo.rpc.read_tree_entry(merge_commit_oid, "file-from-fork.txt")["content"]
      assert_equal "A file from the upstream", forked_repo.rpc.read_tree_entry(merge_commit_oid, "file-from-upstream.txt")["content"]
    end

    test "merges even if the upstream branch was force-pushed to a (mergeable) history with no common ancestor" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      the_branch = forked_repo.refs.create("refs/heads/the-branch", forked_repo.refs["master"].commit.oid, forked_repo.owner)
      the_branch.append_commit({ committer: @refs_test_repo.owner, message: "Upstream Commit" }, @refs_test_repo.owner) do |files|
        files.add("file-from-fork.txt", "A file from the fork")
      end
      orphaned_commit = @refs_test_repo.commits.create({ committer: @refs_test_repo.owner, message: "Orphaned Commit" }) do |files|
        files.add("file-from-upstream.txt", "A file from orphaned upstream")
      end
      assert_empty orphaned_commit.parent_oids
      GitHub::DGit.update_refs_coordinator(@refs_test_repo).commit([["refs/heads/master", @refs_test_repo.refs["master"].commit.oid, orphaned_commit]])

      ref = forked_repo.reload.heads.find("the-branch")
      refute_nil ref
      ref.fetch_and_merge(actor: forked_repo.owner)

      merge_commit_oid = forked_repo.reload.refs["the-branch"].commit.oid
      assert_equal "A file from the fork", forked_repo.rpc.read_tree_entry(merge_commit_oid, "file-from-fork.txt")["content"]
      assert_equal "A file from orphaned upstream", forked_repo.rpc.read_tree_entry(merge_commit_oid, "file-from-upstream.txt")["content"]
    end

    test "doesn't care if base branch gets renamed" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }
      base_oid = @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner).oid
      branch_oid = forked_repo.refs
        .create("refs/heads/the-branch", forked_repo.refs["master"].commit.oid, forked_repo.owner)
        .append_commit(commit_meta, forked_repo.owner) do |files|
          files.add("ahead.txt", "stay ahead (so we have a merge commit instead of a fast-forward)")
        end.oid

      renamer = RepositoryBranchRenamer.for_starting_rename_process(branch_name: "master", repository: @refs_test_repo)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        assert renamer.start_rename("base-new-name", actor: @refs_test_repo.owner, entry_point: :test_case)
      end
      assert_equal base_oid, @refs_test_repo.reload.refs["base-new-name"].commit.oid

      ref = forked_repo.heads.find("the-branch")
      refute_nil ref
      ref.fetch_and_merge(actor: forked_repo.owner)

      merge_commit_oid = forked_repo.reload.refs["the-branch"].commit.oid
      merge_commit = forked_repo.rpc.read_commits([merge_commit_oid]).first
      assert_same_elements [base_oid, branch_oid], merge_commit["parents"]
    end

    test "doesn't touch the branch and raises an exception if there is a merge conflict" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      commit_meta = { message: "msg", committer: create(:user) }
      @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner) do
        |files| files.add("file001", "foo")
      end
      branch_oid = forked_repo.refs["master"].append_commit(commit_meta, forked_repo.owner) do
        |files| files.add("file001", "bar")
      end.oid

      ref = forked_repo.heads.find("master")
      refute_nil ref
      assert_raises Git::Ref::MergeConflictError do
        ref.fetch_and_merge(actor: forked_repo.owner)
      end

      assert_equal branch_oid, forked_repo.reload.refs["master"].commit.oid
    end

    test "doesn't touch the branch and raises an exception if merge commit can't be created (for non-conflict reasons)" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }
      @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner)
      branch_oid = forked_repo.reload.refs["master"].append_commit(commit_meta, forked_repo.owner) do |files|
        files.add("ahead.txt", "stay ahead so a merge commit is created (instead of a fast-forward)")
      end.oid
      if GitHub.flipper[:tmp_objdir_experiment].enabled?
        GitRPC::Client.any_instance.stubs(:create_merge_commit).returns(
          [nil, "non_conflict_error", nil, nil, [["merge_tree.failure", 1, { tags: ["status:failure"] }]]]
        )
      else
        GitRPC::Client.any_instance.stubs(:create_merge_commit).returns([nil, "non_conflict_error", nil])
      end

      ref = forked_repo.heads.find("master")
      refute_nil ref
      exception = assert_raises Git::Ref::FetchAndMergeFailure do
        ref.fetch_and_merge(actor: forked_repo.owner)
      end

      assert_equal branch_oid, forked_repo.reload.refs["master"].commit.oid
      assert_includes exception.ui_message, "problem creating the merge commit"
    end

    test "doesn't touch the branch and raises an exception if branch could not be updated" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }
      @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner)
      branch_oid = forked_repo.reload.refs["master"].commit.oid
      GitHub::DGit::ThreePhaseCommitClient.any_instance.stubs(:commit).returns({ err: "some error", refs_status: {} })

      ref = forked_repo.heads.find("master")
      refute_nil ref
      exception = assert_raises Git::Ref::FetchAndMergeFailure do
        ref.fetch_and_merge(actor: forked_repo.owner)
      end

      assert_equal branch_oid, forked_repo.reload.refs["master"].commit.oid
      assert_includes exception.ui_message, "problem updating the branch"
    end

    test "doesn't touch the branch and raises an exception if user can't write to target branch" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      forked_repo.protect_branch("master", creator: forked_repo.owner, entry_point: :test_case)
      branch_oid = forked_repo.reload.refs["master"].commit.oid

      ref = forked_repo.heads.find("master")
      refute_nil ref
      exception = assert_raises Git::Ref::FetchAndMergeFailure do
        ref.fetch_and_merge(actor: @rick)
      end

      assert_equal branch_oid, @refs_test_repo.reload.refs["master"].commit.oid
      assert_match /can't write/, exception.ui_message
    end

    test "doesn't touch the branch and raises an exception if repo is locked on migration" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }
      @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner)

      forked_repo.lock!(Repository::LockDependency::MIGRATING)
      branch_oid = forked_repo.reload.refs["master"].commit.oid

      ref = forked_repo.heads.find("master")
      refute_nil ref
      exception = assert_raises Git::Ref::FetchAndMergeFailure do
        ref.fetch_and_merge(actor: forked_repo.owner)
      end

      assert_equal branch_oid, forked_repo.reload.refs["master"].commit.oid
      assert_match /This repository is not writable/, exception.ui_message
    end

    test "doesn't touch the branch and raises an exception if user can't write because the branch is protected" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }
      @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner)

      forked_repo.protect_branch("master", creator: forked_repo.owner,
        required_pull_request_reviews: { required_approving_review_count: 1 },
        enforce_admins: true,
        entry_point: :test_case)
      branch_oid = forked_repo.reload.refs["master"].commit.oid

      ref = forked_repo.heads.find("master")
      refute_nil ref
      exception = assert_raises Git::Ref::FetchAndMergeFailure do
        ref.fetch_and_merge(actor: forked_repo.owner)
      end

      assert_equal branch_oid, forked_repo.reload.refs["master"].commit.oid
      assert_match /Changes must be made through a pull request/, exception.ui_message
    end

    test "doesn't touch the branch and raises an exception if the branch requires signed commits" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }
      @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner)

      forked_repo.protect_branch("master", creator: forked_repo.owner,
        required_signatures: true,
        enforce_admins: true,
        entry_point: :test_case)
      branch_oid = forked_repo.reload.refs["master"].commit.oid

      ref = forked_repo.heads.find("master")
      refute_nil ref
      exception = assert_raises Git::Ref::FetchAndMergeFailure do
        ref.fetch_and_merge(actor: forked_repo.owner)
      end

      assert_equal branch_oid, forked_repo.reload.refs["master"].commit.oid
      assert_equal branch_oid, forked_repo.reload.refs["master"].commit.oid
      assert_match /Commits must have verified signatures/, exception.ui_message
    end

    test "doesn't touch the branch and raises an exception if the branch fails deployment rule" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }
      @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner)

      create(:environment, repository: forked_repo, name: "test")
      ruleset = create(:repository_ruleset, :targets_default_branch, source: forked_repo)
      create(:repository_rule_configuration, rule_type: "required_deployments", parameters: {
        required_deployment_environments: ["test"]
      }, repository_ruleset: ruleset)

      branch_oid = forked_repo.reload.refs["master"].commit.oid

      ref = forked_repo.heads.find("master")
      refute_nil ref
      exception = assert_raises Git::Ref::FetchAndMergeFailure do
        ref.fetch_and_merge(actor: forked_repo.owner)
      end

      assert_equal branch_oid, forked_repo.reload.refs["master"].commit.oid
      assert_match /Repository rule violations found/, exception.ui_message
    end

    test "doesn't touch the branch and raises an exception if user can't read contents of parent repository (e.g., it became private)" do
      rando = create(:user)
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      forked_repo.add_member(rando)
      branch_oid = forked_repo.refs["master"].commit.oid

      @refs_test_repo.update!(public: false)
      ref = forked_repo.heads.find("master")
      refute_nil ref
      exception = assert_raises Git::Ref::FetchAndMergeFailure do
        ref.fetch_and_merge(actor: rando)
      end

      assert_equal branch_oid, @refs_test_repo.reload.refs["master"].commit.oid
      assert_includes exception.ui_message, "can't read"
    end

    test "rejects repo that is not a fork" do
      ref = @refs_test_repo.heads.find("master")
      refute_nil ref
      assert_raises Git::Ref::RejectedError do
        ref.fetch_and_merge(actor: @refs_test_repo.owner)
      end
    end

    test "rejects repo whose parent was deleted" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      @refs_test_repo.remove(@refs_test_repo.owner)

      ref = @refs_test_repo.heads.find("master")
      refute_nil ref
      assert_raises Git::Ref::RejectedError do
        ref.fetch_and_merge(actor: forked_repo.owner)
      end
    end

    test "differentiates between fast-forward and 'nothing to do'" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      forked_repo.owner = @refs_test_repo.owner

      ref = forked_repo.heads.find("master")
      refute_nil ref
      result = ref.fetch_and_merge(actor: @refs_test_repo.owner)

      assert_equal "This branch is not behind the upstream rick:master.", result[:message]
      assert_equal "none", result[:merge_type]
      assert_equal "rick:master", result[:base_branch]
    end

    test "differentiates between merge and 'nothing to do'" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      forked_repo.owner = @refs_test_repo.owner

      commit_meta = { message: "msg", committer: forked_repo.owner }
      forked_repo.refs
        .create("refs/heads/the-branch", forked_repo.refs["master"].commit.oid, forked_repo.owner)
        .append_commit(commit_meta, forked_repo.owner) do |files|
          files.add("ahead.txt", "stay ahead (so we have a merge commit instead of a fast-forward)")
        end

      ref = forked_repo.heads.find("the-branch")
      refute_nil ref
      commit_oid = ref.commit.oid
      result = ref.fetch_and_merge(actor: @refs_test_repo.owner)

      # Should be no change in the latest commit
      assert_equal commit_oid, forked_repo.reload.refs["the-branch"].commit.oid

      assert_equal "This branch is not behind the upstream rick:master.", result[:message]
      assert_equal "none", result[:merge_type]
      assert_equal "rick:master", result[:base_branch]
    end

    test "kicks off push processing once" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      forked_repo.owner = @refs_test_repo.owner
      @refs_test_repo.refs["master"].append_commit({ message: "msg", committer: @refs_test_repo.owner }, @refs_test_repo.owner)
      ref = forked_repo.heads.find("master")

      with_hydro_publisher(GitHub.sync_hydro_publisher) { assert_hydro_messages(count: 1, schema: "github.repositories.v1.Pushed") }
    end

    test "doesn't touch the branch when the branch is locked" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }
      @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner)

      forked_repo.protect_branch("master", creator: forked_repo.owner, lock_branch: true, enforce_admins: true)
      branch_oid = forked_repo.reload.refs["master"].commit.oid

      ref = forked_repo.heads.find("master")
      refute_nil ref

      exception = assert_raises Git::Ref::FetchAndMergeFailure do
        ref.fetch_and_merge(actor: forked_repo.owner)
      end

      assert_match /Cannot change this locked branch/, exception.ui_message
    end

    test "merges when the branch is locked and fetching and merging is allowed" do
      forked_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @refs_test_repo.fork(forker: create(:user)) }.first
      commit_meta = { message: "msg", committer: @refs_test_repo.owner }
      new_commit = @refs_test_repo.refs["master"].append_commit(commit_meta, @refs_test_repo.owner)

      forked_repo.protect_branch("master", creator: forked_repo.owner, lock_branch: true, enforce_admins: true, lock_allows_fetch_and_merge: true)
      branch_oid = forked_repo.reload.refs["master"].commit.oid

      ref = forked_repo.heads.find("master")
      refute_nil ref

      assert_nothing_raised do
        ref.fetch_and_merge(actor: forked_repo.owner)
        forked_repo.rpc.read_commits([new_commit.oid])
      end
    end
  end

  context "#notify_socket_subscribers" do
    test "accepts a ref with an emoji" do
      GitHub.stubs(:live_updates_enabled?).returns(true)

      ref = Git::Ref.new(@refs_test_repo, "refs/heads/💔", @expected_refs["refs/heads/💔"])
      data = { action: :push }

      ref.notify_socket_subscribers(data)

      assert_hydro_messages(count: 1, schema: "live_updates.v0.Message")
    end
  end
end

class RefNormalizingTest < GitHub::TestCase
  test "does nothing to an acceptable name" do
    name = "name_with_dashes-and-underscores"
    assert_equal name, Git::Ref.normalize(name)
  end

  test "replaces space with dash" do
    name = "name with spaces"
    normalized = "name-with-spaces"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "replaces extra spaces with a single dash (and no dash at beginning or end)" do
    name = " name with  spaces "
    normalized = "name-with-spaces"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "replace multiple embedded periods" do
    name = "name...with...embedded...periods"
    normalized = "name.with.embedded.periods"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "replace leading and trailing periods" do
    name = "...periods.with.embedded.name..."
    normalized = "periods.with.embedded.name"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "strips extra characters (like tilde, caret, colon, question mark, &c)" do
    name = ":name? with ~a\\ll so^rts of [ cra*zy \030 char\0act\177ers"
    normalized = "name-with-all-sorts-of-crazy-characters"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "strips Unicode non-breaking spaces" do
    name = "my-\u00A0branch"
    normalized = "my-branch"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "strips Unicode C1 control characters" do
    name = "my-\u0080branch"
    normalized = "my-branch"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "strips slash at beginning or end, and reduces multiple slashes to one" do
    name = "/name//with/many/////slashes/"
    normalized = "name/with/many/slashes"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "strips ending dot" do
    name = "name_ending_with_dot."
    normalized = "name_ending_with_dot"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "strips @{ sequence" do
    name = "name_with_at@{bracket_sequence"
    normalized = "name_with_atbracket_sequence"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "strips dot at start of any slash-separated part" do
    name = ".name/.with/some/./././.dotted/stuff"
    normalized = "name/with/some/dotted/stuff"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "strips .lock at end of any slash-separated part" do
    name = "name/with.lock/some/.lock//locked/stuff.lock"
    normalized = "name/with/some/locked/stuff"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "handles repleated .lock" do
    name = "name/with.lock.lock.lock/locks"
    normalized = "name/with/locks"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "doesn’t leave left-over stuff at the end" do
    name = "leftovers .lock"
    normalized = "leftovers"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "doesn’t output something that still needs normalized" do
    name = "some//@{//thing"
    normalized = "some/thing"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "handles tricky stuff that requires repeated normalization" do
    name = "some/foolish.lock@{/thing"
    normalized = "some/foolish/thing"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "stays calm and collected even if thrown a bit of everything" do
    name = ". n\o~^*?:p[e///.no@{pe .lock"
    normalized = "nope/nope"

    assert_equal normalized, Git::Ref.normalize(name)
  end

  test "returns nil when a name is normalized away to nothing" do
    name = "../.lock/@{*[~?-.."

    assert_nil Git::Ref.normalize(name)
  end


  test "does not change the encoding of the input string" do
    name = "old-school".encode("ASCII-8BIT")
    result = Git::Ref.normalize(name)

    assert_equal name.encoding, result.encoding
  end

  # See https://github.com/github/github/issues/154877
  context "#paste_safe_normalize" do
    test "does nothing to an acceptable name" do
      name = "acceptable-name-without-backticks-or-dollar-signs"
      assert_equal name, Git::Ref.paste_safe_normalize(name)
    end

    test "strips malicious command injection characters" do
      name = "`touch${IFS}hacked`"
      normalized = "touch{IFS}hacked"
      assert_equal normalized, Git::Ref.paste_safe_normalize(name)
    end
  end
end
