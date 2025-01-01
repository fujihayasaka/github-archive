# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RenameRepositoryOrchestrationTest < GitHub::TestCase
  include JobTestHelper
  include HydroTestHelpers

  fixtures do
    @jon   = create(:user, login: "jonsnow")
    @rob   = create(:user, login: "robstark")
    @repo  = create(:repository, name: "somesword", owner: @jon)
    @repo_new_owner = create(:repository, owner: @rob)
    @other = create(:repository, name: "someothersword", owner: @jon)
    @key   = create(:public_key,
                    key: Sham.ssh_public_key,
                    repository: @repo)
    @org = create(:business_plus_organization, admin: @jon)
    @org_repo = create(:repository, owner: @org, name: "org-repo")
  end

  setup do
    reset_repo_root
    example_repo :simple, @repo
    @wiki  = @repo.unsullied_wiki
    example_repo :simple, @wiki
    GitHub.flipper[:repo_transfer_owner_lock].disable
  end

  teardown do
    # This is necessary because if a test doesn't complete the rename orchestration, for instance
    # "Repository#update fails due to validation error" then the Mutex lock will not be released
    # and the next test will fail.
    Repositories::RepositoryOwnerLock.release_rename_lock(owner_id: @repo.owner_id)
  end

  test "the repository is unlocked" do
    @repo.lock!(Repository::LockDependency::RENAME)
    assert @repo.reload.locked?

    rename(@repo, "totally-a-new-random-name-123456")

    refute @repo.reload.locked?
  end

  test "should update repo name in table" do
    rename(@repo, "longclaw")

    assert_equal "longclaw", @repo.name
  end

  test "works with case changes" do
    rename(@repo, "SomeSword")
    assert_equal "SomeSword", @repo.name
  end

  test "should return false if invalid repo name" do
    assert_equal false, rename(@repo, "someothersword")
  end

  test "should return false if owner changes during rename" do
    GitHub.flipper[:repo_transfer_owner_lock].enable
    # Although this is a different repo, the stub simulates the owner changing
    Repository.stubs(:find_by).returns(@repo_new_owner)
    refute rename(@repo, "repodepot")
  end

  test "should return true if owner changes during rename" do
    # Although this is a different repo, the stub simulates the owner changing
    Repository.stubs(:find_by).returns(@repo_new_owner)
    assert_equal true, rename(@repo, "repodepot")
  end

  test "should create a redirect entry for the old name" do
    rename(@repo, "longclaw")
    assert_equal 1, @repo.redirects.count
    assert_equal "jonsnow/somesword", @repo.redirects.first.repository_name
  end

  test "renaming a locked repo leaves it locked" do
    @repo.lock_for_billing
    rename(@repo, "finna-be-renamed")
    assert @repo.reload.locked_on_billing?
  end

  test "renaming a repository publishes an indexing event", skip_enterprise: true do
    GitHub.flipper[:geyser_denylist].disable

    rename(@repo, "finna-be-renamed")
    expected_event = {
      change: :ADMIN_REPAIR,
      repository: Hydro::EntitySerializer.repository(@repo),
      owner_name: @repo.owner.name,
    }
    assert_hydro_published_partial(expected_event, schema: "github.search.v0.RepositoryChanged")
    assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: RepositoryOrchestrationJob, args: [@repo.id, @repo.name]
  end

  def rename(repo, new_name)
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      repo.rename(new_name, actor: repo.owner)
    end
  end

  test "Repository#update fails due to validation error" do
    @retired_namespace = create(:retired_namespace,
      owner: @repo.owner,
      name: "finna-be-renamed",
    )

    RenameRepositoryOrchestration.any_instance.stubs(:renamable?).returns(true)
    RetiredNamespace.any_instance.stubs(:claimable_by?).returns(false)

    refute rename(@repo, "finna-be-renamed")

    orchestration = RenameRepositoryOrchestration.where(repository_id: @repo.id).first
    assert_equal "Name has been retired and cannot be reused", T.must(orchestration).error_message
  end

  test "failed rename rolls back changes" do
    @repo.create_repository_auth_version(version: 42)

    GitHub.flipper[:geyser_denylist].disable

    # Mock a failure during the auth_version increment, after the version is updated in the DB
    @repo.stubs(:reset_repository_auth_version).raises(StandardError.new("boom"))

    orig_name = @repo.name

    o = RepositoryOrchestration.rename(@repo, actor: @repo.owner, new_name: "finna-be-renamed")
    assert_raises StandardError do
      o.execute(synchronous: true)
    end

    assert_equal 1, o.attempts
    assert_equal "failed", o.state
    assert_equal "boom", o.error_message
    assert_equal "rename", o.step_name

    @repo.reload
    assert_equal orig_name, @repo.name
    assert_equal 42, @repo.auth_version
  end

  test "increments the repository_auth_version", skip_enterprise: true do
    @repo.create_repository_auth_version(version: 42)

    GitHub.flipper[:geyser_denylist].disable

    # Freeze time so the hydro event timestamps match
    Timecop.freeze do
      orig_name = @repo.name

      RepositoryOrchestration.rename(@repo, actor: @repo.owner, new_name: "finna-be-renamed").execute(synchronous: true)
      @repo.reload

      assert_equal 43, @repo.auth_version

      assert_hydro_published({
        change: :ADMIN_REPAIR,
        repository: Hydro::EntitySerializer.repository(@repo),
        auth_version: 43,
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

      assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
    end
  end

  test "blocks renames when the name doesn't match the given member privilege pattern" do
    GitHub.flipper[:member_privilege_rulesets].enable

    ruleset = create :repository_ruleset, :member_privileges, source: @org
    create(:repository_rule_configuration,
      :restrict_repository_name,
      repository_ruleset: ruleset,
      pattern: "mona.+",
    )

    refute rename(@org_repo, "invalidname")
  end

  test "allows renames if a member privilege ruleset has a matching pattern" do
    GitHub.flipper[:member_privilege_rulesets].enable

    ruleset = create :repository_ruleset, :member_privileges, source: @org
    create(:repository_rule_configuration,
      :restrict_repository_name,
      repository_ruleset: ruleset,
      pattern: "mona.+",
    )

    assert rename(@org_repo, "mona-valid-name")
  end

  test "blocks renames if a member privilege ruleset has a matching negated pattern" do
    GitHub.flipper[:member_privilege_rulesets].enable

    ruleset = create :repository_ruleset, :member_privileges, source: @org
    create(:repository_rule_configuration,
      :restrict_repository_name,
      repository_ruleset: ruleset,
      pattern: "invalid.+",
      negate: true,
    )

    refute rename(@org_repo, "invalid-name")
  end

  test "allows renames if a member privilege ruleset doesn't have a matching negated pattern" do
    GitHub.flipper[:member_privilege_rulesets].enable

    ruleset = create :repository_ruleset, :member_privileges, source: @org
    create(:repository_rule_configuration,
      :restrict_repository_name,
      repository_ruleset: ruleset,
      pattern: "invalid.+",
      negate: true,
    )

    assert rename(@org_repo, "mona-valid-name")
  end
end
