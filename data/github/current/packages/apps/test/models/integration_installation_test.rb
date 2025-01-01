# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"
require "apps/k_v"

class IntegrationInstallationTest < GitHub::TestCase
  include PermissionsHelper

  fixtures do
    @admin = create(:paid_user)
    @staff = create(:staff_admin_user)
    @member = create(:user)
    @collaborator = create(:user)
    @integration = create(:integration, default_permissions: { "metadata" => :read })
    @another_integration = create(:integration, default_permissions: { "metadata" => :read })
    @org   = create(:organization, admin: @admin)
    @org.add_member(@member)
    @repo  = create(:private_repository, :minimal, owner: @org)
    @repo.add_member(@collaborator)
    @public_repo = create(:repository, :minimal, owner: @org)
    @user_repo = create(:private_repository, :minimal, owner: @admin)
    @installation = make_integration_installation(integration: @integration, repository: @repo, events: ["label"])
    @user_installation = make_integration_installation(integration: @integration, repository: @user_repo)
    @org_installation = make_integration_installation(target: @org, repository: create(:private_repository, :minimal, owner: @org))
    @staff = create(:staff_admin_user)
  end

  context "validation" do
    test "requires an application" do
      installation = IntegrationInstallation.new
      installation.valid?

      refute_predicate installation.errors[:integration], :blank?
    end

    test "requires a target" do
      installation = IntegrationInstallation.new
      installation.valid?

      refute_predicate installation.errors[:target], :blank?
    end

    test "VALID_TARGET_TYPES" do
      assert_equal %w(User Business), IntegrationInstallation::VALID_TARGET_TYPES
    end

    test "requires an integration version number" do
      installation = IntegrationInstallation.new
      refute_predicate installation, :valid?

      refute_predicate installation.errors[:integration_version_id], :blank?
    end

    test "uniqueness for integration_id, target_id and target_type" do
      target = create(:organization)
      GitHub.stubs(:launch_github_app).returns(@another_integration)

      installation = make_integration_installation(integration: @integration, target: target)
      assert_predicate installation, :valid?

      installation_dup = IntegrationInstallation.create(
        integration: @integration,
        target: target,
        integration_version_id: @integration.latest_version.number,
        integration_version_number: @integration.latest_version.number,
      )

      refute_predicate installation_dup, :valid?
    end

  end

  test "can have granular permissions" do
    installation = IntegrationInstallation.new
    assert_predicate installation, :can_have_granular_permissions?
  end

  test "cannot have granular user permissions" do
    installation = IntegrationInstallation.new
    refute_predicate installation, :can_have_granular_user_permissions?
  end

  test "has a the latest version on creation" do
    assert_equal @installation.integration_version_id, @integration.latest_version.id
    assert_equal @installation.integration_version_number, @integration.latest_version.number
  end

  context "#repositories" do
    test "returns an scoped relation for the repositories this installation has any permission on" do
      assert_same_elements [@repo], @installation.repositories.all
    end

    test "doesn't return repositories that have been removed (soft-deleted)" do
      integration = create(:integration, default_permissions: { "metadata" => :read })

      installation =
        integration.install_on(@org, repositories: [@repo, @public_repo], installer: @admin, entry_point: :test_case).installation

      assert_same_elements [@repo, @public_repo], installation.repositories.all

      @public_repo.remove(@admin)
      refute_predicate @public_repo, :active?
      assert_same_elements [@repo], installation.repositories.all
    end

    test "limits results to a minimum specified permission" do
      assert_empty @installation.repositories(min_action: :write)
    end

    test "limits results to repos with access via a specified resource" do
      assert_same_elements [@repo], @installation.repositories(resource: "metadata").all
    end

    test "does not include repos, with access other than the specified resource" do
      assert_empty @installation.repositories(resource: "issues")
    end

    test "returns an empty scope if passed an invalid resource" do
      assert_empty @installation.repositories(resource: "stuff")
    end
  end

  context "#repository_ids" do
    test "returns an Array of ids for the repositories this installation has any permission on" do
      assert_same_elements [@repo.id], @installation.repository_ids
    end

    test "limits results to a minimum specified permission" do
      assert_empty @installation.repository_ids(min_action: :write)
    end

    test "limits results to repos with access via a specified resource" do
      integration = create(:integration, default_permissions: { "statuses" => :read })
      installation =
        integration.install_on(@org, repositories: [@repo, @public_repo], installer: @admin, version: integration.latest_version, entry_point: :test_case).installation

      assert_same_elements [@repo.id, @public_repo.id], installation.repository_ids(resource: "statuses")
    end

    test "does not include repos, with access other than the specified resource" do
      assert_empty @installation.repository_ids(resource: "issues")
    end

    test "returns an empty Array if passed an invalid resource" do
      assert_empty @installation.repository_ids(resource: "stuff")
    end

    test "includes individual repository ids, for an installation installed on all user's repositories" do
      org = create(:organization)
      repo = create(:private_repository, :minimal, owner: org)
      public_repo = create(:repository, :minimal, owner: org)
      version = @integration.versions.create(default_permissions: { "statuses" => :read })
      installation =
        @integration.install_on(org, repositories: [], installer: org.admins.first, version: version, entry_point: :test_case).installation

      assert_same_elements [repo.id, public_repo.id], installation.repository_ids
    end

    test "includes individual repository ids, for an installation installed on all user's repositories, for a specified resource" do
      org = create(:organization)
      repo = create(:private_repository, :minimal, owner: org)
      public_repo = create(:repository, :minimal, owner: org)
      version = @integration.versions.create(default_permissions: { "statuses" => :read })
      installation =
        @integration.install_on(org, repositories: [], installer: org.admins.first, version: version, entry_point: :test_case).installation

      assert_same_elements [repo.id, public_repo.id], installation.repository_ids(resource: "statuses")
    end

    test "does not include repos, with access other than the specified resource, when installed on all repositories" do
      org = create(:organization)
      create(:private_repository, :minimal, owner: org)
      create(:repository, :minimal, owner: org)
      version = @integration.versions.create(default_permissions: { "statuses" => :read })
      installation =
        @integration.install_on(org, repositories: [], installer: org.admins.first, version: version, entry_point: :test_case).installation

      assert_empty installation.repository_ids(resource: "issues")
    end

    context "excludes advisory workspace repositories when installed on all" do
      test "with #repository_ids" do
        repository = create(:repository, :minimal)
        author     = repository.owner
        advisory   = create(:repository_advisory, repository: repository, author: author)

        GitHub.context.push(actor_id: author.id)
        workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, author).tap(&:save!)
        installation   = make_integration_installation(target: author, permissions: { "metadata" => :read })

        assert_predicate installation, :installed_on_all_repositories?
        assert_equal [repository.id], installation.repository_ids
      end

      test "with #repositories" do
        repository = create(:repository, :minimal)
        author     = repository.owner
        advisory   = create(:repository_advisory, repository: repository, author: author)

        GitHub.context.push(actor_id: author.id)
        workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, author).tap(&:save!)
        installation   = make_integration_installation(target: author, permissions: { "metadata" => :read })

        assert_predicate installation, :installed_on_all_repositories?
        assert_equal [repository.id], installation.repositories.pluck(:id)
      end
    end

    test "filters the results based on a list of repo ids" do
      repos = create_list(:repository, 2, owner: @org)

      installation = make_integration_installation(repositories: repos, permissions: { "metadata" => :read })

      actual_ids = installation.repository_ids(
        repository_ids: [repos.first.id]
      )

      assert_same_elements [repos.first.id], actual_ids
    end

    test "filters the results based on a list of repo ids, in batches" do
      org = create(:organization)

      repos         = create_list(:repository, 4, owner: org)
      filtered_ids  = [repos.first.id, repos.last.id]
      external_ids  = [repos.last.id + 1_000, repos.last.id + 1_001]

      installation = make_integration_installation(repositories: repos, permissions: { "metadata" => :read })

      IntegrationInstallable.stub_const(:BATCH_SIZE, 2) do
        actual_ids = installation.repository_ids(
          repository_ids: filtered_ids + external_ids
        )

        assert_same_elements filtered_ids, actual_ids
      end
    end

    test "returns an empty array if the installation is not persisted" do
      assert_predicate IntegrationInstallation.new.repository_ids, :empty?
      assert_predicate IntegrationInstallation.new.repositories, :empty?
    end

    test "filters out non active repositories when installed on all repos" do
      active_repo = create(:repository, :minimal, owner: @org)
      deleted_repo = create(:deleted_repository, owner: @org)

      installation = make_integration_installation(target: @org, permissions: { "metadata" => :read })

      actual_ids = installation.repository_ids
      refute_includes installation.repository_ids, deleted_repo.id
    end

    test "does not filter out non active repositories when installed on selected repos" do
      active_repo = create(:repository, :minimal, owner: @org)
      deleted_repo = create(:repository, :minimal, owner: @org)

      installation = make_integration_installation(repositories: [active_repo, deleted_repo], permissions: { "metadata" => :read })

      deleted_repo.update(active: nil)

      actual_ids = installation.repository_ids
      assert_includes installation.repository_ids, deleted_repo.id
    end

    test "does not filter out non active repositories when installed on selected repos when providing repository ids" do
      active_repo = create(:repository, :minimal, owner: @org)
      deleted_repo = create(:repository, :minimal, owner: @org)

      installation = make_integration_installation(repositories: [active_repo, deleted_repo], permissions: { "metadata" => :read })

      deleted_repo.update(active: nil)

      actual_ids = installation.repository_ids(repository_ids: [active_repo.id, deleted_repo.id])
      assert_same_elements [active_repo.id, deleted_repo.id], actual_ids
    end
  end

  context "#repositories_count" do
    test "returns the count of repositories when installated on selected repositories" do
      repos = create_list(:repository, 2, owner: @org)
      installation = make_integration_installation(
        repositories: repos,
        permissions: { "metadata" => :read, "issues" => :write },
      )
      assert_equal 2, installation.repositories_count
      refute_equal @org.repository_ids.count, installation.repositories_count
    end

    test "returns the count of repositories when installed on all" do
      org = create(:organization)
      create_list(:repository, 3, owner: org)

      installation = make_integration_installation(
        target: org,
        permissions: { "metadata" => :read, "issues" => :write },
      )

      assert_equal 3, installation.repositories_count

      create(:repository, owner: org)
      assert_equal 4, installation.repositories_count
    end

    test "excludes advisory repos when installed on all" do
      org = create(:organization)
      org_repos = create_list(:repository, 3, owner: org)
      advisory_repo = create(:repository_advisory, :with_workspace, repository: org_repos.first, author: org.admins.first)

      installation = make_integration_installation(
        target: org,
        permissions: { "metadata" => :read, "issues" => :write },
      )

      assert_equal 1, RepositoryAdvisory.where(owner_id: org.id).count
      assert_equal 3, installation.repositories_count
    end

    test "properly instruments the query based on the flipper flag" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      installation = make_integration_installation(
        target: create(:organization),
        permissions: { "metadata" => :read, "issues" => :write },
      )

      installation.repositories_count

      metric = "permission_grantable.repositories_count"
      assert_equal 1, GitHub.dogstats.distributions(metric).length
    end
  end

  context "#events" do
    test "accepts events" do
      installation = IntegrationInstallation.new events: %w(issues)
      assert_equal %w(issues), installation.events
      assert_equal 1, installation.event_records.size
    end

    test "adds new events" do
      integration = create(:integration, :with_active_hook,
        default_permissions: { "issues" => :read, "pull_requests" => :read },
        default_events: %w(issues),
      )

      installation = integration.install_on(
        @org,
        repositories: [@repo],
        version: integration.latest_version,
        installer: @admin,
        entry_point: :test_case).installation

      assert_equal %w(issues), installation.events

      installation.update! events: %w(issues pull_request)
      assert_same_elements %w(issues pull_request), installation.reload.events
    end

    test "removes old events" do
      integration = create(:integration, :with_active_hook,
        default_permissions: { "issues" => :read, "pull_requests" => :read },
        default_events: %w(issues pull_request),
      )

      version = integration.versions.create(
        default_permissions: { "issues" => :read, "pull_requests" => :read },
        default_events: %w(issues),
      )

      installation = integration.install_on(
        @org,
        repositories: [@repo],
        version: version,
        installer: @admin,
        entry_point: :test_case
      ).installation

      assert_equal %w(issues), installation.events

      installation.update! events: %w(pull_request)
      assert_same_elements %w(pull_request), installation.reload.events
    end

    test "raises an error when trying to directly mutate events" do
      assert_raises FrozenError do
        IntegrationInstallation.new.events << "pull_request"
      end
    end

    test "persists the events collection on save" do
      integration = create(:integration, :with_active_hook,
        default_permissions: { "issues" => :read, "pull_requests" => :read },
        default_events: %w(issues pull_request)
      )

      installation = integration.install_on(
        @org,
        repositories: [@repo],
        version: integration.latest_version,
        installer: @admin,
        entry_point: :test_case
      ).installation

      installation.events = %w(issues)
      assert_equal %w(issues), installation.events

      event_records = installation.event_records
      assert_equal 2, event_records.count

      pull_request_event = installation.event_records.detect { |r| r.name == "pull_request" }
      assert_predicate pull_request_event, :marked_for_destruction?

      installation.save!

      assert_equal 1, installation.event_records.count
    end
  end

  context "#generate_token" do
    test "creates a token for the installation" do
      _, token_value = @installation.generate_token
      token       = ServerToServerTokens.domain.by_unhashed_token(token_value)

      token = T.must(token)
      assert_equal @installation, token.authenticatable_class.find_by(id: token.authenticatable_id)
    end
  end

  context "#bot" do
    test "returns the integration's bot" do
      assert_equal @integration.bot, @installation.bot
    end

    test "sets the installation as the bot's current installation context" do
      assert_equal @installation, @installation.bot.installation
    end
  end

  context "#organization" do
    test "returns the target when it's an organization" do
      assert_equal @org, @installation.organization
    end

    test "returns nil when the target is a user", skip_with_all_emus: true do
      assert_nil @user_installation.organization
    end
  end

  context ".user_installable", skip_with_all_emus: true do
    test "includes regular third-party installations" do
      user = create(:user)
      integration_one = create(:integration, name: "Regular App one")
      integration_two = create(:integration, name: "Regular App two")
      installation_one = make_integration_installation(target: user, integration: integration_one)
      installation_two = make_integration_installation(target: user, integration: integration_two)

      user_installable = IntegrationInstallation.user_installable
      assert_includes user_installable, installation_one
      assert_includes user_installable, installation_two
    end

    test "excludes installations of Apps that have been configured as non user-installable" do
      user = create(:user)
      integration_one = create(:integration, name: "Regular App one")
      non_user_installable_integration = create_privileged_app_with_capabilities(
        capabilities: { user_installable: false },
        options: { name: "Internal App two" }
      )
      installation_one = make_integration_installation(target: user, integration: integration_one)
      installation_two = make_integration_installation(target: user, integration: non_user_installable_integration)

      user_installable = IntegrationInstallation.user_installable
      assert_includes user_installable, installation_one
      refute_includes user_installable, installation_two
    end

    test "optionally accepts a Apps::Privileged::Query argument to perform the capability lookup" do
      user = create(:user)
      integration_one = create(:integration, name: "Regular App one")
      non_user_installable_integration = create(:integration, name: "Internal App two")
      installation_one = make_integration_installation(target: user, integration: integration_one)
      installation_two = make_integration_installation(target: user, integration: non_user_installable_integration)

      stubbed_query = Apps::Privileged::Query.new
      stubbed_query.expects(:without_capability).
        with(:user_installable, type: Integration).once.returns([non_user_installable_integration.id])

      user_installable = IntegrationInstallation.user_installable(stubbed_query)
      assert_includes user_installable, installation_one
      refute_includes user_installable, installation_two
    end
  end

  context ".with_repository" do
    test "finds installations that have an ability on the given repository's contents" do
      integration = create(:integration, default_permissions: { "contents" => :read })

      repo_a = create(:private_repository, :minimal, owner: @org)
      repo_b = create(:private_repository, :minimal, owner: @org)

      installation =
        integration.install_on(
          @org, repositories: [repo_a],
          version: integration.latest_version,
          installer: @admin,
          entry_point: :test_case).installation
      assert_includes IntegrationInstallation.with_repository(repo_a), installation
      refute_includes IntegrationInstallation.with_repository(repo_b), installation
    end

    test "finds installations that have an ability on the given repository's pull requests" do
      integration = create(:integration, default_permissions: { "pull_requests" => :read })

      repo_a = create(:private_repository, :minimal, owner: @org)
      repo_b = create(:private_repository, :minimal, owner: @org)

      installation =
        integration.install_on(
          @org,
          repositories: [repo_a],
          version: integration.latest_version,
          installer: @admin,
          entry_point: :test_case).installation
      assert_includes IntegrationInstallation.with_repository(repo_a), installation
      refute_includes IntegrationInstallation.with_repository(repo_b), installation
    end

    test "finds installations that have an ability on the given repository's commit statuses" do
      integration = create(:integration, default_permissions: { "statuses" => :read })

      repo_a = create(:private_repository, :minimal, owner: @org)
      repo_b = create(:private_repository, :minimal, owner: @org)

      installation =
        integration.install_on(
          @org,
          repositories: [repo_a],
          version: integration.latest_version,
          installer: @admin,
          entry_point: :test_case).installation
      assert_includes IntegrationInstallation.with_repository(repo_a), installation
      refute_includes IntegrationInstallation.with_repository(repo_b), installation
    end

    test "finds installations that have an ability on all private repositories for the given repository's owner" do
      repo_a = create(:private_repository, :minimal, owner: @org)
      integration = create(:integration, default_permissions: { "statuses" => :read })
      integration_b = create(:integration, default_permissions: { "statuses" => :read })

      installation =
        integration.install_on(@org, repositories: [], installer: @admin, entry_point: :test_case).installation

      installation_b =
        integration_b.install_on(@org, repositories: [], installer: @admin, entry_point: :test_case).installation

      assert_includes IntegrationInstallation.with_repository(repo_a), installation
      assert_includes IntegrationInstallation.with_repository(repo_a), installation_b
    end
  end

  context ".with_target" do
    test "finds all installations for a given target" do
      org_installation1 = make_integration_installation(repositories: [@repo], permissions: { "metadata" => :read })
      org_installation2 = make_integration_installation(repositories: [@repo], permissions: { "metadata" => :read })

      user_installation = make_integration_installation(repositories: [create(:repository, :minimal, owner: @admin)])

      org_installations = IntegrationInstallation.with_target(@org)
      user_installations = IntegrationInstallation.with_target(@admin)
      assert_includes org_installations, org_installation1
      assert_includes org_installations, org_installation2
      refute_includes org_installations, user_installation

      unless GitHub.single_or_multi_tenant_enterprise?
        assert_includes user_installations, user_installation
        refute_includes user_installations, org_installation1
      end
    end
  end

  context ".with_resources_on" do
    test "finds installations that have an ability on the given repository's contents" do
      org = create(:organization)

      repo_a = create(:private_repository, :minimal, owner: org)
      repo_b = create(:private_repository, :minimal, owner: org)

      @integration.update(default_permissions: { "contents" => :read })
      @integration.reload

      installation = make_integration_installation(integration: @integration, repository: repo_a)

      assert_includes IntegrationInstallation.with_resources_on(subject: repo_a, resources: :contents), installation
      refute_includes IntegrationInstallation.with_resources_on(subject: repo_b, resources: :contents), installation
    end

    test "finds installations that have an ability and a minimum action on the given repository's contents" do
      org = create(:organization)

      repo_a = create(:private_repository, :minimal, owner: org)
      repo_b = create(:private_repository, :minimal, owner: org)

      @integration.update(default_permissions: { "contents" => :read })
      @integration.reload

      installation = make_integration_installation(integration: @integration, repository: repo_a)

      assert_includes IntegrationInstallation.with_resources_on(subject: repo_a, resources: :contents, min_action: :read), installation
      refute_includes IntegrationInstallation.with_resources_on(subject: repo_b, resources: :contents, min_action: :read), installation

      refute_includes IntegrationInstallation.with_resources_on(subject: repo_a, resources: :contents, min_action: :write), installation
      refute_includes IntegrationInstallation.with_resources_on(subject: repo_b, resources: :contents, min_action: :write), installation
    end

    test "finds installations that have an ability on the given repository's pull requests" do
      org = create(:organization)

      repo_a = create(:private_repository, :minimal, owner: org)
      repo_b = create(:private_repository, :minimal, owner: org)

      @integration.update(default_permissions: { "pull_requests" => :read })
      @integration.reload

      installation = make_integration_installation(integration: @integration, repository: repo_a)

      assert_includes IntegrationInstallation.with_resources_on(subject: repo_a, resources: :pull_requests), installation
      refute_includes IntegrationInstallation.with_resources_on(subject: repo_b, resources: :pull_requests), installation
    end

    test "finds installations that have an ability on the given repository's commit statuses" do
      org = create(:organization)

      repo_a = create(:private_repository, :minimal, owner: org)
      repo_b = create(:private_repository, :minimal, owner: org)

      @integration.update(default_permissions: { "statuses" => :read })
      @integration.reload

      installation = make_integration_installation(integration: @integration, repository: repo_a)

      assert_includes IntegrationInstallation.with_resources_on(subject: repo_a, resources: :statuses), installation
      refute_includes IntegrationInstallation.with_resources_on(subject: repo_b, resources: :statuses), installation
    end

    test "finds installations that have an ability on all private repositories for the given repository's owner" do
      repo_a = create(:private_repository, :minimal, owner: @org)

      installation   = make_integration_installation(target: @org, permissions: { "statuses" => :read })
      installation_b = make_integration_installation(target: @org, permissions: { "statuses" => :read })

      assert_includes IntegrationInstallation.with_resources_on(subject: repo_a, resources: :statuses), installation
      assert_includes IntegrationInstallation.with_resources_on(subject: repo_a, resources: :statuses), installation_b
    end

    test "finds installations with a specific permission on a repository" do
      repo_a = create(:private_repository, :minimal, owner: @org)

      installation_a = make_integration_installation(repository: repo_a, permissions: { "contents" => :read })
      installation_b = make_integration_installation(repository: repo_a, permissions: { "metadata" => :read })

      assert_includes IntegrationInstallation.with_resources_on(subject: repo_a, resources: :contents), installation_a
      refute_includes IntegrationInstallation.with_resources_on(subject: repo_a, resources: :contents), installation_b
    end

    test "finds all installations with org wide permission for the given org" do
      installation_with_members_read  = make_integration_installation(target: @org, permissions: { "members" => :read })
      installation_with_members_write = make_integration_installation(target: @org, permissions: { "members" => :write })

      _rando_installation = make_integration_installation(target: create(:organization), permissions: { "members" => :read })

      assert_same_elements [installation_with_members_read, installation_with_members_write], \
        IntegrationInstallation.with_resources_on(subject: @org, resources: :members)
    end

    test "finds all installations with specific org wide permission for the given org" do
      installation_with_members_read = make_integration_installation(target: @org, permissions: { "members" => :read })

      _installation_pull_requests_write = make_integration_installation(target: @org, permissions: { "pull_requests" => :write })
      _rando_installation               = make_integration_installation(target: create(:organization), permissions: { "members" => :read })

      assert_same_elements [installation_with_members_read], \
        IntegrationInstallation.with_resources_on(subject: @org, resources: :members)
    end
  end

  context ".with_org_permissions" do
    test "finds all installations with org wide permission for the given org" do
      integration = create(:integration, default_permissions: { "members" => :read })

      org_installation1 =
        integration.install_on(@org, repositories: [], installer: @admin, entry_point: :test_case).installation

      other_integration = create(:integration, default_permissions: { "members" => :write })
      org_installation2 =
        other_integration.install_on(@org, repositories: [], installer: @admin, entry_point: :test_case).installation

      _other_org_installation =
        other_integration.install_on(create(:organization), repositories: [], installer: @admin, entry_point: :test_case).installation

      assert_same_elements [org_installation1, org_installation2], IntegrationInstallation.with_org_permissions(@org)
    end
  end

  context "deletion locking" do
    test "persists locking info" do
      IntegrationInstallation.lock_target_for_deletion(@installation)

      assert Apps::KV.store.exists(IntegrationInstallation.target_deletion_lock_key(@installation)).value { raise "this should never have happened!" }
      assert IntegrationInstallation.target_locked_for_deletion?(@installation)
    end

    test "checks if a target is locked for deletion" do
      refute IntegrationInstallation.target_locked_for_deletion?(@installation)

      IntegrationInstallation.lock_target_for_deletion(@installation)

      assert IntegrationInstallation.target_locked_for_deletion?(@installation)
    end
  end

  context "target deletion lock key" do
    test "builds key based on installation target when record is installation" do
      key = IntegrationInstallation.target_deletion_lock_key(@installation)
      assert_equal "integration_installation:lock:#{@installation.target_type}:#{@installation.target_id}:deleted", key
    end

    test "builds key based on user info when record is a user" do
      key = IntegrationInstallation.target_deletion_lock_key(@admin)
      assert_equal "integration_installation:lock:#{@admin.class.base_class}:#{@admin.id}:deleted", key
    end
  end

  context "not_suspended" do
    test "fiters out installations suspended by the integrator" do
      integration = create(:integration)

      installation1 = make_integration_installation(integration: integration, target: @org)
      installation2 = make_integration_installation(integration: integration, target: create(:organization, admin: @admin))

      installation2.suspend!; installation2.reload
      assert_predicate installation2, :integrator_suspended?

      assert_same_elements [installation1], integration.installations.not_suspended
    end

    test "filters out installations suspended by the target" do
      integration = create(:integration)

      installation1 = make_integration_installation(integration: integration, target: @org)
      installation2 = make_integration_installation(integration: integration, target: create(:organization, admin: @admin))

      installation2.suspend!(user: @admin); installation2.reload
      assert_predicate installation2, :user_suspended?

      assert_same_elements [installation1], integration.installations.not_suspended
    end
  end

  context "suspended" do
    test "fiters out installations not suspended by the integrator" do
      integration = create(:integration)

      installation1 = make_integration_installation(integration: integration, target: @org)
      installation2 = make_integration_installation(integration: integration, target: create(:organization, admin: @admin))

      installation2.suspend!; installation2.reload
      assert_predicate installation2, :integrator_suspended?

      assert_same_elements [installation2], integration.installations.suspended
    end

    test "filters out installations suspended by the target" do
      integration = create(:integration)

      installation1 = make_integration_installation(integration: integration, target: @org)
      installation2 = make_integration_installation(integration: integration, target: create(:organization, admin: @admin))

      installation2.suspend!(user: @admin); installation2.reload
      assert_predicate installation2, :user_suspended?

      assert_same_elements [installation2], integration.installations.suspended
    end
  end

  context "#uninstall" do
    test "destroys the installation" do
      assert_difference "IntegrationInstallation.count", -1 do
        @installation.uninstall
      end
    end

    test "new job destroys the authentication tokens" do
      @installation.generate_token
      @installation.generate_token
      token_records = ServerToServerTokens.domain.by_authenticatable_id(@installation.id)
      token_records = T.must(token_records)
      assert_equal 2, token_records.size

      perform_enqueued_jobs(only: [DestroyAuthenticationTokensJob]) do
        @installation.uninstall
      end

      token_records = ServerToServerTokens.domain.by_authenticatable_id(@installation.id)
      token_records = T.must(token_records)
      assert_equal 0, token_records.size
    end

    test "revokes installation bot access" do
      assert_able @installation.bot, :read, @repo.resources.metadata

      perform_enqueued_jobs(only: [AddToSearchIndexJob, DestroyDependentRecordsJob]) { @installation.uninstall }

      refute_able @installation.bot, :read, @repo.resources.statuses
    end

    test "destroys the installation's hook event subscriptions" do
      refute_empty @installation.event_records

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        @installation.uninstall
      end

      assert_empty @installation.event_records
    end

    test "destroys the scoped integration installations" do
      make_scoped_integration_installation(parent: @installation, repositories: [@repo])
      refute_empty @installation.children

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        @installation.uninstall
      end

      assert_empty @installation.children
    end

    test "doesn't destroy the installation's hook event subscriptions in the foreground" do
      refute_empty @installation.event_records

      perform_enqueued_jobs(only: []) do
        @installation.uninstall
      end

      # These should still exist, since we didn't perform the DestroyDependentRecordsJob job.
      refute_empty @installation.event_records
    end

    test "doesn't destroy the installation's scoped integration installations in the foreground" do
      make_scoped_integration_installation(parent: @installation, repositories: [@repo])
      refute_empty @installation.children

      perform_enqueued_jobs(only: []) do
        @installation.uninstall
      end

      # These should still exist, since we didn't perform the DestroyDependentRecordsJob job.
      refute_empty @installation.children
    end
  end

  test "destroy deletes permissions" do
    assert_able @installation.bot, :read, @repo.resources.metadata

    grant_direct_admin_permission(
      actor: @installation,
      subject: @repo.resources.metadata,
    )

    perform_enqueued_jobs(only: [AddToSearchIndexJob, DestroyDependentRecordsJob]) { @installation.destroy }

    refute_granted_in_permissions_table(
      actor_id: @installation.ability_id,
      actor_type: @installation.ability_type,
      subject_id: @repo.resources.statuses.ability_id,
      subject_type: @repo.resources.statuses.ability_type,
    )
  end

  test "destroy clears related subscription item installed_at" do
    subscription_item = create(:billing_subscription_item, installed_at: Time.current)
    @installation.update!(subscription_item: subscription_item)

    @installation.destroy

    assert_nil subscription_item.reload.installed_at
  end

  test "destroy doesn't raise exception if subscription_item no longer exists" do
    @installation.update!(subscription_item_id: nil)

    assert_nothing_raised do
      @installation.destroy
    end
  end

  context "cached permissions attributes" do
    test "get_cached_permissions works with mysql JSON attributes" do
      @user_installation.update(permissions_cache: @user_installation.permissions)
      assert_instance_of Hash, @user_installation.permissions_cache

      assert_equal @user_installation.permissions, @user_installation.get_cached_permissions
    end

    test "sets cached permissions using mysql JSON" do
      assert_nil @user_installation.permissions_cache

      assert_equal @user_installation.permissions, @user_installation.get_cached_permissions
    end

    test "does not clear the cache if the installation has recently been updated" do
      enable_feature_flag(:integration_installation_permissions_cache_ttl)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @user_installation.update(permissions_cache: @user_installation.permissions)
      timestamp = @user_installation.updated_at

      Timecop.travel(1.minute.from_now) do
        @user_installation.get_cached_permissions
        assert_equal timestamp, @user_installation.reload.updated_at

        metric = "integration_installation.permissions_cache"
        expected_tags = ["clear_cache:true"]
        assert_empty GitHub.dogstats.increments(metric, tags: expected_tags)
      end
    end

    test "does clear the cache if the installation has not recently been updated" do
      enable_feature_flag(:integration_installation_permissions_cache_ttl)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @user_installation.update(permissions_cache: @user_installation.permissions)
      old_timestamp = @user_installation.updated_at

      Timecop.freeze(new_timestamp = 2.weeks.from_now) do
        @user_installation.get_cached_permissions
        refute_equal old_timestamp, @user_installation.reload.updated_at
        assert_equal new_timestamp.to_i, @user_installation.updated_at.to_i

        metric = "integration_installation.permissions_cache"
        expected_tags = ["clear_cache:true"]
        assert_equal 1, GitHub.dogstats.increments(metric, tags: expected_tags).length
      end
    end

    test "does not clear the cache if the installation has not recenty been updated and the ff is disabled" do
      disable_feature_flag(:integration_installation_permissions_cache_ttl)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @user_installation.update(permissions_cache: @user_installation.permissions)
      old_timestamp = @user_installation.updated_at

      Timecop.travel(2.weeks.from_now) do
        @user_installation.get_cached_permissions
        assert_equal old_timestamp, @user_installation.reload.updated_at

        metric = "integration_installation.permissions_cache"
        expected_tags = ["clear_cache:true"]
        assert_empty GitHub.dogstats.increments(metric, tags: expected_tags)
      end
    end
  end

  context "conditionally cached permissions based on feature flag" do
    test "with the feature flag enabled", skip_if_feature_disabled: :cached_fgp_permissions do
      installation = make_integration_installation(integration: @integration, repository: create(:repository, :minimal))

      installation.permissions; installation.reload
      refute_nil installation.permissions_cache
    end

    test "with the feature flag disabled", skip_if_feature_enabled: :cached_fgp_permissions do
      installation = make_integration_installation(integration: @integration, repository: create(:repository, :minimal))

      installation.permissions; installation.reload
      assert_nil installation.permissions_cache
    end
  end

  context "#default_repository_permission" do
    test "raises, with an invalid resource" do
      assert_raises ArgumentError do
        @installation.default_repository_permission(resource: "bogus_resource")
      end
    end

    test "returns a Integer representing the permission level the installation has for the specified resource" do
      installation = make_integration_installation(target: @org, permissions: { "metadata" => :read, "issues" => :write })

      assert_equal 1, installation.default_repository_permission(resource: "issues")
    end

    test "returns nil if the installation has no permission for the specified resource" do
      assert_nil @installation.default_repository_permission(resource: "statuses")
    end
  end

  context "#installed_on_all_repositories?" do
    test "returns true if the installation is on all private repositories" do
      installation = make_integration_installation(target: @org, permissions: { "issues" => :write })
      assert installation.installed_on_all_repositories?
    end

    test "returns false if the installation is not on all private repositories" do
      refute @installation.installed_on_all_repositories?
    end

    test "returns true if the installation is on all private repositories, with the specified permission" do
      installation = make_integration_installation(target: @org, permissions: { "issues" => :write })
      assert installation.installed_on_all_repositories?(min_action: :write)
    end

    test "returns true if the installation is on all private repositories, with the specified resource" do
      installation = make_integration_installation(target: @org, permissions: { "issues" => :write })
      assert installation.installed_on_all_repositories?(resource: "issues")
    end

    test "returns false if the installation is not on all private repositories, with the specified permission" do
      installation = make_integration_installation(target: @org, permissions: { "issues" => :read })
      refute installation.installed_on_all_repositories?(min_action: :write)
    end

    test "returns false if the installation is not on all private repositories, with the specified resource" do
      installation = make_integration_installation(target: @org, permissions: { "issues" => :write })
      refute installation.installed_on_all_repositories?(resource: "statuses")
    end
  end

  context "#rate_limit" do
    test "defaults to the GitHub API default" do
      assert_equal GitHub.api_default_rate_limit, @installation.rate_limit
    end

    test "can have a custom, permanent rate limit" do
      @installation.update(rate_limit: 20000)
      assert_equal 20000, @installation.rate_limit
    end

    test "uses the permanent rate limit even if it's lower than the default" do
      new_limit = GitHub.api_default_rate_limit - 1
      @installation.update(rate_limit: new_limit)

      assert_equal new_limit, @installation.rate_limit
    end

    test "returns a the temporary_rate_limit if one is set" do
      @installation.update(rate_limit: 20000, dynamic_rate_limit: 20020)
      @installation.set_temporary_rate_limit(30000)
      assert_equal 30000, @installation.rate_limit
    end

    test "returns the override limit if one is set, and there is no temporary limit" do
      @installation.update(
        temporary_rate_limit_expires_at: 1.day.ago,
        dynamic_rate_limit: 20020,
        rate_limit: 40000)

      assert_equal 40000, @installation.rate_limit
    end

    test "returns the dynamic rate limit if one is set, and there is no override or temporary limit" do
      @installation.update(
        temporary_rate_limit_expires_at: 1.day.ago,
        dynamic_rate_limit: 20000,
        rate_limit: nil)

      assert_equal 20000, @installation.rate_limit
    end

    test "returns the default limit if the dynamic rate limit is lower" do
      @installation.update(dynamic_rate_limit: 100)
      assert_equal GitHub.api_default_rate_limit, @installation.rate_limit
    end
  end

  context "#temporary_rate_limit" do
    test "is nil when no temporary rate limit is set" do
      assert_nil @installation.temporary_rate_limit
    end

    test "returns the temporary rate limit if set and active" do
      @installation.set_temporary_rate_limit(30000)
      assert_equal 30000, @installation.temporary_rate_limit
    end

    test "returns nil if a temporary rate limit has expired" do
      @installation.update(temporary_rate_limit: 30000, temporary_rate_limit_expires_at: 1.second.ago)
      assert_nil @installation.temporary_rate_limit
    end
  end

  context "#set_temporary_rate_limit" do
    test "updates an installation's temporary rate limit" do
      assert_equal GitHub.api_default_rate_limit, @installation.rate_limit

      Timecop.freeze(Time.zone.parse("August 1 2018 10:00 AM")) do
        @installation.set_temporary_rate_limit(20000)

        assert_equal 20000, @installation.rate_limit
        assert_equal 20000, @installation.temporary_rate_limit
        assert_same_time 3.days.from_now, @installation.temporary_rate_limit_expires_at
      end
    end

    test "allows a custom duration" do
      Timecop.freeze do
        @installation.set_temporary_rate_limit(20000, 1.day)

        assert_equal 20000, @installation.rate_limit
        assert_equal 20000, @installation.temporary_rate_limit
        assert_same_time 1.day.from_now, @installation.temporary_rate_limit_expires_at
      end
    end
  end

  context "#using_temporary_rate_limit?" do
    test "returns true if a temporary rate limit has been set" do
      @installation.set_temporary_rate_limit(20000, 1.day)
      assert @installation.using_temporary_rate_limit?
    end

    test "returns false if a temporary rate limit has not been set" do
      refute @installation.using_temporary_rate_limit?
    end
  end

  context "instrumentation" do
    test "deletion" do
      GitHub.context.push(actor_id: @admin.id)

      events = subscribe "integration_installation.destroy"

      expected_payload = {}.tap do |payload|
        payload[:installation_id]       = @installation.id
        payload[:application_client_id] = @integration.key
        payload[:integration]           = @integration.name
        payload[:app]                   = @integration.name
        payload[:integration_id]        = @integration.id
        payload[:app_id]                = @integration.id
        payload[:name]                  = @integration.name
        payload[:slug]                  = @integration.slug
        payload[:org]                   = @org.display_login
        payload[:org_id]                = @org.id
        payload[:repository_selection]  = "selected"
      end

      @installation.uninstall

      assert event = events.pop, "expected an instrument deletion event"

      assert_equal "integration_installation.destroy", event.name
      assert_equal expected_payload, event.payload
    end

    test "can instrument if the target is missing" do
      GitHub.context.push(actor_id: @admin.id)

      events = subscribe "integration_installation.destroy"

      expected_payload = {}.tap do |payload|
        payload[:installation_id]       = @installation.id
        payload[:application_client_id] = @integration.key
        payload[:integration]           = @integration.name
        payload[:app]                   = @integration.name
        payload[:integration_id]        = @integration.id
        payload[:app_id]                = @integration.id
        payload[:name]                  = @integration.name
        payload[:slug]                  = @integration.slug
        payload[:repository_selection]  = "selected"
      end

      @org.delete
      @installation.reload

      @installation.uninstall

      assert event = events.pop, "expected an instrument deletion event"

      assert_equal "integration_installation.destroy", event.name
      assert_equal expected_payload, event.payload
    end

    test "uninstall with a given actor" do
      events = subscribe "integration_installation.destroy"

      expected_payload = {}.tap do |payload|
        payload[:installation_id]       = @installation.id
        payload[:application_client_id] = @integration.key
        payload[:integration]           = @integration.name
        payload[:app]                   = @integration.name
        payload[:integration_id]        = @integration.id
        payload[:app_id]                = @integration.id
        payload[:name]                  = @integration.name
        payload[:slug]                  = @integration.slug
        payload[:org]                   = @org.display_login
        payload[:org_id]                = @org.id
        payload[:repository_selection]  = "selected"
        payload[:actor_id]              = @admin.id
        payload[:actor]                 = @admin.display_login
      end

      @installation.uninstall(actor: @admin)

      assert event = events.pop, "expected an instrument deletion event"

      assert_equal "integration_installation.destroy", event.name
      assert_equal expected_payload, event.payload
    end

    test "uninstall with a staff actor", skip_enterprise: true do
      events = subscribe "integration_installation.destroy"
      staff_admin_user = create(:staff_admin_user)
      User.stubs(:staff_user).returns(staff_admin_user)

      expected_payload = {}.tap do |payload|
        payload[:installation_id]       = @installation.id
        payload[:application_client_id] = @integration.key
        payload[:integration]           = @integration.name
        payload[:app]                   = @integration.name
        payload[:integration_id]        = @integration.id
        payload[:app_id]                = @integration.id
        payload[:name]                  = @integration.name
        payload[:slug]                  = @integration.slug
        payload[:org]                   = @org.display_login
        payload[:org_id]                = @org.id
        payload[:repository_selection]  = "selected"
        payload[:staff_actor]           = @admin.display_login
        payload[:staff_actor_id]        = @admin.id
        payload[:actor_id]              = User.staff_user.id
        payload[:actor]                 = User.staff_user.display_login
      end

      @installation.uninstall(actor: @admin, staff_actor: true)

      assert event = events.pop, "expected an instrument deletion event"

      assert_equal "integration_installation.destroy", event.name
      assert_same_hash expected_payload, event.payload
    end

    test "skips default instrumentation for Actions installation" do
      events = subscribe "integration_installation.create"

      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner
      integration = create(:launch_integration)

      installation = make_integration_installation(integration: integration, repository: create(:repository, :minimal))

      assert_equal 0, events.size
    end

    test "instruments enabling Actions when installing Actions app on a repository" do
      installation_events = subscribe "integration_installation.create"
      enable_events = subscribe "repo.actions_enabled"

      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner
      integration = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(integration)
      org = create(:organization, admins: [@admin])
      repo = create(:repository, :minimal, owner: org)

      installation = make_integration_installation(integration: integration, repository: repo)

      assert_equal 0, installation_events.size
      assert_equal 1, enable_events.size

      expected_payload = {
        installation_id: installation.id,
        application_client_id: integration.key,
        name: integration.name,
        slug: integration.slug,
        repository_selection: installation.repository_selection,
        integration: integration.name,
        integration_id: integration.id,
        app: integration.name,
        app_id: integration.id,
        org: org.display_login,
        org_id: org.id,
        actor: @admin.display_login,
        actor_id: @admin.id,
        repo: repo.name_with_display_owner,
        repo_id: repo.id,
        public_repo: repo.public?,
      }

      event = enable_events.pop
      assert_same_hash expected_payload, event.payload
    end

    test "instruments enabling elevated read access for Codespaces" do
      installation_events = subscribe "integration_installation.create"
      granted_events = subscribe "repo.codespaces_trusted_repo_access_granted"

      make_trusted_oauth_apps_owner
      integration = create(:codespaces_integration)

      org  = create(:organization, admin: @admin)
      repo = create(:repository, :minimal, owner: org)

      make_integration_installation(integration: integration, repository: repo)

      assert_equal 0, installation_events.size
      assert_equal 1, granted_events.size

      expected_payload = {
        actor: @admin.display_login,
        actor_id: @admin.id,
        repo: repo.name_with_display_owner,
        repo_id: repo.id,
        public_repo: repo.public?,
        org: org.display_login,
        org_id: org.id,
      }

      event = granted_events.pop
      assert_same_hash expected_payload, event.payload
    end

    test "does not instrument enabling Actions when installing Actions app on all repositories" do
      installation_events = subscribe "integration_installation.create"
      enable_events = subscribe "repo.actions_enabled"

      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner
      integration = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(integration)

      make_integration_installation(integration: integration, target: @org)

      assert_equal 0, installation_events.size
      assert_equal 0, enable_events.size
    end

    test "instruments enabling elevated read access on all repositories for Codespaces" do
      installation_events = subscribe "integration_installation.create"
      granted_events = subscribe "#{@org.event_prefix}.codespaces_trusted_repo_access_granted"

      make_trusted_oauth_apps_owner
      integration = create(:codespaces_integration)

      make_integration_installation(integration: integration, target: @org)

      assert_equal 0, installation_events.size
      assert_equal 1, granted_events.size

      expected_payload = {
        actor: @admin.display_login,
        actor_id: @admin.id,
        org: @org.display_login,
        org_id: @org.id,
      }

      event = granted_events.pop
      assert_same_hash expected_payload, event.payload
    end

    test "uses custom instrumentation when destroying a codespaces installation" do
      make_trusted_oauth_apps_owner
      integration = create(:codespaces_integration)

      installation = make_integration_installation(integration: integration, target: @org)

      installation_events = subscribe "integration_installation.destroy"
      revoked_events = subscribe "#{@org.event_prefix}.codespaces_trusted_repo_access_revoked"

      expected_payload = {
        org: @org.display_login,
        org_id: @org.id,
      }

      installation.uninstall

      assert_equal 0, installation_events.count
      assert_equal 1, revoked_events.count

      event = revoked_events.pop
      assert_same_hash expected_payload, event.payload
    end

    context "suspension" do
      test "by an integrator" do
        events = subscribe "integration_installation.suspend"

        expected_payload = {}.tap do |payload|
          payload[:installation_id]       = @installation.id
          payload[:application_client_id] = @integration.key
          payload[:integration]           = @integration.name
          payload[:app]                   = @integration.name
          payload[:integration_id]        = @integration.id
          payload[:app_id]                = @integration.id
          payload[:name]                  = @integration.name
          payload[:slug]                  = @integration.slug
          payload[:org]                   = @org.display_login
          payload[:org_id]                = @org.id
          payload[:repository_selection]  = "selected"
          payload[:actor]                 = @installation.bot.display_login
          payload[:actor_id]              = @installation.bot.id
        end

        @installation.suspend!; @installation.reload

        assert event = events.pop, "expected an instrument suspend event"

        assert_equal "integration_installation.suspend", event.name
        assert_same_hash expected_payload, event.payload
      end

      test "by a user" do
        events = subscribe "integration_installation.suspend"

        expected_payload = {}.tap do |payload|
          payload[:installation_id]       = @installation.id
          payload[:application_client_id] = @integration.key
          payload[:integration]           = @integration.name
          payload[:app]                   = @integration.name
          payload[:integration_id]        = @integration.id
          payload[:app_id]                = @integration.id
          payload[:name]                  = @integration.name
          payload[:slug]                  = @integration.slug
          payload[:org]                   = @org.display_login
          payload[:org_id]                = @org.id
          payload[:repository_selection]  = "selected"
          payload[:actor]                 = @admin.display_login
          payload[:actor_id]              = @admin.id
        end

        @installation.suspend!(user: @admin); @installation.reload

        assert event = events.pop, "expected an instrument suspend event"

        assert_equal "integration_installation.suspend", event.name
        assert_same_hash expected_payload, event.payload
      end

      context "as a staff actor" do
        test "sets the github-staff user as the actor", skip_enterprise: true do
          events = subscribe "integration_installation.suspend"

          expected_payload = {}.tap do |payload|
            payload[:installation_id]       = @installation.id
            payload[:application_client_id] = @integration.key
            payload[:integration]           = @integration.name
            payload[:app]                   = @integration.name
            payload[:integration_id]        = @integration.id
            payload[:app_id]                = @integration.id
            payload[:name]                  = @integration.name
            payload[:slug]                  = @integration.slug
            payload[:org]                   = @org.display_login
            payload[:org_id]                = @org.id
            payload[:repository_selection]  = "selected"
            payload[:actor]                 = User.staff_user.display_login
            payload[:actor_id]              = User.staff_user.id
            payload[:staff_actor]           = @staff.display_login
            payload[:staff_actor_id]        = @staff.id
          end

          @installation.suspend!(user: @staff, staff_actor: true); @installation.reload
          assert_equal User.staff_user, @installation.user_suspended_by

          assert event = events.pop, "expected an instrument suspend event"

          assert_equal "integration_installation.suspend", event.name
          assert_same_hash expected_payload, event.payload
        end

        test "does not mask the actor", enterprise_only: true do
          events = subscribe "integration_installation.suspend"

          expected_payload = {}.tap do |payload|
            payload[:installation_id]       = @installation.id
            payload[:application_client_id] = @integration.key
            payload[:integration]           = @integration.name
            payload[:app]                   = @integration.name
            payload[:integration_id]        = @integration.id
            payload[:app_id]                = @integration.id
            payload[:name]                  = @integration.name
            payload[:slug]                  = @integration.slug
            payload[:org]                   = @org.display_login
            payload[:org_id]                = @org.id
            payload[:repository_selection]  = "selected"
            payload[:actor]                 = @staff.display_login
            payload[:actor_id]              = @staff.id
          end

          @installation.suspend!(user: @staff, staff_actor: true); @installation.reload
          assert_equal @staff, @installation.user_suspended_by

          assert event = events.pop, "expected an instrument suspend event"

          assert_equal "integration_installation.suspend", event.name
          assert_same_hash expected_payload, event.payload
        end
      end
    end

    context "unsuspension" do
      test "by an integrator" do
        events = subscribe "integration_installation.unsuspend"

        @installation.suspend!; @installation.reload

        expected_payload = {}.tap do |payload|
          payload[:installation_id]       = @installation.id
          payload[:application_client_id] = @integration.key
          payload[:integration]           = @integration.name
          payload[:app]                   = @integration.name
          payload[:integration_id]        = @integration.id
          payload[:app_id]                = @integration.id
          payload[:name]                  = @integration.name
          payload[:slug]                  = @integration.slug
          payload[:org]                   = @org.display_login
          payload[:org_id]                = @org.id
          payload[:repository_selection]  = "selected"
          payload[:actor]                 = @installation.bot.display_login
          payload[:actor_id]              = @installation.bot.id
        end

        @installation.unsuspend!

        assert event = events.pop, "expected an instrument unsuspend event"

        assert_equal "integration_installation.unsuspend", event.name
        assert_same_hash expected_payload, event.payload
      end

      test "by a user" do
        events = subscribe "integration_installation.unsuspend"

        @installation.suspend!(user: @admin); @installation.reload

        expected_payload = {}.tap do |payload|
          payload[:installation_id]       = @installation.id
          payload[:application_client_id] = @integration.key
          payload[:integration]           = @integration.name
          payload[:app]                   = @integration.name
          payload[:integration_id]        = @integration.id
          payload[:app_id]                = @integration.id
          payload[:name]                  = @integration.name
          payload[:slug]                  = @integration.slug
          payload[:org]                   = @org.display_login
          payload[:org_id]                = @org.id
          payload[:repository_selection]  = "selected"
          payload[:actor]                 = @admin.display_login
          payload[:actor_id]              = @admin.id
        end

        @installation.unsuspend!(user: @admin)

        assert event = events.pop, "expected an instrument unsuspend event"

        assert_equal "integration_installation.unsuspend", event.name
        assert_same_hash expected_payload, event.payload
      end

      context "as a staff actor" do
        test "sets the github-staff user as the actor", skip_enterprise: true do
          events = subscribe "integration_installation.unsuspend"

          @installation.suspend!(user: @admin); @installation.reload

          expected_payload = {}.tap do |payload|
            payload[:installation_id]       = @installation.id
            payload[:application_client_id] = @integration.key
            payload[:integration]           = @integration.name
            payload[:app]                   = @integration.name
            payload[:integration_id]        = @integration.id
            payload[:app_id]                = @integration.id
            payload[:name]                  = @integration.name
            payload[:slug]                  = @integration.slug
            payload[:org]                   = @org.display_login
            payload[:org_id]                = @org.id
            payload[:repository_selection]  = "selected"
            payload[:actor]                 = User.staff_user.display_login
            payload[:actor_id]              = User.staff_user.id
            payload[:staff_actor]           = @staff.display_login
            payload[:staff_actor_id]        = @staff.id
          end

          @installation.unsuspend!(user: @staff, staff_actor: true)

          assert event = events.pop, "expected an instrument unsuspend event"

          assert_equal "integration_installation.unsuspend", event.name
          assert_same_hash expected_payload, event.payload
        end

        test "does not mask the actor", enterprise_only: true do
          events = subscribe "integration_installation.unsuspend"

          @installation.suspend!(user: @admin); @installation.reload

          expected_payload = {}.tap do |payload|
            payload[:installation_id]       = @installation.id
            payload[:application_client_id] = @integration.key
            payload[:integration]           = @integration.name
            payload[:app]                   = @integration.name
            payload[:integration_id]        = @integration.id
            payload[:app_id]                = @integration.id
            payload[:name]                  = @integration.name
            payload[:slug]                  = @integration.slug
            payload[:org]                   = @org.display_login
            payload[:org_id]                = @org.id
            payload[:repository_selection]  = "selected"
            payload[:actor]                 = @staff.display_login
            payload[:actor_id]              = @staff.id
          end

          @installation.unsuspend!(user: @staff, staff_actor: true)

          assert event = events.pop, "expected an instrument unsuspend event"

          assert_equal "integration_installation.unsuspend", event.name
          assert_same_hash expected_payload, event.payload
        end
      end
    end

    context "adding repositories" do
      test "invalidates user associated repositories cache" do
        enable_feature_flag(:installation_user_associated_repo_ids_cache, @integration)
        events = subscribe "integration_installation.repositories_added"

        user = @repo.owner.admins.first
        user.associated_installation_repository_ids(@installation)

        IntegrationInstallation::UserAssociatedRepositories.expects(:invalidate_cache).with(installation: @installation).once

        @installation.instrument_repositories_added([@repo.id], actor: @repo.owner, repository_selection: "selected", async: false)

        assert event = events.pop, "expected an instrument repositories added event"
        assert_equal "integration_installation.repositories_added", event.name
      end

      test "masks the actor if performed automatically" do
        events = subscribe "integration_installation.repositories_added"

        user = @repo.owner.admins.first

        @installation.instrument_repositories_added([@repo.id], actor: user, repository_selection: "selected", async: false, performed_automatically: true)

        expected_payload = {
          app:                      @integration.name,
          application_client_id:    @integration.key,
          org:                      @repo.owner.display_login,
          name:                     @integration.name,
          slug:                     @integration.slug,
          actor:                    @integration.bot.display_login,
          app_id:                   @integration.id,
          org_id:                   @repo.owner.id,
          actor_id:                 @integration.bot.id,
          integration:              @integration.name,
          requester_id:             nil,
          integration_id:           @integration.id,
          installation_id:          @installation.id,
          repositories_added:       [@repo.id],
          added_automatically:      true,
          repository_selection:     "selected",
          repositories_added_names: [@repo.name_with_display_owner],
        }

        assert event = events.pop, "expected an instrument repositories added event"
        assert_equal "integration_installation.repositories_added", event.name
        assert_same_hash expected_payload, event.payload
      end

      test "enqueues a background job if async" do
        user = @repo.owner.admins.first

        IntegrationInstallation.stub_const(:MAX_REPOS_TO_INSTRUMENT, 1) do
          assert_enqueued_with(job: IntegrationInstallationInstrumentationJob, args: [
            :repositories_added, @installation.id, user.id, [@repo.id], "selected", { requester_id: nil }
          ]) do
            @installation.instrument_repositories_added([@repo.id], actor: user, repository_selection: "selected")
          end
        end
      end
    end

    context "removing repositories" do
      test "invalidates user associated repositories cache" do
        enable_feature_flag(:installation_user_associated_repo_ids_cache, @integration)
        events = subscribe "integration_installation.repositories_removed"

        user = @repo.owner.admins.first
        user.associated_installation_repository_ids(@installation)

        IntegrationInstallation::UserAssociatedRepositories.expects(:invalidate_cache).with(installation: @installation).once

        @installation.instrument_repositories_removed([@repo.id], actor: @repo.owner, async: false)

        assert event = events.pop, "expected an instrument repositories removed event"
        assert_equal "integration_installation.repositories_removed", event.name
      end

      test "enqueues a background job if async" do
        user = @repo.owner

        IntegrationInstallation.stub_const(:MAX_REPOS_TO_INSTRUMENT, 1) do
          assert_enqueued_with(job: IntegrationInstallationInstrumentationJob, args: [
            :repositories_removed, @installation.id, user.id, [@repo.id], "selected"
          ]) do
            @installation.instrument_repositories_removed([@repo.id], actor: user.owner)
          end
        end
      end
    end
  end

  context "#permissions" do
    test "returns a Hash of resource names and permission level the installation has" do
      installation = make_integration_installation(target: @org,
        permissions: {
          "issues" => :read,
          "statuses" => :write,
          "metadata" => :read,
        })

      assert_same_elements %w(statuses issues metadata), installation.permissions.keys
      assert_same_elements [:write, :read, :read], installation.permissions.values
    end
  end

  context "#update_version" do
    test "returns a successful result with an updated installation number" do
      installation = make_integration_installation(target: @org)
      version = installation.integration.versions.create(default_permissions: { "contents" => :read })

      result = installation.update_version(editor: @admin, version: version, entry_point: :test_case)

      assert_predicate result, :success?
      assert installation = result.installation

      assert_equal version.id, installation.integration_version_id
      assert_equal version.number, installation.integration_version_number
    end
  end

  context "#manageable_by?" do
    test "returns true for a user who can admin the target org" do
      installation = make_integration_installation(target: @org)
      org_admin = @org.admins.first

      manageable, _ = installation.manageable_by?(org_admin)
      assert manageable
    end

    test "returns true for the same user the installation is on", skip_with_all_emus: true do
      user = create(:user)
      installation = make_integration_installation(target: user)

      manageable, _ = installation.manageable_by?(user)
      assert manageable
    end

    test "returns true for a user where they can admin all of the specified repositories but cannot admin the org target" do
      repo_admin = create(:user)
      org = create(:organization)
      org.add_member(repo_admin)
      repo_a = create(:repository, :minimal, owner: org)
      repo_b = create(:repository, :minimal, owner: org)
      repo_a.add_member(repo_admin, action: :admin)
      repo_b.add_member(repo_admin, action: :admin)

      installation = make_integration_installation(repositories: [repo_a, repo_b], permissions: { "metadata" => :read })

      manageable, _ = installation.manageable_by?(repo_admin)
      assert manageable
    end

    test "returns false for a user where they can admin all of the specified repositories but cannot admin the user target", skip_with_all_emus: true do
      repo_admin = create(:user)
      other_user = create(:user)
      repo_a = create(:repository, :minimal, owner: other_user)
      repo_b = create(:repository, :minimal, owner: other_user)
      repo_a.add_member(repo_admin, action: :admin)
      repo_b.add_member(repo_admin, action: :admin)

      installation = make_integration_installation(repositories: [repo_a, repo_b])

      manageable, error_message = installation.manageable_by?(repo_admin)

      refute manageable
      assert_equal "You do not have permission to modify this app on #{other_user.display_login}.", error_message
    end

    test "returns false for a user who cannot admin the target org or repositories" do
      user = create(:user)
      repo = create(:repository, :minimal, owner: @org)
      installation = make_integration_installation(repository: repo)

      manageable, error_message = installation.manageable_by?(user)

      refute manageable
      assert_equal "You do not have permission to modify this App on all repositories belonging to #{@org.display_login}. Please contact an Organization Owner.", error_message
    end

    test "returns false if user is nil", skip_with_all_emus: true do
      repo  = create(:repository, :minimal)
      owner = repo.owner
      installation = make_integration_installation(repository: repo)

      manageable, error_message = installation.manageable_by?(nil)

      refute manageable
      assert_equal "You do not have permission to modify this app on #{owner.display_login}.", error_message
    end
  end

  context "#recalculate_rate_limit" do
    test "sets the rate_limit to the calculated value" do
      expected = 10_000

      refute_equal expected, @org_installation.rate_limit
      assert_operator expected, :>, GitHub.api_default_rate_limit

      IntegrationInstallation::RateLimitCalculator.stubs(:calculate).returns(expected)

      @org_installation.recalculate_rate_limit
      assert_equal expected, @org_installation.rate_limit
    end
  end

  test "#using_basic_auth? return false" do
    refute_predicate @org_installation, :using_basic_auth?
  end

  test "#using_personal_access_token? return false" do
    refute_predicate @org_installation, :using_personal_access_token?
  end

  test "#installed_automatically?" do
    # false if installation created without trigger (manually)
    refute_predicate @installation, :installed_automatically?

    trigger = create(:integration_install_trigger,
                     integration: @another_integration,
                     install_type: :file_added)
    other_installation = make_integration_installation(integration: @another_integration, repository: @repo)
    other_installation.integration_install_trigger_id = trigger.id

    assert_predicate other_installation, :installed_automatically?
  end

  test "does not allow duplicates for integration_id, target_id and target_type" do
    target = create(:organization)
    integration = create(:integration, default_permissions: { "metadata" => :read })

    installation = make_integration_installation(integration: integration, target: target)
    assert_predicate installation, :valid?

    installation_dup = IntegrationInstallation.create(
      integration: integration,
      target: target,
      integration_version_id: installation.integration_version_id,
      integration_version_number: installation.integration_version_number,
    )

    refute_predicate installation_dup, :valid?
    assert_equal ["GitHub App has already been installed"], installation_dup.errors.full_messages
  end

  context "Launch tasks" do
    test "#launch_github_app?" do
      integration = create(:integration, default_permissions: { "metadata" => :read })
      GitHub.stubs(:launch_github_app).returns(integration)

      installation = make_integration_installation(integration: integration, repository: create(:repository, :minimal))

      assert_predicate installation, :launch_github_app?
    end

    test "#launch_lab_github_app?" do
      integration = create(:integration, default_permissions: { "metadata" => :read })
      GitHub.stubs(:launch_lab_github_app).returns(integration)

      installation = make_integration_installation(integration: integration, repository: create(:repository, :minimal))

      assert_predicate installation, :launch_lab_github_app?
    end

    test "uses custom instrumentation when installing Actions app for a user", skip_with_all_emus: true do
      make_trusted_oauth_apps_owner
      integration = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(integration)

      installation = make_integration_installation(integration: integration, repository: @user_repo)

      original_events = subscribe "integration_installation.repositories_added"
      custom_events = subscribe "repo.actions_enabled"

      installation.instrument_repositories_added([@user_repo.id], actor: @admin, repository_selection: "selected", async: false)

      assert_equal 0, original_events.size

      expected_payload = {
        actor: @admin.display_login,
        actor_id: @admin.id,
        repo: @user_repo.name_with_display_owner,
        repo_id: @user_repo.id,
        public_repo: @user_repo.public?,
      }.merge(@user_repo.owner.event_context)

      assert event = custom_events.pop
      assert_same_hash expected_payload, event.payload
    end

    test "masks the actor when adding repositories to actions automatically", skip_with_all_emus: true do
      make_trusted_oauth_apps_owner
      integration = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(integration)

      installation = make_integration_installation(integration: integration, repository: @user_repo)

      original_events = subscribe "integration_installation.repositories_added"
      custom_events = subscribe "repo.actions_enabled"

      installation.instrument_repositories_added([@user_repo.id],
        actor: @admin, repository_selection: "selected", async: false, performed_automatically: true,
      )

      assert_equal 0, original_events.size

      expected_payload = {
        actor: integration.bot.display_login,
        actor_id: integration.bot.id,
        repo: @user_repo.name_with_display_owner,
        repo_id: @user_repo.id,
        public_repo: @user_repo.public?,
      }.merge(@user_repo.owner.event_context)

      assert event = custom_events.pop
      assert_same_hash expected_payload, event.payload
    end

    test "uses custom instrumentation when installing Actions app for an organization" do
      make_trusted_oauth_apps_owner
      integration = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(integration)

      installation = make_integration_installation(integration: integration, repository: @repo)

      original_events = subscribe "integration_installation.repositories_added"
      custom_events = subscribe "repo.actions_enabled"

      installation.instrument_repositories_added([@repo.id], actor: @admin, repository_selection: "selected", async: false)

      assert_equal 0, original_events.size

      expected_payload = {
        actor: @admin.display_login,
        actor_id: @admin.id,
        repo: @repo.name_with_display_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        org: @repo.owner.display_login,
        org_id: @repo.owner.id,
      }

      assert event = custom_events.pop
      assert_same_hash expected_payload, event.payload
    end
  end

  context "Codespaces" do
    test "uses custom instrumentation when adding repositories to an existing Codespaces installation for a user", skip_with_all_emus: true do
      make_trusted_oauth_apps_owner
      integration = create(:codespaces_integration)

      repo2 = create(:repository, :minimal, owner: @user_repo.owner)
      installation = make_integration_installation(integration: integration, repository: @user_repo)

      original_events = subscribe "integration_installation.repositories_added"
      custom_events = subscribe "repo.codespaces_trusted_repo_access_granted"

      installation.edit(repositories: [@user_repo, repo2], editor: @admin, entry_point: :test_case)

      assert_equal 0, original_events.size

      expected_payload = {
        actor: @admin.display_login,
        actor_id: @admin.id,
        repo: repo2.name_with_display_owner,
        repo_id: repo2.id,
        public_repo: repo2.public?,
        user: repo2.owner.display_login,
        user_id: repo2.owner.id,
      }

      assert event = custom_events.pop
      assert_same_hash expected_payload, event.payload
    end

    test "uses custom instrumentation when adding repositories to an existing installation for an organization" do
      make_trusted_oauth_apps_owner
      integration = create(:codespaces_integration)

      repo2 = create(:repository, :minimal, owner: @repo.owner)
      installation = make_integration_installation(integration: integration, repository: @repo)

      original_events = subscribe "integration_installation.repositories_added"
      custom_events = subscribe "repo.codespaces_trusted_repo_access_granted"

      installation.edit(repositories: [@repo, repo2], editor: @admin, entry_point: :test_case)

      assert_equal 0, original_events.size

      expected_payload = {
        actor: @admin.display_login,
        actor_id: @admin.id,
        repo: repo2.name_with_display_owner,
        repo_id: repo2.id,
        public_repo: repo2.public?,
        org: repo2.owner.display_login,
        org_id: repo2.owner.id,
      }

      assert event = custom_events.pop
      assert_same_hash expected_payload, event.payload
    end
  end

  context "#repository_installation_required?" do
    context "Business target" do
      test "returns false when there are no permissions" do
        target = create(:business)
        installation = make_integration_installation(target: target, permissions: { Business::Resources.subject_types.first => :read })

        refute_predicate installation, :repository_installation_required?
      end

      test "returns false when there are repository permissions" do
        target = create(:business)
        installation = make_integration_installation(target: target, permissions: { "metadata" => :read, Business::Resources.subject_types.first => :read })

        refute_predicate installation, :repository_installation_required?
      end
    end

    context "Organization target" do
      test "returns false when there are no permissions" do
        installation = make_integration_installation(target: @org)
        refute_predicate installation, :repository_installation_required?
      end

      test "returns true when there are repository permissions" do
        installation = make_integration_installation(target: @org, permissions: { "metadata" => :read })
        assert_predicate installation, :repository_installation_required?
      end
    end

    context "User target", skip_with_all_emus: true do
      test "returns false when there are no permissions" do
        installation = make_integration_installation(target: @admin)
        refute_predicate installation, :repository_installation_required?
      end

      test "returns true when there are repository permissions" do
        installation = make_integration_installation(target: @admin, permissions: { "metadata" => :read })
        assert_predicate installation, :repository_installation_required?
      end
    end
  end

  context "#target_for_conditional_access" do
    test "it returns a user", skip_with_all_emus: true do
      installation = make_integration_installation(target: @admin)
      assert_equal installation.target_for_conditional_access, @admin
    end

    test "it returns an org" do
      installation = make_integration_installation(target: @org)
      assert_equal installation.target_for_conditional_access, @org
    end

    test "it returns a business" do
      business = create(:business)
      installation = make_integration_installation(target: business, permissions: { Business::Resources.subject_types.first => :read })
      assert_equal installation.target_for_conditional_access, business
    end
  end

  context "#repository_permissions_only?" do
    test "returns false when there are no permissions" do
      installation = make_integration_installation(target: @org)
      assert_predicate installation.permissions, :empty?

      refute_predicate installation, :repository_permissions_only?
    end

    test "returns false when there are organization permissions" do
      installation = make_integration_installation(target: @org, permissions: { "members" => :read })
      refute_predicate installation, :repository_permissions_only?
    end

    test "returns false when there are organization and repository permissions" do
      installation = make_integration_installation(target: @org, permissions: { "members" => :read, "metadata" => :read })
      refute_predicate installation, :repository_permissions_only?
    end

    test "returns true when there are repository permissions" do
      installation = make_integration_installation(target: @org, permissions: { "metadata" => :read })
      assert_predicate installation, :repository_permissions_only?
    end
  end

  test "#clear_abilities_per_destroyed_record?" do
    refute_predicate @installation, :clear_abilities_per_destroyed_record?
  end

  context "suspension" do
    context "suspended_at" do
      test "returns nil if the installation is not suspended" do
        refute_predicate @installation, :suspended?
        assert_nil @installation.suspended_at
      end

      test "returns the bot if the integrator suspended the installation" do
        @installation.suspend!; @installation.reload
        assert_equal @installation.integrator_suspended_at, @installation.suspended_at
      end

      test "returns the user if a target owner suspended the installation" do
        @installation.suspend!(user: @admin); @installation.reload
        assert_equal @installation.user_suspended_at, @installation.suspended_at
      end

      test "returns the latest suspended_at" do
        Timecop.freeze 2.days.ago do
          @installation.suspend!; @installation.reload
        end

        @installation.suspend!(user: @admin); @installation.reload

        assert_predicate @installation, :integrator_suspended?
        assert_predicate @installation, :user_suspended?

        assert @installation.integrator_suspended_at < @installation.user_suspended_at
        assert_equal @installation.user_suspended_at, @installation.suspended_at
      end
    end

    context "suspended_by" do
      test "returns nil if the installation is not suspended" do
        refute_predicate @installation, :suspended?
        assert_nil @installation.suspended_by
      end

      test "returns the bot if the integrator suspended the installation" do
        @installation.suspend!; @installation.reload
        assert_equal @installation.bot, @installation.suspended_by
      end

      test "returns the user if a target owner suspended the installation" do
        @installation.suspend!(user: @admin); @installation.reload
        assert_equal @admin, @installation.suspended_by
      end

      test "returns the latest suspending actor" do
        Timecop.freeze 2.days.ago do
          @installation.suspend!; @installation.reload
        end

        @installation.suspend!(user: @admin); @installation.reload

        assert_predicate @installation, :integrator_suspended?
        assert_predicate @installation, :user_suspended?

        assert @installation.integrator_suspended_at < @installation.user_suspended_at
        assert_equal @admin, @installation.suspended_by
      end
    end

    context "#integrator_suspended?" do
      test "is only true when integrator_suspended and integrator_suspended_at are both set" do
        @installation.update(integrator_suspended: true); @installation.reload
        refute_predicate @installation, :integrator_suspended?

        @installation.update(integrator_suspended: false, integrator_suspended_at: Time.zone.now); @installation.reload
        refute_predicate @installation, :integrator_suspended?

        @installation.update(integrator_suspended: true, integrator_suspended_at: Time.zone.now); @installation.reload
        assert_predicate @installation, :integrator_suspended?
      end
    end

    context "#user_suspended?" do
      test "is only true when both user_suspended_by_id and user_suspended_at are set" do
        @installation.update(user_suspended_by: @admin); @installation.reload
        refute_predicate @installation, :user_suspended?

        @installation.update(user_suspended_by: nil, user_suspended_at: Time.zone.now); @installation.reload
        refute_predicate @installation, :user_suspended?

        @installation.update(user_suspended_by: @admin, user_suspended_at: Time.zone.now); @installation.reload
        assert_predicate @installation, :user_suspended?
      end
    end

    context "#suspended?" do
      test "is true if the installation is suspended by the integrator" do
        @installation.update(integrator_suspended: true, integrator_suspended_at: Time.zone.now); @installation.reload
        assert_predicate @installation, :suspended?
      end

      test "is true if the installation is suspended by a User" do
        @installation.update(user_suspended_by: @admin, user_suspended_at: Time.zone.now); @installation.reload
        assert_predicate @installation, :suspended?
      end

      test "is false if the integration is suspended" do
        @integration.suspend(actor: create(:staff_admin_user), reason: "testing")

        refute_predicate @installation, :suspended?
      end
    end

    context "#integration_suspended?" do
      test "is true if the integration is suspended" do
        @integration.suspend(actor: create(:staff_admin_user), reason: "testing")

        assert_predicate @installation, :integration_suspended?
      end

      test "is false if the integration is not suspended and the installation is" do
        @installation.update(user_suspended_by: @admin, user_suspended_at: Time.zone.now); @installation.reload
        assert_predicate @installation, :suspended?
        refute_predicate @integration, :suspended?

        refute_predicate @installation, :integration_suspended?
      end
    end

    context "#staff_suspended" do
      test "returns false we aren't guarding audit log staff actors", enterprise_only: true do
        staff_user = create(:user, login: GitHub.staff_user_login)
        @installation.suspend!(user: staff_user, staff_actor: true); @installation.reload

        refute_predicate @installation, :staff_suspended?
      end

      test "returns true if a guarded staff user suspends the installation", skip_enterprise: true, skip_with_all_emus: true do
        @installation.suspend!(user: User.staff_user, staff_actor: true); @installation.reload
        assert_predicate @installation, :staff_suspended?
      end

      # https://github.com/github/ecosystem-apps/issues/1760
      test "returns false if the associated user no longer exists" do
        suspender = create(:user)
        @org.add_admin(suspender)

        @installation.suspend!(user: suspender)
        @installation.reload

        suspender.delete
        assert_predicate suspender, :destroyed?

        refute_predicate @installation, :staff_suspended?
      end
    end
  end

  test "shouldn't enqueue DestroyAuthenticationTokensJob after destroy without tokens" do
    assert_enqueued_jobs 0, only: DestroyAuthenticationTokensJob do
      @installation.destroy
    end
  end

  test "should enqueue DestroyAuthenticationTokensJob after destroy" do
    assert_enqueued_with(job: DestroyAuthenticationTokensJob, args: [@installation.id, @installation.class.name]) do
      @installation.generate_token
      @installation.destroy
    end
  end

  test "new job destroys the authentication tokens" do
    @installation.generate_token
    @installation.generate_token
    token_records = ServerToServerTokens.domain.by_authenticatable_id(@installation.id)
    token_records = T.must(token_records)
    assert_equal 2, token_records.size

    perform_enqueued_jobs(only: [DestroyAuthenticationTokensJob]) do
      @installation.uninstall
    end

    token_records = ServerToServerTokens.domain.by_authenticatable_id(@installation.id)
    token_records = T.must(token_records)
    assert_equal 0, token_records.size
  end
end
