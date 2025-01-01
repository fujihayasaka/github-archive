# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class RepositoryRefsDependencyMethodsTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include DogstatsTestHelpers
  include PushTestHelper

  fixtures do
    Spokesd.enable_spokesd

    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :encodings)

    @repo.update_default_branch("unicode-文字化け".b)

    @repo2 = create(:repository, owner: @user, from_example: :simple)
    @fork = create(:repository, parent: @repo2)

    @bigrepo = create(:repository, owner: @user, from_example: :hella_behind_yet_still_ahead)

    @org = create(:business_plus_organization, admin: @user)
    @org_writer = create(:user)
    @org.add_member(@org_writer, action: :write)

    @org_repo = create(:repository, owner: @org, from_example: :simple)
    @org_repo.add_member(@org_writer, action: :admin)


    @ref_name = "test-branch"
    @commit_oid = "b44d25df1414b9b6383f5dd27880a6931c3f2485"

    @tag_name = "v1.0"
    @repo.tags.create(@tag_name, @commit_oid, @user)

    @actions_app = create(:launch_integration)

    example_repo_snapshot
  end

  setup do
    Spokesd.enable_spokesd
    example_repo_restore
  end

  context "#update_default_branch" do
    test "returns false when new branch is one that is being renamed" do
      previous_value = @repo.default_branch
      rename = create(:repository_branch_rename, repository: @repo,
        old_name: "badencs-path")
      refute @repo.update_default_branch(rename.old_name)
      assert_equal previous_value, @repo.reload.default_branch
    end

    test "resets workflows correctly when default branch changes" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner
      make_integration_installation(integration: @actions_app, repository: @repo)

      default_branch = @repo.default_branch
      sha = @repo.refs[default_branch].commit.oid
      branch = "branch"
      @repo.heads.create(branch, sha, @repo.owner)

      # Default branch contains files to create workflows A and B
      # Other branch contains files to create workflows B and C
      prev_oid = T.let(nil, T.nilable(String))
      [
        ["A", default_branch],
        ["B", default_branch],
        ["B", branch],
        ["C", branch]
      ].each do |name, branch_name|
        path = ".github/workflows/#{name}.yaml"
        commit = @repo.refs.find(branch_name).append_commit({ message: "Add workflow", author: @repo.owner }, @repo.owner) do |changes|
          changes.add(path, "name: #{name}")
        end
        @repo.update_repository_workflows("refs/heads/#{branch_name}", prev_oid, commit.oid)
        prev_oid = commit.oid
      end

      workflows = Hash.new
      %w[A B C].each do |name|
        path = ".github/workflows/#{name}.yaml"
        workflow = Actions::Workflow.find_by(repository: @repo, path: path)
        workflows[name] = workflow
      end

      # Before updating the default branch:
      #   Workflows for A and B should be created and present in the default branch
      #   No workflow should be created for C
      refute_nil workflows["A"]
      assert workflows["A"].present_in_default_branch
      refute_nil workflows["B"]
      assert workflows["B"].present_in_default_branch
      assert_nil workflows["C"]

      @repo.update_default_branch(branch)

      %w[A B C].each do |name|
        path = ".github/workflows/#{name}.yaml"
        workflow = Actions::Workflow.find_by(repository: @repo, path: path)
        workflows[name] = workflow
      end

      # After updating the default branch:
      #   Workflow A should be deleted
      #   Workflow B should be updated and present in the default branch
      #   Workflow C should be created and present in the default branch
      refute workflows["A"].present_in_default_branch
      assert_equal "deleted", workflows["A"].state
      refute_nil workflows["B"]
      assert workflows["B"].present_in_default_branch
      refute_nil workflows["C"]
      assert workflows["C"].present_in_default_branch
    end
  end

  context "#can_switch_default_branch?" do
    test "returns true if default branch targeted by org ruleset (org admin)" do
      create(:repository_ruleset, :example_ruleset, :targets_all_repos, source: @org)

      assert @org_repo.can_switch_default_branch?(@user)
    end

    test "returns false if default branch targeted by org ruleset (non org-admin)" do
      create(:repository_ruleset, :example_ruleset, :targets_all_repos, source: @org)

      refute @org_repo.can_switch_default_branch?(@org_writer)
    end
  end

  context "#switch_default_branch" do
    test "returns true if default branch is updated" do
      @repo.heads.create("topic", @repo.heads[@repo.default_branch].target.first_parent_oid, @user)
      assert @repo.switch_default_branch(@user, "topic")
      assert_equal "topic", @repo.reload.default_branch
    end

    test "returns true if org ruleset targeted default branch is updated" do
      create(:repository_ruleset, :example_ruleset, :targets_all_repos, source: @org)

      @org_repo.heads.create("topic", @org_repo.heads[@org_repo.default_branch].target.first_parent_oid, @user)
      assert @org_repo.switch_default_branch(@user, "topic")
      assert_equal "topic", @org_repo.reload.default_branch
    end

    test "returns false if org ruleset targeted default branch is not updated" do
      create(:repository_ruleset, :example_ruleset, :targets_all_repos, source: @org)

      default_branch = @org_repo.default_branch

      @org_repo.heads.create("topic", @org_repo.heads[@org_repo.default_branch].target.first_parent_oid, @org_writer)
      refute @org_repo.switch_default_branch(@org_writer, "topic")
      assert_equal default_branch, @org_repo.reload.default_branch
    end
  end

  context "#branch_refs_for_compare" do
    test "includes default branch" do
      result = @repo.branch_refs_for_compare.map(&:name)
      assert_includes result, @repo.default_branch.b
    end

    test "includes other branches than the default branch" do
      result = @repo.branch_refs_for_compare.map(&:name)
      assert_includes result, "badencs-path" # exists in `encodings` sample repo
    end

    test "does not include a branch that is being renamed" do
      rename = create(:repository_branch_rename, repository: @repo,
        old_name: "badencs-path")
      result = @repo.branch_refs_for_compare.map(&:name)
      refute_includes result, rename.old_name
    end
  end

  context "#default_branch" do
    test "returns owner's preferred default branch when an error occurs" do
      @user.set_default_new_repo_branch("sample-sample", actor: @user)
      GitRPC::Client.any_instance.stubs(:read_symbolic_ref).raises(GitRPC::InvalidRepository)
      SpokesAPI::Client.any_instance.stubs(:get_default_branch).raises(SpokesAPI::NotFound)
      assert_equal "sample-sample", @repo.default_branch
    end

    test "does not return preferred default when ResourceExhausted raised" do
      @user.set_default_new_repo_branch("sample-sample", actor: @user)
      SpokesAPI::Client.any_instance.stubs(:get_default_branch).raises(SpokesAPI::ResourceExhausted)
      assert_raises(SpokesAPI::ResourceExhausted) { @repo.default_branch }
    end if TestEnv.test_all_features?
  end

  test "ref_to_sha" do
    assert_equal @commit_oid, @repo.ref_to_sha(@ref_name)
  end

  test "ambiguous short sha" do
    # Enable spokesd so that we use Spokes Access API.
    Spokesd.enable_spokesd

    # This short sha is unambiguous.
    assert_equal "ffeeef2a7a825d1e85c0933c8811a3f2a85dcfc0",
      @bigrepo.ref_to_sha("ffeeef2a")

    # This one is ambiguous.
    assert_nil \
      @bigrepo.ref_to_sha("ffeeef2")
  end

  test "ref_to_sha with .. in name" do
    assert_nil @repo.ref_to_sha("foo..bar")
  end

  test "ref_to_sha with oid" do
    assert_equal @commit_oid, @repo.ref_to_sha(@commit_oid)
  end

  test "batched single update" do
    assert_different_shas "master", "test-branch"
    oid = @repo.refs.read("test-branch").sha
    @repo.batch_write_refs(@user, [["refs/heads/master", nil, oid]])
    assert_same_sha "master", "test-branch"
  end

  test "batched single delete" do
    assert_same_sha "test-branch"
    @repo.batch_write_refs(@user, [["refs/heads/test-branch", nil, GitHub::NULL_OID]])
    assert_nil_sha "test-branch"
  end

  test "batched multiple update" do
    assert_different_shas "master", "test-branch", "empty-branch"
    oid = @repo.refs.read("test-branch").sha
    @repo.batch_write_refs(@user, [
      ["refs/heads/master", nil, oid],
      ["refs/heads/empty-branch", nil, oid],
      ])
    assert_same_sha "master", "test-branch", "empty-branch"
  end

  test "batched multiple delete" do
    assert_different_shas "test-branch", "empty-branch"
    @repo.batch_write_refs(@user, [
      ["refs/heads/test-branch", nil, GitHub::NULL_OID],
      ["refs/heads/empty-branch", nil, GitHub::NULL_OID],
      ])
    assert_nil_sha "test-branch", "empty-branch"
  end

  test "update and delete" do
    assert_different_shas "master", "test-branch", "empty-branch"
    oid = @repo.refs.read("test-branch").sha
    @repo.batch_write_refs(@user, [
      ["refs/heads/master", nil, oid],
      ["refs/heads/empty-branch", nil, GitHub::NULL_OID],
      ])
    assert_same_sha "master", "test-branch"
    assert_nil_sha "empty-branch"
  end

  test "verifying a ref tip while modifying other refs" do
    assert_different_shas "master", "test-branch", "empty-branch"
    oid = @repo.refs.read("test-branch").sha

    @repo.batch_write_refs(@user, [
      ["refs/heads/test-branch", oid, nil],
      ["refs/heads/master", nil, oid],
      ["refs/heads/empty-branch", nil, GitHub::NULL_OID],
    ])

    assert_same_sha "master", "test-branch"
    assert_nil_sha "empty-branch"
  end

  test "fails if ref does not exist when updating" do
    assert_different_shas "master", "test-branch", "empty-branch"

    oid = @repo.refs.read("test-branch").sha
    empty_branch_oid = @repo.refs.read("empty-branch").sha

    error = assert_raises Git::Ref::ComparisonMismatch do
      @repo.batch_write_refs(@user, [
        ["refs/heads/test-branch", oid, nil],
        ["refs/heads/does-not-exist", empty_branch_oid, oid],
      ])
    end

    assert_equal "refs/heads/does-not-exist expected to be at #{empty_branch_oid}", error.message
  end

  test "verify a ref does not exist when updating" do
    assert_different_shas "master", "test-branch", "empty-branch"

    oid = @repo.refs.read("test-branch").sha
    empty_branch_oid = @repo.refs.read("empty-branch").sha

    @repo.batch_write_refs(@user, [
      ["refs/heads/test-branch", oid, nil],
      ["refs/heads/does-not-exist", GitHub::NULL_OID, oid],
    ])

    assert_equal oid, @repo.refs.read("does-not-exist").sha
  end

  test "fails if ref points to an unexpected commit while modifying other refs" do
    assert_different_shas "master", "test-branch", "empty-branch"

    oid = @repo.refs.read("test-branch").sha
    master_oid = @repo.refs.read("master").sha
    empty_branch_oid = @repo.refs.read("empty-branch").sha

    error = assert_raises Git::Ref::ComparisonMismatch do
      @repo.batch_write_refs(@user, [
        ["refs/heads/test-branch", oid, nil],
        ["refs/heads/master", empty_branch_oid, oid],
        ["refs/heads/empty-branch", nil, GitHub::NULL_OID],
      ])
    end

    assert_match %r{(refs/heads/master )?is at #{master_oid} but expected #{empty_branch_oid}}, error.message

    assert_equal oid, @repo.refs.read("test-branch").sha
    assert_equal master_oid, @repo.refs.read("master").sha
    assert_equal empty_branch_oid, @repo.refs.read("empty-branch").sha
  end

  test "verifying a ref does not exist while modifying other refs" do
    assert_different_shas "master", "test-branch", "empty-branch"
    oid = @repo.refs.read("test-branch").sha

    @repo.batch_write_refs(@user, [
      ["refs/heads/does-not-exist", GitHub::NULL_OID, nil],
      ["refs/heads/master", nil, oid],
      ["refs/heads/empty-branch", nil, GitHub::NULL_OID],
    ])

    assert_same_sha "master", "test-branch"
    assert_nil_sha "empty-branch"
  end

  test "fails if ref does exist unexpectedly while modifying other refs" do
    assert_different_shas "master", "test-branch", "empty-branch"

    oid = @repo.refs.read("test-branch").sha
    master_oid = @repo.refs.read("master").sha
    empty_branch_oid = @repo.refs.read("empty-branch").sha

    error = assert_raises Git::Ref::ReferenceExistsError do
      @repo.batch_write_refs(@user, [
        ["refs/heads/test-branch", GitHub::NULL_OID, nil],
        ["refs/heads/master", nil, oid],
        ["refs/heads/empty-branch", nil, GitHub::NULL_OID],
      ])
    end

    assert_match %r{(reference already exists|refs/heads/test-branch is at #{oid} but expected #{GitHub::NULL_OID})}, error.message

    assert_equal master_oid, @repo.refs.read("master").sha
    assert_equal empty_branch_oid, @repo.refs.read("empty-branch").sha
  end

  test "verifying a ref does not exist on creation" do
    assert_different_shas "master", "test-branch", "empty-branch"
    oid = @repo.refs.read("test-branch").sha

    @repo.batch_write_refs(@user, [
      ["refs/heads/did-not-exist-before", GitHub::NULL_OID, oid],
    ])

    assert_same_sha "did-not-exist-before", "test-branch"
  end

  test "fails if ref exists unexpectedly on creation" do
    assert_different_shas "master", "test-branch", "empty-branch"

    oid = @repo.refs.read("test-branch").sha
    master_oid = @repo.refs.read("master").sha

    error = assert_raises Git::Ref::ReferenceExistsError do
      @repo.batch_write_refs(@user, [
        ["refs/heads/master", GitHub::NULL_OID, oid],
        ["refs/heads/empty-branch", nil, GitHub::NULL_OID],
      ])
    end

    assert_match %r{(reference already exists|refs/heads/master is at #{master_oid} but expected #{GitHub::NULL_OID})}, error.message

    assert_equal master_oid, @repo.refs.read("master").sha
    assert_predicate @repo.refs.read("refs/heads/empty-branch"), :exists?
  end

  test "retries with the full list of updates if a lock is encountered" do
    assert_different_shas "master", "test-branch", "empty-branch"
    oid = @repo.refs.read("test-branch").sha

    updates = [
      ["refs/heads/master", nil, oid],
      ["refs/heads/empty-branch", nil, oid],
      ["refs/heads/test-branch", nil, GitHub::NULL_OID],
    ]

    error_result = {
      checksum: "5:3fbb317e16a0a278a64c9cca289039867661963c",
      refs_status: {
        "refs/heads/empty-branch" => "lock exists",
      },
      err: "reference update failure",
    }

    success_result = {
      checksum: "5:06f079ae24394c99a0a00899ad62e3b6821bef4f",
      refs_status: {},
      err: nil,
    }

    GitHub::DGit::SpokesdThreePhaseCommitClient.any_instance.expects(:commit).with(updates, any_parameters).twice.returns(error_result, success_result)

    @repo.batch_write_refs(@user, updates)
  end

  test "fails after exhausting all retry attempts" do
    assert_different_shas "master", "test-branch", "empty-branch"
    oid = @repo.refs.read("test-branch").sha

    updates = [
      ["refs/heads/master", nil, oid],
      ["refs/heads/empty-branch", nil, oid],
      ["refs/heads/test-branch", nil, GitHub::NULL_OID],
    ]

    error_result = {
      checksum: "5:3fbb317e16a0a278a64c9cca289039867661963c",
      refs_status: {
        "refs/heads/empty-branch" => "lock exists",
      },
      err: "reference update failure",
    }

    GitHub::DGit::SpokesdThreePhaseCommitClient.any_instance.expects(:commit).with(updates, any_parameters).times(5).returns(error_result)

    assert_raises Git::Ref::UpdateFailedSensitive do
      @repo.batch_write_refs(@user, updates, attempts_remaining: 5)
    end
  end

  test "batched update with post_receive:true creates Push records" do
    assert_different_shas "master", "test-branch", "empty-branch"
    assert_equal 0, push_accessor.by_repository_id_and_refs(repository_id: @repo.id, refs: ["refs/heads/master", "refs/heads/test-branch", "refs/heads/empty-branch"]).count
    oid = @repo.refs.read("test-branch").sha
    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      @repo.batch_write_refs(@user, [
        ["refs/heads/master", nil, oid],
        ["refs/heads/empty-branch", nil, oid],
        ], post_receive: true)
      assert_same_sha "master", "test-branch", "empty-branch"
    end

    assert_equal 1, push_accessor.by_repository_id_and_refs(repository_id: @repo.id, refs: ["refs/heads/master"]).count
    assert_equal 1, push_accessor.by_repository_id_and_refs(repository_id: @repo.id, refs: ["refs/heads/empty-branch"]).count
  end

  test "batched update with post_receive:false does not create Push records" do
    assert_different_shas "master", "test-branch", "empty-branch"
    assert_equal 0, push_accessor.by_repository_id_and_refs(repository_id: @repo.id, refs: ["refs/heads/master", "refs/heads/test-branch", "refs/heads/empty-branch"]).count
    oid = @repo.refs.read("test-branch").sha

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      @repo.batch_write_refs(@user, [
        ["refs/heads/master", nil, oid],
        ["refs/heads/empty-branch", nil, oid],
        ], post_receive: false)
      assert_same_sha "master", "test-branch", "empty-branch"
    end

    assert_equal 0, push_accessor.by_repository_id_and_refs(repository_id: @repo.id, refs: ["refs/heads/master"]).count
    assert_equal 0, push_accessor.by_repository_id_and_refs(repository_id: @repo.id, refs: ["refs/heads/empty-branch"]).count
  end

  context "#fetch_commits_from" do
    test "fetches commits and new ref name defaults to source ref name" do
      ref = @repo.heads.create("new_branch", @repo.default_oid, @user)
      ref.append_commit({ message: "testing", committer: @user }, @user) do |files|
        files.add("somefile", "somecontents")
      end

      assert_raises GitRPC::ObjectMissing do
        @repo2.commits.find(ref.target_oid)
      end

      @repo2.fetch_commits_from(ref, user: @user)

      assert_equal ref.sha, @repo2.heads["new_branch"].sha
    end

    test "creates branch with a different name if new_ref_name is provided" do
      master_oid = @repo.heads.read("master").target_oid
      ref = @repo.heads.create("new_branch", @repo.default_oid, @user)
      ref.append_commit({ message: "testing", committer: @user }, @user) do |files|
        files.add("somefile", "somecontents")
      end

      assert_raises GitRPC::ObjectMissing do
        @repo2.commits.find(ref.target_oid)
      end

      @repo2.fetch_commits_from(ref, user: @user, new_ref_name: "AH_BEES")

      assert_equal ref.sha, @repo2.heads["AH_BEES"].sha
      refute @repo2.heads["new_branch"]
    end

    test "fetches multiple commits if necessary" do
      ref = @repo.heads.create("new_branch", @repo.default_oid, @user)
      ref.append_commit({ message: "testing", committer: @user }, @user) do |files|
        files.add("somefile", "somecontents")
      end

      commit1_sha = ref.sha

      ref.append_commit({ message: "testing", committer: @user }, @user) do |files|
        files.add("somefile", "somecontents")
      end

      commit2_sha = ref.sha

      assert_raises GitRPC::ObjectMissing do
        @repo2.commits.find(ref.target_oid)
      end

      @repo2.fetch_commits_from(ref, user: @user)

      assert_equal ref.sha, @repo2.heads["new_branch"].sha

      assert @repo2.objects.exist?(commit1_sha)
      assert @repo2.objects.exist?(commit2_sha)
    end

    test "does not fetch refs" do
      ref = @repo.heads.create("new_branch", @repo.default_oid, @user)
      ref.append_commit({ message: "testing", committer: @user }, @user) do |files|
        files.add("somefile", "somecontents")
      end

      # Put a ref on this first commit
      @repo.heads.create("dont-fetch-me-pls", ref.sha, @user)

      ref.append_commit({ message: "testing", committer: @user }, @user) do |files|
        files.add("somefile", "somecontents")
      end

      assert_raises GitRPC::ObjectMissing do
        @repo2.commits.find(ref.target_oid)
      end

      @repo2.fetch_commits_from(ref, user: @user)

      assert_equal ref.sha, @repo2.heads["new_branch"].sha

      assert @repo.heads["dont-fetch-me-pls"]
      refute @repo2.heads["dont-fetch-me-pls"]
    end
  end
  context "#limited_heads" do
    test "returns lazily loaded limited head records" do
      10.times do |branch_id|
        @repo.heads.create("branch_#{branch_id}", @repo.default_oid, @user)
      end
      assert_equal @repo.limited_heads(5).count, 5
    end

    test "does not cache the list of repos" do
      10.times do |branch_id|
        @repo.heads.create("branch_#{branch_id}", @repo.default_oid, @user)
      end
      @repo.limited_heads(5)
      assert_equal @repo.limited_heads(6).count, 6
    end
  end

  test "#protect_branch cannot loop infinitely" do
    @repo.protected_branches.stubs(:create!).raises(ActiveRecord::RecordNotUnique.new)
    assert_raises(ActiveRecord::RecordNotUnique) do
      Timeout.timeout(2) do
        @repo.protect_branch("master", creator: @user, required_status_checks: { include_admins: true }, entry_point: :test_case)
      end
    end
  end

  test "#protect branch sets non-admin enforced branch lock" do
    protected_branch = @repo.protect_branch(
      @repo.default_branch,
      creator: @user,
      lock_branch: true,
      entry_point: :test_case,
    )

    assert_equal protected_branch.lock_branch_enforcement_level, "non_admins"
  end

  test "#protect branch sets admin enforced branch lock" do
    protected_branch = @repo.protect_branch(
      @repo.default_branch,
      creator: @user,
      lock_branch: true,
      enforce_admins: true,
      entry_point: :test_case,
    )

    assert_equal protected_branch.lock_branch_enforcement_level, "everyone"
  end

  if GitHub.merge_queues_enabled?
    test "#protect_branch enables the merge queue" do
      GitHub.flipper[:merge_queue].enable(@repo)

      protected_branch = assert_difference -> { MergeQueue.count }, 1 do
        @repo.protect_branch(
          @repo.default_branch,
          creator: @user,
          enforce_merge_queue: true,
          entry_point: :test_case,
        )
      end

      assert_predicate protected_branch, :merge_queue_enabled?
      assert protected_branch&.merge_queue
    end

    test "#protect_branch disables the merge queue" do
      GitHub.flipper[:merge_queue].enable(@repo)

      protected_branch = assert_no_difference -> { MergeQueue.count } do
        @repo.protect_branch(
          @repo.default_branch,
          creator: @user,
          enforce_merge_queue: false,
          entry_point: :test_case,
        )
      end

      refute_predicate protected_branch, :merge_queue_enabled?
      refute protected_branch.merge_queue
    end
  else
    test "#protect_branch ignores merge queue for enterprise" do
      GitHub.flipper[:merge_queue].enable(@repo)

      protected_branch = assert_no_difference -> { MergeQueue.count } do
        @repo.protect_branch(
          @repo.default_branch,
          creator: @user,
          enforce_merge_queue: true,
          entry_point: :test_case,
        )
      end

      refute_predicate protected_branch, :merge_queue_enabled?
      refute protected_branch.merge_queue
    end
  end

  context "#base_branch" do
    test "returns the default branch by default" do
      refute @repo.can_compare_against_parent?(@user)
      assert_equal @repo.default_branch, @repo.base_branch("my-feature", @user)
    end

    test "returns gh-pages as the base for gh-pages" do
      refute @repo.can_compare_against_parent?(@user)
      assert_equal "gh-pages", @repo.base_branch("gh-pages", @user)
    end

    context "on a forked repository" do
      test "returns the parent's default branch by default" do
        assert @fork.can_compare_against_parent?(@user)
        assert_equal "#{@user.login}:master", @fork.base_branch("my-feature", @user)
      end

      test "returns the parent's org, name, and default branch when include_remote_repo is true" do
        assert @fork.can_compare_against_parent?(@user)
        assert_equal "#{@user.login}/#{@fork.parent.name}:master", @fork.base_branch("my-feature", @user, include_remote_repo: true)
      end

      test "returns the parent's org, name, and default branch when include_remote_repo is true with seperator" do
        assert @fork.can_compare_against_parent?(@user)
        assert_equal "#{@user.login}:#{@fork.parent.name}:master", @fork.base_branch("my-feature", @user, include_remote_repo: true, repo_seperator: ":")
      end

      test "returns the parent's equivalent branch when it exists" do
        assert @fork.can_compare_against_parent?(@user)
        assert_equal "#{@user.login}:cr-line-endings",
          @fork.base_branch("cr-line-endings", @user)
      end

      test "returns the parent's org, name, and equivalent branch when include_remote_repo is true" do
        assert @fork.can_compare_against_parent?(@user)
        assert_equal "#{@user.login}/#{@fork.parent.name}:cr-line-endings",
          @fork.base_branch("cr-line-endings", @user, include_remote_repo: true)
      end

      test "returns the child's default branch when the parent and child repos have different visibility" do
        @fork.parent.update! public: false

        refute @fork.can_compare_against_parent?(@user)
        assert_equal "main", @fork.base_branch("my-feature", @user)
      end

      test "returns the parent's default branch when the child is an internal fork" do
        internal_repo = create(:internal_repository)
        fork = create(:private_repository, parent: internal_repo)
        org = internal_repo.owner
        user = org.admin

        assert fork.can_compare_against_parent?(user)
        assert_equal "#{org.login}:#{internal_repo.default_branch}", fork.base_branch("my-feature", user)
      end

      test "returns the child's default branch when the user doesn't have pull access to the parent" do
        @fork.update! public: false
        @fork.parent.update! public: false
        child_collaborator = create(:user)
        @fork.add_member(child_collaborator, action: :read)

        refute @fork.can_compare_against_parent?(child_collaborator)
        assert_equal "main", @fork.base_branch("my-feature", child_collaborator)
      end
    end
  end

  def assert_different_shas(*args)
    shas = args.map { |name| @repo.refs.read(name).sha }
    shas.each do |sha|
      assert_match /\A[0-9a-f]{40}\z/, sha
    end
    assert_equal shas.size, shas.uniq.size
  end

  def assert_same_sha(*args)
    shas = args.map { |name| @repo.refs.read(name).sha }
    shas.each do |sha|
      assert_match /\A[0-9a-f]{40}\z/, sha
    end
    assert_equal 1, shas.uniq.size
  end

  def assert_nil_sha(*args)
    args.each do |name|
      assert_nil @repo.refs.read(name).sha, "branch #{name} should be NULL"
    end
  end
end
