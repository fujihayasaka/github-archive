# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class IntegrationInstallationCreatorInstallingAnIntegrationTest < GitHub::TestCase
  include HydroTestHelpers
  include PermissionsHelper

  fixtures do
    make_trusted_oauth_apps_owner

    @integration = create(:integration, default_permissions: { "metadata" => :read })
    @admin = create(:user)
    @org   = create(:organization, login: "ACME", admin: @admin)
    @repo  = create(:private_repository, :minimal, owner: @org)
    @public_repo = create(:repository, :minimal, owner: @org)
  end

  context ".perform" do
    test "returns an installation for a valid installation" do
      options = {
        repositories: [@repo],
        installer: @admin,
        version: @integration.latest_version,
        entry_point: :test_case,
      }

      result = IntegrationInstallation::Creator.perform(@integration, @org, **options)
      assert result.installation
    end

    test "queues a job to calculate the rate limit" do
      options = {
        repositories: [@repo],
        installer: @admin,
        version: @integration.latest_version,
        entry_point: :test_case,
      }

      assert_enqueued_jobs 1, only: UpdateIntegrationInstallationRateLimitJob, queue: "update_integration_installation_rate_limit" do
        result = IntegrationInstallation::Creator.perform(@integration, @org, **options)
        assert_enqueued_with(job: UpdateIntegrationInstallationRateLimitJob, args: [result.installation.id], queue: "update_integration_installation_rate_limit")
      end
    end

    test "does not return an installation for an invalid installation" do
      result = IntegrationInstallation::Creator.perform(@integration,
        @org, repositories: [@repo], installer: @admin, version: create(:integration_version), entry_point: :test_case
      )

      assert_nil result.installation
    end

    test "returns a success when the installer can admin all the repos but cannot admin the target" do
      repo_admin = create(:user)
      @repo.add_member(repo_admin, action: :admin)

      options = {
        repositories: [@repo],
        installer: repo_admin,
        version: @integration.latest_version,
        entry_point: :test_case,
      }

      result = IntegrationInstallation::Creator.perform(@integration, @org, **options)
      assert_predicate result, :success?
    end

    test "returns a failure when the installer cannot admin all of the repos" do
      repo_admin = create(:user)
      @repo.add_member(repo_admin, action: :admin)
      org_repo_b = create(:private_repository, :minimal, owner: @org)

      options = {
        repositories: [@repo, org_repo_b],
        installer: repo_admin,
        version: @integration.latest_version,
        entry_point: :test_case,
      }

      result = IntegrationInstallation::Creator.perform(@integration, @org, **options)
      assert_predicate result, :failed?
      assert_equal "You do not have permission to install this app on these repositories belonging to ACME. Please contact an Organization Owner.", result.error
    end

    test "returns a failure when the installer cannot admin the account, and requests install on all" do
      repo_admin = create(:user)
      @repo.add_member(repo_admin, action: :admin)

      options = {
        repositories: [],
        installer: repo_admin,
        version: @integration.latest_version,
        entry_point: :test_case,
      }

      result = IntegrationInstallation::Creator.perform(@integration, @org, **options)
      assert_predicate result, :failed?
      assert_equal "You do not have permission to install apps with all repositories on ACME. Please contact an Organization Owner.", result.error
    end

    test "returns a failure if installing on a personal account that is not the installer's account, and the installer cannot admin the repos" do
      other_user = create(:user, login: "other-user")

      result = IntegrationInstallation::Creator.perform(@integration,
                                                        other_user,
                                                        installer: @admin,
                                                        repositories: [create(:repository, :minimal, owner: other_user)],
                                                        version: @integration.latest_version,
                                                        entry_point: :test_case,
                                                       )

      assert_predicate result, :failed?
      assert_equal "You do not have permission to install this app on other-user.", result.error
    end

    test "returns a false if installing on specified repos, but the installer is neither an org admin nor admin of all the repos" do
      member = create(:user)
      @org.add_member(member)

      result = IntegrationInstallation::Creator.perform(@integration,
                                                        @org,
                                                        installer: member,
                                                        repositories: [@repo],
                                                        version: @integration.latest_version,
                                                        entry_point: :test_case,
                                                       )

      assert_predicate result, :failed?
      assert_equal "You do not have permission to install this app on these repositories belonging to ACME. Please contact an Organization Owner.", result.error
    end

    test "returns a failure for a non org admin who has admin access to all of the repos, but there are org permissions" do
      integration = create(:integration, default_permissions: { "members" => :read })

      repo_admin = create(:user)
      @repo.add_member(repo_admin, action: :admin)

      options = {
        repositories: [@repo],
        installer: repo_admin,
        version: integration.latest_version,
        entry_point: :test_case,
      }

      result = IntegrationInstallation::Creator.perform(integration, @org, **options)
      assert_predicate result, :failed?
      assert_equal "You cannot install apps with organization permissions on ACME. Please contact an Organization Owner.", result.error
    end

    test "returns a failure if a repository isn't owned by the owner given" do
      other_org = create(:organization, admin: @admin)
      other_org_repo = create(:repository, :minimal, owner: other_org)

      result = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [other_org_repo],
        version: @integration.latest_version,
        installer: @admin,
        entry_point: :test_case,
      )

      assert_predicate result, :failed?
      assert_equal "Repositories must be owned by ACME. Please contact an Organization Owner.", result.error
    end

    test "fails gracefully on ActiveRecord::RecordInvalid" do
      options = {
        repositories: [@repo],
        installer: @admin,
        version: @integration.latest_version,
        entry_point: :test_case,
      }

      result = IntegrationInstallation::Creator.perform(@integration, @org, **options)
      assert result.installation

      result = IntegrationInstallation::Creator.perform(@integration, @org, **options)

      assert_predicate result, :failed?
      assert_equal "GitHub App has already been installed", result.error
    end

    test "fails gracefully on ActiveRecord::RecordNotUnique" do
      options = {
        repositories: [@repo],
        installer: @admin,
        version: @integration.latest_version,
        entry_point: :test_case,
      }

      IntegrationInstallation.any_instance.expects(:save!).raises(ActiveRecord::RecordNotUnique)
      result = IntegrationInstallation::Creator.perform(@integration, @org, **options)

      assert_predicate result, :failed?
      assert_equal "this app has already been installed", result.error
    end

    test "fails gracefully when events fail to be set" do
      version = @integration.versions.create(
        default_permissions: { "contents" => :read, "statuses" => :write },
        default_events: %w(status),
      )

      event = version.default_event_records.first
      event.update_column(:name, "foo")

      event.reload
      refute_predicate event, :valid?

      options = {
        repositories: [@repo],
        installer: @admin,
        version: version,
        entry_point: :test_case,
      }

      result = IntegrationInstallation::Creator.perform(@integration, @org, **options)
      assert_predicate result, :failed?

      error_message = "The following event is invalid: foo."
      assert_equal error_message, result.error
      refute result.installation
    end

    context "during repository transfers" do
      test "returns a failure if a selected repository is marked transferring during installation" do
        with_cache_enabled do
          other_org = create(:organization, admin: @admin)
          repos = [@public_repo]

          RepositoryOrchestration.transfer_type.create(repository: @public_repo).update(state: :running)

          result = IntegrationInstallation::Creator.perform(
            @integration,
            @org,
            repositories: repos,
            version: @integration.latest_version,
            installer: @admin,
            entry_point: :test_case,
          )

          assert_predicate result, :failed?
          refute_predicate result.installation, :present?
          assert_equal "Could not complete installation. Please verify repository selection and try again.", result.error
        end
      end

      test "returns an installation if Apps are explicitly being reinstalled on the repo during the transfer" do
        with_cache_enabled do
          other_org = create(:organization, admin: @admin)

          RepositoryOrchestration.transfer_type.create(repository: @public_repo).update(state: :running)
          @public_repo.update!(owner: other_org)

          # Install on the new repo owner
          result = IntegrationInstallation::Creator.perform(
            @integration,
            other_org,
            repositories: [@public_repo],
            version: @integration.latest_version,
            installer: other_org.admins.first,
            reinstalling_during_repository_transfer: true,
            entry_point: :test_case,
          )

          assert_predicate result, :success?
          assert_predicate result.installation, :present?
        end
      end
    end

    test "creates an IntegrationInstallation with the expected values set" do
      version = @integration.versions.create(
        default_permissions: { "contents" => :read, "statuses" => :write },
        default_events: %w(status),
      )

      result = assert_queries_matching(/INSERT IGNORE INTO permissions/, 1) do
        IntegrationInstallation::Creator.perform(@integration, @org, repositories: [@repo, @public_repo], version: version, installer: @admin, entry_point: :test_case)
      end

      assert_predicate result, :success?
      assert_able result.installation, :read, @repo.resources.contents
      assert_able result.installation, :write, @repo.resources.statuses
      assert_able result.installation, :read, @public_repo.resources.contents
      assert_able result.installation, :write, @public_repo.resources.statuses
      assert_same_elements ["status"], result.installation.events
    end

    test "creates a unique installation for each org that the integration is installed on" do
      org_a_admin = create(:user)
      org_b_admin = create(:user)
      org_a       = create(:organization, admin: org_a_admin)
      org_b       = create(:organization, admin: org_b_admin)
      repo_a      = create(:repository, :minimal, owner: org_a)
      repo_b      = create(:repository, :minimal, owner: org_b)

      installation_a =
        @integration.install_on(org_a, repositories: [repo_a], installer: org_a_admin, version: @integration.latest_version, entry_point: :test_case).installation
      installation_b =
        @integration.install_on(org_b, repositories: [repo_b], installer: org_b_admin, version: @integration.latest_version, entry_point: :test_case).installation

      refute_equal installation_a, installation_b
      assert_equal org_a, installation_a.target
      assert_equal org_b, installation_b.target
    end

    test "an installation can only be created once" do
      repo_a = create(:repository, :minimal, owner: @org)
      repo_b = create(:repository, :minimal, owner: @org)

      assert_difference "@integration.installations.count", 1 do
        result_a =
          @integration.install_on(@org, repositories: [repo_a], installer: @admin, version: @integration.latest_version, entry_point: :test_case)
        result_b =
          @integration.install_on(@org, repositories: [repo_b], installer: @admin, version: @integration.latest_version, entry_point: :test_case)

        assert_predicate result_a, :success?
        assert_predicate result_b, :failed?

        assert_equal "GitHub App has already been installed", result_b.error
      end
    end

    test "instruments creation of the installation" do
      events = subscribe "integration_installation.create"

      result = IntegrationInstallation::Creator.perform(@integration,
        @org, repositories: [@repo], installer: @admin, version: @integration.latest_version, entry_point: :test_case
      )
      assert result.installation

      expected_payload = {}.tap do |payload|
        payload[:installation_id]      = result.installation.id
        payload[:installer_id]         = @admin.id
        payload[:requester_id]         = nil
        payload[:integration]          = @integration.name
        payload[:app]                  = @integration.name
        payload[:integration_id]       = @integration.id
        payload[:app_id]               = @integration.id
        payload[:name]                 = @integration.name
        payload[:slug]                 = @integration.slug
        payload[:org]                  = @org.to_s
        payload[:org_id]               = @org.id
        payload[:repository_selection] = "selected"
        payload[:repository_ids]       = [@repo.id] if GitHub.flipper[:instrument_installation_creation_with_repo_ids].enabled?
      end

      assert event = events.pop, "not instrumented"
      assert_same_hash expected_payload, event.payload
    end

    test "masks the identity of the installer as the bot when installed automatically" do
      events = subscribe "integration_installation.create"

      file_added_trigger = create(:integration_install_trigger, integration: @integration, install_type: :file_added, path: "\\A\\.github/README")

      result = IntegrationInstallation::Creator.perform(@integration, @org,
        repositories: [@repo], installer: @admin, version: @integration.latest_version, trigger_id: file_added_trigger.id, entry_point: :test_case
      )

      assert_predicate result, :success?
      refute_nil result.installation

      expected_payload = {
        app: @integration.name,
        org: @org.to_s,
        app_id: @integration.id,
        org_id: @org.id,
        name: @integration.name,
        slug: @integration.slug,
        trigger_id: file_added_trigger.id,
        integration: @integration.name,
        installer_id: @integration.bot.id,
        requester_id: nil,
        integration_id: @integration.id,
        installation_id: result.installation.id,
        repository_selection: "selected",
        installed_automatically: true,
      }

      if GitHub.flipper[:instrument_installation_creation_with_repo_ids].enabled?
        expected_payload[:repository_ids] = [@repo.id]
      end

      assert event = events.pop, "not instrumented"
      assert_same_hash expected_payload, event.payload
    end

    test "sets the permission for all repos, when no specific repositories are given" do
      version = @integration.versions.create(default_permissions: { "contents" => :read })

      result = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: nil,
        version: version,
        installer: @admin,
        entry_point: :test_case,
      )

      assert result.success?

      assert_able result.installation, :read, @repo.resources.contents
      assert_able result.installation, :read, @public_repo.resources.contents
      new_repo = create(:private_repository, :minimal, owner: @org, created_by_user_id: @admin.id)
      new_public_repo = create(:repository, :minimal, owner: @org, created_by_user_id: @admin.id)
      assert_able result.installation, :read, new_repo.resources.contents
      assert_able result.installation, :read, new_public_repo.resources.contents
    end

    test "does not install permissions on any repositories when :none is passed" do
      version = @integration.versions.create(default_permissions: {})

      result = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: :none,
        version: version,
        installer: @admin,
        entry_point: :test_case,
      )

      assert result.success?
      assert_empty result.installation.repositories
      refute_able result.installation, :read, @repo.resources.contents
    end

    test "uses limited repo permissions when an internal app has the :static_installation_repository_permissions capability" do
      integration = create(:codespaces_integration)
      version = integration.latest_version

      result = IntegrationInstallation::Creator.perform(integration, @org, repositories: [@repo], version: version, installer: @admin, entry_point: :test_case)

      assert_predicate result, :success?
      installation = result.installation

      expected_permissions = Apps::Internal.property(:static_installation_repository_permissions, app: integration)
      unexpected_permissions = version.permissions_of_type(Repository).reject { |resource, _| expected_permissions.key?(resource) }

      expected_permissions.each_pair do |resource, action|
        assert_able installation, action, @repo.resources.public_send(resource.to_sym)
      end

      unexpected_permissions.each_pair do |resource, action|
        refute_able installation, action, @repo.resources.public_send(resource.to_sym)
      end
    end

    test "sets permissions on organization based permissions" do
      version = @integration.versions.create(
        default_permissions: { "members" => :read, "metadata" => :read, "organization_projects" => :read },
        default_events: %w(membership),
      )

      result = assert_queries_matching(/INSERT IGNORE INTO permissions/, 1) do
        IntegrationInstallation::Creator.perform(@integration, @org, repositories: [], version: version, installer: @admin, entry_point: :test_case)
      end

      assert_predicate result, :success?
      installation = result.installation

      assert_able installation, :read, @org.resources.members
      assert_able installation, :read, @org.repository_resources.metadata
      assert_able installation, :read, @org.resources.organization_projects

      assert_same_elements ["membership"], installation.events
    end

    test "an integration with organization permissions can be installed on a user" do
      version = @integration.versions.create(
        default_permissions: { "members" => :read },
        default_events: %w(membership),
      )

      result = IntegrationInstallation::Creator.perform(
        @integration,
        @admin,
        repositories: [],
        version: version,
        installer: @admin,
        entry_point: :test_case,
      )

      assert result.success?
    end

    test "records nil if the target has no Marketplace subscription to the integration" do
      result = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [],
        version: @integration.latest_version,
        installer: @admin,
        entry_point: :test_case,
      )

      assert_nil result.installation.subscription_item_id
    end

    test "records the subscription item for new installations" do
      listing = create(:marketplace_listing, listable: @integration)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      plan_subscription = create(:billing_plan_subscription, user: @org)
      subscription_item = Billing::SubscriptionItem.create(plan_subscription: plan_subscription, subscribable: listing_plan)

      result = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [],
        version: @integration.latest_version,
        installer: @admin,
        entry_point: :test_case,
      )

      assert_equal subscription_item.id, result.installation.subscription_item_id
      assert subscription_item.reload.installed_at.present?
    end

    test "doesn't record an inactive subscription item for new installations" do
      listing = create(:marketplace_listing, listable: @integration)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      plan_subscription = create(:billing_plan_subscription, user: @org)
      Billing::SubscriptionItem.create(plan_subscription: plan_subscription, subscribable: listing_plan, quantity: 0)

      result = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [],
        version: @integration.latest_version,
        installer: @admin,
        entry_point: :test_case,
      )

      assert_nil result.installation.subscription_item_id
    end

    test "doesn't record the subscription item ID for existing installations" do
      installation = @integration.install_on(
        @org,
        repositories: [@repo],
        version: @integration.latest_version,
        installer: @admin,
        entry_point: :test_case,
      ).installation

      assert_nil installation.subscription_item_id

      listing = create(:marketplace_listing, listable: @integration)
      listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      plan_subscription = create(:billing_plan_subscription, user: @org)
      Billing::SubscriptionItem.create(plan_subscription: plan_subscription, subscribable: listing_plan)

      IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [@public_repo],
        version: @integration.latest_version,
        installer: @admin,
        entry_point: :test_case,
      )

      assert_nil installation.subscription_item_id
    end

    test "sets the cache values" do
      options = {
        repositories: [@repo],
        installer: @admin,
        version: create(:integration_version, integration: @integration, default_permissions: { "metadata" => :read }),
        entry_point: :test_case,
      }

      installation = IntegrationInstallation::Creator.perform(@integration, @org, **options).installation
      cache_key_prefix = "integration_installation:#{installation.id}"

      assert_equal installation.permissions, installation.get_cached_permissions
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert GitHub.kv.exists("#{cache_key_prefix}.permissions"), "expected permissions key to be set"
      # rubocop:enable GitHub/DoNotUseGlobalKv

      assert_equal installation.repository_selection, installation.get_cached_repository_selection
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert GitHub.kv.exists("#{cache_key_prefix}.repository_selection"), "expected repository_selection key to be set"
      # rubocop:enable GitHub/DoNotUseGlobalKv

      # Also sets the *_cache columns that will replace using the KV.
      assert_equal installation.permissions, installation.permissions_cache.deep_transform_values(&:to_sym)
      assert_equal installation.repository_selection, installation.repository_selection_cache
    end
  end

  context "dual writing FGP permissions" do
    include PermissionsHelper

    test "writes records to permissions tables for org resources and all repositories" do
      version = @integration.versions.create(
        default_permissions: { "members" => :read, "metadata" => :read },
      )

      result = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [],
        version: version,
        installer: @admin,
        entry_point: :test_case,
      )

      assert result.success?
      installation = result.installation
      assert_able installation, :read, @org.resources.members
      assert_able installation, :read, @repo.resources.metadata

      assert_granted_in_permissions_table(
        actor_id: installation.id,
        actor_type: installation.ability_type,
        subject_id: @org.resources.members.ability_id,
        subject_type: @org.resources.members.ability_type,
      )

      # Check for the permission record that applies to *all* repositories on
      # this organization.
      assert_granted_in_permissions_table(
        actor_id: installation.id,
        actor_type: installation.ability_type,
        subject_id: @org.repository_resources.metadata.ability_id,
        subject_type: @org.repository_resources.metadata.ability_type,
      )
    end

    test "writes records to permissions tables for individual repositories" do
      version = @integration.versions.create(
        default_permissions: { "metadata" => :read },
      )

      result = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [@repo],
        version: version,
        installer: @admin,
        entry_point: :test_case,
      )

      assert result.success?
      installation = result.installation
      assert_able installation, :read, @repo.resources.metadata

      # Check for the permission record that applies to the specific repository
      # that we installed on.
      assert_granted_in_permissions_table(
        actor_id: installation.id,
        actor_type: installation.ability_type,
        subject_id: @repo.resources.metadata.ability_id,
        subject_type: @repo.resources.metadata.ability_type,
      )
    end
  end

  context "Business installation" do
    test "can install an app as a business" do
      integration = create(:integration, default_permissions: { "enterprise_administration" => :write, "enterprise_vulnerabilities" => :write })
      business    = create(:business)
      installer   = business.owners.first

      result = assert_queries_matching(/INSERT IGNORE INTO permissions/, 1) do
        IntegrationInstallation::Creator.perform(integration, business, repositories: [], version: integration.latest_version, installer: installer, entry_point: :test_case)
      end

      assert_predicate result, :success?

      installation = result.installation
      assert_able installation, :write, business.resources.enterprise_administration
      assert_able installation, :write, business.resources.enterprise_vulnerabilities
    end

    test "it does not grant organization permissions" do
      integration = create(:integration, default_permissions: { "organization_administration" => :write, Business::Resources.subject_types.first => :read })
      business    = create(:business)

      result = IntegrationInstallation::Creator.perform(
        integration,
        business,
        repositories: [],
        version: integration.latest_version,
        installer: business.owners.first,
        entry_point: :test_case,
      )

      assert_predicate result, :success?

      installation = result.installation
      assert_equal({ Business::Resources.subject_types.first => :read }, installation.permissions)
    end

    test "it does not grant repository permissions" do
      integration = create(:integration, default_permissions: { "metadata" => :read, Business::Resources.subject_types.first => :read })
      business    = create(:business)

      result = IntegrationInstallation::Creator.perform(
        integration,
        business,
        repositories: [],
        version: integration.latest_version,
        installer: business.owners.first,
        entry_point: :test_case,
      )

      assert_predicate result, :success?

      installation = result.installation
      assert_equal({ Business::Resources.subject_types.first => :read }, installation.permissions)
    end
  end
end
