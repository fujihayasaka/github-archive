# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryWithEvenMoreGitReposOnDiskTest < GitHub::TestCase
  include HydroTestHelpers
  include HydroMessageJobTestHelpers

  self.these_tests_are_order_dependent_and_yearn_to_be_random

  fixtures do
    @mojombo  = create(:user, login: "mojombo2", plan: "medium")
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")
    @pj       = create(:user, login: "pj",       plan: "medium")
    @maddox   = create(:user, login: "maddox")
    @rtomayko = create(:user, login: "rtomayko")

    @grit     = create(:repository, name: "grit",     owner: @mojombo, from_example: :mojombo_grit)
    @ambition = create(:private_repository, name: "ambition", owner: @defunkt, from_example: :defunkt_ambition)
    @facebox  = create(:repository, name: "facebox",  owner: @defunkt, from_example: :defunkt_facebox)
    @gitrpc   = create(:repository, name: "gitrpc",   owner: @rtomayko, from_example: :simple)
    @simple   = create(:repository, name: "simple",   owner: @rtomayko, from_example: :repository_test_simple)
    @deleted  = create(:repository, name: "deleted",   owner: @rtomayko, from_example: :simple)

    create :user_email, user: @mojombo, email: "tom@mojombo.com"
    create :user_email, user: @defunkt, email: "chris@ozmm.org"
    create :user_email, user: @pj,      email: "pjhyett@gmail.com"


    @deleted.remove(@deleted.owner)
  end

  setup do
    example_repo :defunkt_ambition, @ambition
  end

  test "knows its disk usage" do
    @ambition.update_attribute :disk_usage, 0
    @ambition.update_disk_usage
    assert @ambition.reload.disk_usage >= 20,
      "#{@ambition.reload.disk_usage} should be >= 20"
  end

  test "knows how to represent its disk usage in human-friendly format" do
    @ambition.stubs disk_usage: 24
    assert_equal "24 KB", @ambition.human_disk_usage

    @simple.stubs disk_usage: 2394829
    assert_equal "2.28 GB", @simple.human_disk_usage
  end

  test "can find recently created public sources" do
    repos = Repository.find_all_public
    assert_equal 4, repos.size
  end

  test "knows network alternates are allowed for public repositories" do
    assert @grit.shared_storage_allowed?
    assert @facebox.shared_storage_allowed?
  end

  test "enabling and disabling network alternates" do
    assert !@gitrpc.network.shared_storage_enabled?, "network repo already exists"

    assert !@gitrpc.shared_storage_enabled?
    assert !@gitrpc.rpc.fs_exist?("objects/info/alternates")

    @gitrpc.enable_shared_storage
    assert @gitrpc.shared_storage_enabled?

    assert @gitrpc.network.shared_storage_enabled?

    assert @gitrpc.rpc.fs_exist?("objects/info/alternates")
    assert_equal "../../network.git/objects\n",
      @gitrpc.rpc.fs_read("objects/info/alternates")

    refute_nil @gitrpc.commits.find(@gitrpc.ref_to_sha("master"))

    @gitrpc.disable_shared_storage
    assert !@gitrpc.shared_storage_enabled?
    assert !@gitrpc.rpc.fs_exist?("objects/info/alternates")
  end

  # Looking for Repository#toggle_visibility tests? Check
  # test/models/repository_toggle_visibility_test.rb

  context "Deleting a forked repository" do
    test "decrements the parent's public_fork_count if the fork is public" do
      defunkt_grit = create(:fork_repository, forker: @defunkt, fork_repo: @grit)

      assert_difference "@grit.public_fork_count", -1 do
        defunkt_grit.destroy
      end
    end

    test "does not change the parent's public_fork_count if the fork is private" do
      @ambition.add_member(@mojombo)
      mojombo_ambition = create(:fork_repository, forker: @mojombo, fork_repo: @ambition)

      assert_no_difference "@ambition.public_fork_count" do
        mojombo_ambition.destroy
      end
    end

    test "removes collaborators" do
      @maddox.stubs(:can_fork?).returns(true)
      @ambition.add_member(@maddox)

      assert_difference "@defunkt.reload.collaborators_count", -1 do
        @ambition.remove_member(@maddox)
      end
    end
  end

  context "Deleting a repository" do
    test "removes collaborators" do
      @ambition.add_member(@pj)

      assert @ambition.member?(@pj)
      assert_difference "@defunkt.reload.collaborators_count", -1 do
        perform_enqueued_jobs(only: [ClearAbilitiesJob]) { @ambition.destroy }
      end
      refute @ambition.member?(@pj)
    end

    test "removes a repo from teams its on" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      team = create(:team, organization: org)
      team.add_repository repo, :pull
      assert team.batched_repositories.include?(repo)
      repo.destroy
      refute team.reload.batched_repositories.include?(repo)
    end

    test "removes language analysis data" do
      @ambition.analyze_languages
      analysis = @ambition.language_analysis
      refute_empty analysis.language_sizes
      @ambition.destroy
      assert_empty analysis.language_sizes
    end

    test "instrument removal of the repo when there are installations on all repositories" do
      events = subscribe "integration_installation.repositories_removed"

      user = create(:user, plan: "bronze")
      installation = make_integration_installation(target: user, permissions: { "metadata" => :read })
      integration = installation.integration
      new_repo = create(:private_repository, owner: user,
        created_by_user_id: user.id,
        deleted_by_user_id: user.id
      )

      only = [IntegrationInstallationRepositoryRemovalJob]
      perform_enqueued_jobs(only: only) do
        perform_enqueued_hydro_jobs(only: [HydroDeleteInstallationsRepositoryDeletedJob], allowed_primary_query_count: 27) do
          new_repo.remove(user, synchronous: true)
        end
      end
      new_repo.purge(synchronous: true)

      expected_payload = {}.tap do |payload|
        payload[:installation_id]      = installation.id
        payload[:actor]                = user.login
        payload[:actor_id]             = user.id
        payload[:integration]          = integration.name
        payload[:app]                  = integration.name
        payload[:integration_id]       = integration.id
        payload[:app_id]               = integration.id
        payload[:name]                 = integration.name
        payload[:slug]                 = integration.slug
        payload[:user]                 = user.to_s
        payload[:user_id]              = user.id
        payload[:repositories_removed] = [new_repo.id]
        payload[:repositories_removed_names] = [new_repo.full_name]
        payload[:repository_selection] = "all"

      end

      assert event = events.pop, "not instrumented"
      assert_equal expected_payload, event.payload

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :USER,
          target_id: user.id,
          target_name: user.login,
          repository_selection: :ALL,
        },
        repositories_removed: [Hydro::EntitySerializer.repository(new_repo)],
        sender: Hydro::EntitySerializer.user(user),
      }, schema: "github.v1.IntegrationInstallationRepositoriesRemoved")
    end

    test "instrument removal of the repo when the installation is installed on the repo directly" do
      events = subscribe "integration_installation.repositories_removed"

      user = create(:user, plan: "bronze")

      new_repo = create(:private_repository, owner: user,
        created_by_user_id: user.id,
        deleted_by_user_id: user.id
      )

      installation = make_integration_installation(repository: new_repo, permissions: { "metadata" => :read })
      integration = installation.integration

      only = [IntegrationInstallationRepositoryRemovalJob]
      perform_enqueued_jobs(only: only) do
        perform_enqueued_hydro_jobs(only: [HydroDeleteInstallationsRepositoryDeletedJob], allowed_primary_query_count: 4) do
          new_repo.remove(user, synchronous: true)
        end
      end
      new_repo.purge(synchronous: true)

      expected_payload = {}.tap do |payload|
        payload[:installation_id]      = installation.id
        payload[:actor]                = user.login
        payload[:actor_id]             = user.id
        payload[:integration]          = integration.name
        payload[:app]                  = integration.name
        payload[:integration_id]       = integration.id
        payload[:app_id]               = integration.id
        payload[:name]                 = integration.name
        payload[:slug]                 = integration.slug
        payload[:user]                 = user.to_s
        payload[:user_id]              = user.id
        payload[:repositories_removed] = [new_repo.id]
        payload[:repositories_removed_names] = [new_repo.full_name]
        payload[:repository_selection] = "selected"

      end

      assert event = events.pop, "not instrumented"
      assert_equal expected_payload, event.payload

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :USER,
          target_id: user.id,
          target_name: user.login,
          repository_selection: :SELECTED,
        },
        repositories_removed: [Hydro::EntitySerializer.repository(new_repo)],
        sender: Hydro::EntitySerializer.user(user),
      }, schema: "github.v1.IntegrationInstallationRepositoriesRemoved")
    end
  end

  test "fails if you use a reserved name" do
    repo = Repository.new(name: "..", owner: @mojombo)
    assert !repo.save
  end

  context "Creating a private repository" do
    unless GitHub.enterprise?
      test "fails if you've gone over your private repo quota" do
        user = create(:user)
        repo = build(:private_repository, owner: user)
        User.any_instance.stubs(:at_private_repo_limit?).returns(true)
        refute repo.save
        assert repo.errors[:visibility].any?
        assert_match /Please upgrade/, repo.errors[:visibility].first
      end
    end

    test "instruments addition of the repo when there are installations on all private repositories" do
      events = subscribe "integration_installation.repositories_added"

      user = create(:user, plan: "bronze")
      installation = make_integration_installation(target: user, permissions: { "metadata" => :read })
      integration = installation.integration
      new_repo = create(:private_repository, :full_creation, owner: user, created_by_user_id: user.id)

      expected_payload = {}.tap do |payload|
        payload[:installation_id]          = installation.id
        payload[:actor]                    = user.login
        payload[:actor_id]                 = user.id
        payload[:integration]              = integration.name
        payload[:app]                      = integration.name
        payload[:integration_id]           = integration.id
        payload[:app_id]                   = integration.id
        payload[:name]                     = integration.name
        payload[:slug]                     = integration.slug
        payload[:user]                     = user.to_s
        payload[:user_id]                  = user.id
        payload[:repositories_added]       = [new_repo.id]
        payload[:repositories_added_names] = [new_repo.full_name]
        payload[:repository_selection]     = "all"
        payload[:requester_id]             = nil
      end
      assert event = events.pop, "not instrumented"
      assert_equal expected_payload, event.payload
    end

    test "instruments addition of the repo when there are installations on all private repositories only once" do
      events = subscribe "integration_installation.repositories_added"

      user = create(:user, plan: "bronze")
      installation = make_integration_installation(target: user, permissions: { "metadata" => :read, "issues" => :read })
      create(:private_repository, :full_creation, owner: user, created_by_user_id: user.id)

      assert_equal 1, events.count
    end
  end

  context "force push rejection" do
    test "can be set to all, default, or none" do
      @simple.set_force_push_rejection "all", @simple.owner
      assert_equal "all", @simple.force_push_rejection
      assert_equal "all", @simple.config.get("git.reject_force_push")

      @simple.set_force_push_rejection false, @simple.owner
      assert_equal false, @simple.force_push_rejection
      assert_equal false, @simple.config.get("git.reject_force_push")

      @simple.set_force_push_rejection "default", @simple.owner
      assert_equal "default", @simple.force_push_rejection
      assert_equal "default", @simple.config.get("git.reject_force_push")
    end

    test "should allow by default" do
      assert_equal false, @simple.force_push_rejection,
        "should not deny force pushes by default"
      assert_nil @simple.config.get("git.reject_force_push")
    end

    test "can be set and cleared" do
      @simple.set_force_push_rejection "all", @simple.owner
      assert_equal "all", @simple.force_push_rejection
      assert_equal "all", @simple.config.get("git.reject_force_push")

      @simple.clear_force_push_rejection(@simple.owner)
      assert_equal false, @simple.force_push_rejection
      assert_nil @simple.config.get("git.reject_force_push")
    end

    test "manipulating the value clears all git-level config" do
      ["all", "default", false].each do |value|
        @simple.rpc.config_store("receive.denynonfastforwards", "true")
        @simple.rpc.config_store("receive.denynonffhead", "true")

        @simple.set_force_push_rejection value, @simple.owner

        assert_equal "false", @simple.rpc.config_get("receive.denynonfastforwards")
        assert_equal "false", @simple.rpc.config_get("receive.denynonffhead")
      end
    end

    test "clearing the value also clears all git-level config" do
      @simple.rpc.config_store("receive.denynonfastforwards", "true")
      @simple.rpc.config_store("receive.denynonffhead", "true")

      @simple.clear_force_push_rejection(@simple.owner)

      assert_equal "false", @simple.rpc.config_get("receive.denynonfastforwards")
      assert_equal "false", @simple.rpc.config_get("receive.denynonffhead")
    end

    test "manipulating the value only clears existing git-level config" do
      @repo = create(:repository, from_example: :simple)

      @repo.rpc.config_store("receive.denynonfastforwards", "true")

      @repo.set_force_push_rejection "all", @repo.owner

      assert_equal "false", @repo.rpc.config_get("receive.denynonfastforwards")
      assert_nil            @repo.rpc.config_get("receive.denynonffhead")
    end
  end

  context "max object size" do
    test "can be set to an integer, or zero" do
      @simple.set_max_object_size 0, @simple.owner
      assert_equal 0, @simple.max_object_size
      assert_equal "0", @simple.config.get("git.maxobjectsize")

      @simple.set_max_object_size 23, @simple.owner
      assert_equal 23, @simple.max_object_size
      assert_equal "23", @simple.config.get("git.maxobjectsize")
    end

    test "can be explicitly set to Repository::DEFAULT_MAX_OBJECT_SIZE" do
      @simple.set_max_object_size Configurable::MaxObjectSize::DEFAULT_MAX_OBJECT_SIZE, @simple.owner
      assert_equal Configurable::MaxObjectSize::DEFAULT_MAX_OBJECT_SIZE, @simple.max_object_size
      assert_equal Configurable::MaxObjectSize::DEFAULT_MAX_OBJECT_SIZE.to_s, @simple.config.get("git.maxobjectsize")
    end

    test "should be Repository::DEFAULT_MAX_OBJECT_SIZE by default" do
      assert_equal Configurable::MaxObjectSize::DEFAULT_MAX_OBJECT_SIZE, @simple.max_object_size, "should be Repository::DEFAULT_MAX_OBJECT_SIZE by default"
      assert_nil @simple.config.get("git.maxobjectsize")
    end

    test "can be set and cleared" do
      @simple.set_max_object_size 440, @simple.owner
      assert_equal 440, @simple.max_object_size
      assert_equal "440", @simple.config.get("git.maxobjectsize")

      @simple.clear_max_object_size(@simple.owner)
      assert_equal Configurable::MaxObjectSize::DEFAULT_MAX_OBJECT_SIZE, @simple.max_object_size
      assert_nil @simple.config.get("git.maxobjectsize")
    end
  end

  context "disk quota" do
    [:warn, :lock].each do |kind|
      test "can be set to an integer or zero (#{kind})" do
        @simple.set_disk_quota(kind: kind, value: 0, user: @simple.owner)
        assert_equal 0, @simple.disk_quota(kind: kind)
        assert_equal "0", @simple.config.get("git.#{kind}diskquota")

        @simple.set_disk_quota(kind: kind, value: 23, user: @simple.owner)
        assert_equal 23, @simple.disk_quota(kind: kind)
        assert_equal "23", @simple.config.get("git.#{kind}diskquota")
      end

      test "setting default clears it (#{kind})" do
        @simple.set_disk_quota(kind: kind, value: @simple.default_disk_quota(kind: kind), user: @simple.owner)
        assert_equal @simple.default_disk_quota(kind: kind), @simple.disk_quota(kind: kind)
        assert_nil @simple.config.get("git.#{kind}diskquota")
      end

      test "can be set and cleared (#{kind})" do
        @simple.set_disk_quota(kind: kind, value: 440, user: @simple.owner)
        assert_equal 440, @simple.disk_quota(kind: kind)
        assert_equal "440", @simple.config.get("git.#{kind}diskquota")

        @simple.clear_disk_quota(kind: kind, user: @simple.owner)
        assert_equal @simple.default_disk_quota(kind: kind), @simple.disk_quota(kind: kind)
        assert_nil @simple.config.get("git.#{kind}diskquota")
      end
    end
  end

  context "ssh access" do
    test "defaults to true" do
      assert @simple.ssh_enabled?
    end

    test "can be disabled" do
      @simple.disable_ssh(@simple.owner)
      refute @simple.reload.ssh_enabled?
    end

    test "can be disabled via the owner" do
      @simple.owner.disable_ssh(@simple.owner)
      refute @simple.reload.ssh_enabled?
    end
  end
end
