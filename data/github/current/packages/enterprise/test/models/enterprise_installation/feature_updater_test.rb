# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseInstallationFeatureUpdaterTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @anon = create :user
    @admin = create :user
    @org = create :organization, admin: @admin

    @business = create :business, owners: [@admin]

    @business_enterprise_installation = create :enterprise_installation, owner: @business
    @business_integration, @business_integration_secret = @business_enterprise_installation.create_github_app
    result = @business_integration.install_on(
      @business,
      repositories: :none,
      installer: @admin,
      entry_point: :test_case
    )
    @business_integration_installation = result.installation

    @org_enterprise_installation = create :enterprise_installation, owner: @org
    @org_integration, @org_integration_secret = @org_enterprise_installation.create_github_app
    result = @org_integration.install_on(
      @org,
      repositories: [],
      installer: @admin,
      entry_point: :test_case
    )
    @org_integration_installation = result.installation
  end

  test "fails when integration does not exist" do
    @org_integration.destroy!
    @org_enterprise_installation.request_github_app_permissions_update(["contributions"])

    result = EnterpriseInstallation::FeatureUpdater.perform(@org_enterprise_installation, actor: @admin, entry_point: :test_case)
    assert result.failed?
    refute_nil result.error
  end

  test "updates integration installation for connected org when permissions are changed" do
    @org_enterprise_installation.request_github_app_permissions_update(["content_analysis"])

    new_version = @org_integration.latest_version

    refute_equal new_version.id, @org_integration_installation.integration_version_id
    refute_equal new_version.number, @org_integration_installation.integration_version_number

    assert @org_integration_installation.permissions.empty?

    EnterpriseInstallation::FeatureUpdater.perform(@org_enterprise_installation, actor: @admin, entry_point: :test_case)

    @org_integration_installation.reload

    assert_equal new_version.id, @org_integration_installation.integration_version_id
    assert_equal new_version.number, @org_integration_installation.integration_version_number

    refute @org_integration_installation.permissions.empty?

    @org_enterprise_installation.request_github_app_permissions_update([])

    @org_integration.reload
    new_version = @org_integration.latest_version

    refute_equal new_version.id, @org_integration_installation.integration_version_id
    refute_equal new_version.number, @org_integration_installation.integration_version_number

    EnterpriseInstallation::FeatureUpdater.perform(@org_enterprise_installation, actor: @admin, entry_point: :test_case)

    @org_integration_installation.reload

    assert_equal new_version.id, @org_integration_installation.integration_version_id
    assert_equal new_version.number, @org_integration_installation.integration_version_number

    assert @org_integration_installation.permissions.empty?
  end

  test "updates integration installation for connected enterprise when permissions are changed" do
    @business_enterprise_installation.request_github_app_permissions_update(["content_analysis"])

    new_version = @business_integration.latest_version

    refute_equal new_version.id, @business_integration_installation.integration_version_id
    refute_equal new_version.number, @business_integration_installation.integration_version_number

    assert @business_integration_installation.permissions.empty?

    EnterpriseInstallation::FeatureUpdater.perform(@business_enterprise_installation, actor: @admin, entry_point: :test_case)

    @business_integration_installation.reload

    assert_equal new_version.id, @business_integration_installation.integration_version_id
    assert_equal new_version.number, @business_integration_installation.integration_version_number

    refute @business_integration_installation.permissions.empty?

    @business_enterprise_installation.request_github_app_permissions_update([])

    @business_integration.reload
    new_version = @business_integration.latest_version

    refute_equal new_version.id, @business_integration_installation.integration_version_id
    refute_equal new_version.number, @business_integration_installation.integration_version_number

    EnterpriseInstallation::FeatureUpdater.perform(@business_enterprise_installation, actor: @admin, entry_point: :test_case)

    @business_integration_installation.reload

    assert_equal new_version.id, @business_integration_installation.integration_version_id
    assert_equal new_version.number, @business_integration_installation.integration_version_number

    assert @business_integration_installation.permissions.empty?
  end

  test "installs integration installation on all connected org repositories for private search" do
    GitHub.flipper[:cached_fgp_permissions].disable

    @org_enterprise_installation.request_github_app_permissions_update(["private_search"])

    EnterpriseInstallation::FeatureUpdater.perform(@org_enterprise_installation, actor: @admin, entry_point: :test_case)

    assert @org_integration_installation.installed_on_all_repositories?
    assert_equal @org_integration.latest_version.default_permissions,
                 @org_integration_installation.permissions
  end

  test "does not update if actor is not an admin of the connected organization" do
    @org_enterprise_installation.request_github_app_permissions_update(["contributions"])
    new_version = @org_integration.latest_version

    EnterpriseInstallation::FeatureUpdater.perform(@org_enterprise_installation, actor: @anon, entry_point: :test_case)

    @org_integration_installation.reload

    refute_equal new_version.id, @org_integration_installation.integration_version_id
    refute_equal new_version.number, @org_integration_installation.integration_version_number

    assert @org_integration_installation.permissions.empty?
  end

  test "does not update if actor is not an admin of the connected enterprise" do
    @business_enterprise_installation.request_github_app_permissions_update(["contributions"])
    new_version = @business_integration.latest_version

    EnterpriseInstallation::FeatureUpdater.perform(@business_enterprise_installation, actor: @anon, entry_point: :test_case)

    @business_integration_installation.reload

    refute_equal new_version.id, @business_integration_installation.integration_version_id
    refute_equal new_version.number, @business_integration_installation.integration_version_number

    assert @business_integration_installation.permissions.empty?
  end

  test "logs to failbot when an error is raised" do
    @org_integration.destroy!
    @org_enterprise_installation.request_github_app_permissions_update(["contributions"])

    EnterpriseInstallation::FeatureUpdater.perform(@org_enterprise_installation, actor: @admin, entry_point: :test_case)
    assert Failbot.reports.detect do |report|
      report["class"] == "EnterpriseInstallation::FeatureUpdater::Result::Error"
    end
  end

  test "instruments integration_installation.version_updated if version changes" do
    old_version = @business_integration.latest_version
    @business_enterprise_installation.request_github_app_permissions_update(["content_analysis"])
    new_version = @business_integration.reload.latest_version

    events = subscribe "integration_installation.version_updated"

    EnterpriseInstallation::FeatureUpdater.perform(@business_enterprise_installation, actor: @admin, entry_point: :test_case)

    assert event = events.pop, "Expected an integration_installation.version_updated event"
    expected_payload = {}.tap do |payload|
      payload[:installation_id]      = @business_integration_installation.id
      payload[:actor]                = @admin.login
      payload[:actor_id]             = @admin.id
      payload[:integration]          = @business_integration.name
      payload[:app]                  = @business_integration.name
      payload[:integration_id]       = @business_integration.id
      payload[:app_id]               = @business_integration.id
      payload[:name]                 = @business_integration.name
      payload[:slug]                 = @business_integration.slug
      payload[:business]             = @business.slug
      payload[:business_id]          = @business.id
      payload[:old_version]          = old_version.number
      payload[:new_version]          = new_version.number
      payload[:repository_selection] = "selected"
      payload[:permissions_added]    = { "enterprise_vulnerabilities" => :read }
    end
    assert_same_hash expected_payload, event.payload
  end

  test "does not instrument integration_installation.version_updated if version does not change" do
    events = subscribe "integration_installation.version_updated"

    EnterpriseInstallation::FeatureUpdater.perform(@business_enterprise_installation, actor: @admin, entry_point: :test_case)

    assert_equal 0, events.count
  end

  test "publishes a Hydro event when features are added", skip_enterprise: true do
    features = %w(contributions)
    features_removed = []
    @business_enterprise_installation.request_github_app_permissions_update(features)

    EnterpriseInstallation::FeatureUpdater.perform(@business_enterprise_installation, actor: @admin, entry_point: :test_case)

    assert_hydro_published({
      enterprise_installation: Hydro::EntitySerializer.enterprise_installation(@business_enterprise_installation),
      features: features,
      actor: Hydro::EntitySerializer.user(@admin),
      features_disabled: features_removed,
    }, schema: "github.github_connect.v0.UpdateFeatures")
  end

  test "publishes a Hydro event when features are removed", skip_enterprise: true do
    # Add search features first
    @business_enterprise_installation.request_github_app_permissions_update(%w[private_search search])
    EnterpriseInstallation::FeatureUpdater.perform(@business_enterprise_installation, actor: @admin, entry_point: :test_case)

    # Now test removing the same features (done by sending an empty array of features)
    @business_enterprise_installation.request_github_app_permissions_update([])

    # The additional feature being removed, 'search', needs no permission changes, so would be passed in here by
    # the enterprise_installation_controller's upgrade_confirm action
    EnterpriseInstallation::FeatureUpdater.perform(@business_enterprise_installation, actor: @admin, non_perm_change_features: { removed: ["search"] }, entry_point: :test_case)

    assert_hydro_published({
      enterprise_installation: Hydro::EntitySerializer.enterprise_installation(@business_enterprise_installation),
      features: [],
      actor: Hydro::EntitySerializer.user(@admin),
      features_disabled: %w(private_search search),
    }, schema: "github.github_connect.v0.UpdateFeatures")
  end

  test "does not publish a Hydro event if version doesn't change", skip_enterprise: true do
    features = %w(contributions)
    EnterpriseInstallation::FeatureUpdater.perform(@business_enterprise_installation, actor: @admin, entry_point: :test_case)

    refute_hydro_messages(schema: "github.github_connect.v0.UpdateFeatures")
  end

  test "schedules the job to update app installations if target is a business and an update is actually performed" do
    features = %w(contributions)
    @business_enterprise_installation.request_github_app_permissions_update(features)

    expected_args = [
      @business.id,
      { entry_point: :enterprise_installation_feature_updater }
    ]

    assert_enqueued_with(job: UpdatePrivateSearchOnEnterpriseOrgsJob, args: expected_args) do
      EnterpriseInstallation::FeatureUpdater.perform(@business_enterprise_installation, actor: @admin, entry_point: :test_case)
    end
  end

  test "does not schedule the job to update app installations if target is an organization" do
    org = create :business_plus_organization, admin: @admin
    enterprise_installation = create :enterprise_installation, owner: org
    integration, secret = enterprise_installation.create_github_app
    installation = make_integration_installation(integration: integration, target: org)

    assert_no_enqueued_jobs(only: UpdatePrivateSearchOnEnterpriseOrgsJob) do
      EnterpriseInstallation::FeatureUpdater.perform(enterprise_installation, actor: @admin, entry_point: :test_case)
    end
  end

  test "does not schedule the job to update app installations if we're already at latest version (no update performed)" do
    assert_no_enqueued_jobs(only: UpdatePrivateSearchOnEnterpriseOrgsJob) do
      EnterpriseInstallation::FeatureUpdater.perform(@business_enterprise_installation, actor: @admin, entry_point: :test_case)
    end
  end
end
