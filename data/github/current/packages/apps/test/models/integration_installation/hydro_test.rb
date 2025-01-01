# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class IntegrationInstallationHydroEventsTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @integration = create(:integration, default_permissions: { "metadata" => :read })

    @admin = create(:paid_user)
    @member = create(:user)
    @collaborator = create(:user)

    @org   = create(:organization, admin: @admin)
    @org.add_member(@member)

    @business = create(:business, owners: [@admin])

    @repo = create(:private_repository, :minimal, owner: @org)
    @repo.add_member(@collaborator)
    @public_repo = create(:repository, :minimal, owner: @org)
    @user_repo = create(:private_repository, :minimal, owner: @admin)
  end

  context "installing", skip_enterprise: true do
    test "all repositories on a user" do
      installation = make_integration_installation(integration: @integration, target: @admin)

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :USER,
          target_id: @admin.id,
          target_name: @admin.login,
          repository_selection: :ALL,
        },
        integration: Hydro::EntitySerializer.integration(@integration),
        repositories: [],
        sender: Hydro::EntitySerializer.user(@admin),
      }, schema: "github.v1.IntegrationInstallationCreate")
    end

    test "a single repository on a user" do
      installation = make_integration_installation(integration: @integration, target: @admin, repositories: [@user_repo])

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :USER,
          target_id: @admin.id,
          target_name: @admin.login,
          repository_selection: :SELECTED,
        },
        integration: Hydro::EntitySerializer.integration(@integration),
        repositories: [Hydro::EntitySerializer.repository(@user_repo)],
        sender: Hydro::EntitySerializer.user(@admin),
      }, schema: "github.v1.IntegrationInstallationCreate")
    end

    test "all repositories on an org" do
      installation = make_integration_installation(integration: @integration, target: @org)

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :ORGANIZATION,
          target_id: @org.id,
          target_name: @org.login,
          repository_selection: :ALL,
        },
        integration: Hydro::EntitySerializer.integration(@integration),
        repositories: [],
        sender: Hydro::EntitySerializer.user(@admin),
      }, schema: "github.v1.IntegrationInstallationCreate")
    end

    test "a single repository on an org" do
      installation = make_integration_installation(integration: @integration, target: @org, repositories: [@repo])

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :ORGANIZATION,
          target_id: @org.id,
          target_name: @org.login,
          repository_selection: :SELECTED,
        },
        integration: Hydro::EntitySerializer.integration(@integration),
        repositories: [Hydro::EntitySerializer.repository(@repo)],
        sender: Hydro::EntitySerializer.user(@admin),
      }, schema: "github.v1.IntegrationInstallationCreate")
    end

    test "handles failure to find the installation", skip_if_feature_disabled: :instrument_installation_creation_with_repo_ids do
      # Simulates failure to find the installation
      IntegrationInstallation.stubs(:find_by).returns(nil)
      installation = make_integration_installation(integration: @integration, target: @org, repositories: [@repo])

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :ORGANIZATION,
          target_id: @org.id,
          target_name: @org.login,
          repository_selection: :SELECTED,
        },
        integration: Hydro::EntitySerializer.integration(@integration),
        repositories: [Hydro::EntitySerializer.repository(@repo)],
        sender: Hydro::EntitySerializer.user(@admin),
      }, schema: "github.v1.IntegrationInstallationCreate")
    end

    test "handles failure to find the installation with feature disabled", skip_if_feature_enabled: :instrument_installation_creation_with_repo_ids do
      # Simulates failure to find the installation
      IntegrationInstallation.stubs(:find_by).returns(nil)
      installation = make_integration_installation(integration: @integration, target: @org, repositories: [@repo])

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :ORGANIZATION,
          target_id: @org.id,
          target_name: @org.login,
          repository_selection: :SELECTED,
        },
        integration: Hydro::EntitySerializer.integration(@integration),
        repositories: [],
        sender: Hydro::EntitySerializer.user(@admin),
      }, schema: "github.v1.IntegrationInstallationCreate")
    end

    test "on a business" do
      installation = make_integration_installation(target: @business, permissions: { Business::Resources.subject_types.first => :read })

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :BUSINESS,
          target_id: @business.id,
          target_name: @business.slug,
          repository_selection: :SELECTED,
        },
        integration: Hydro::EntitySerializer.integration(installation.integration),
        repositories: [],
        sender: Hydro::EntitySerializer.user(@admin),
      }, schema: "github.v1.IntegrationInstallationCreate")
    end
  end

  context "uninstalling", skip_enterprise: true do
    test "uninstalling from a user" do
      installation = make_integration_installation(integration: @integration, target: @admin, repositories: [@user_repo])
      installation.uninstall(actor: @admin)

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :USER,
          target_id: @admin.id,
          target_name: @admin.login,
          repository_selection: :SELECTED,
        },
        integration: Hydro::EntitySerializer.integration(@integration),
        sender: Hydro::EntitySerializer.user(@admin),
      }, schema: "github.v1.IntegrationInstallationDelete")
    end

    test "uninstalling from an org" do
      installation = make_integration_installation(integration: @integration, target: @org, repositories: [@repo])
      installation.uninstall(actor: @member)

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :ORGANIZATION,
          target_id: @org.id,
          target_name: @org.login,
          repository_selection: :SELECTED,
        },
        integration: Hydro::EntitySerializer.integration(@integration),
        sender: Hydro::EntitySerializer.user(@member),
      }, schema: "github.v1.IntegrationInstallationDelete")
    end

    test "uninstalling from a business" do
      installation = make_integration_installation(integration: @integration, target: @business, permissions: { Business::Resources.subject_types.first => :read })
      installation.uninstall(actor: @admin)

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :BUSINESS,
          target_id: @business.id,
          target_name: @business.slug,
          repository_selection: :SELECTED,
        },
        integration: Hydro::EntitySerializer.integration(@integration),
        sender: Hydro::EntitySerializer.user(@admin),
      }, schema: "github.v1.IntegrationInstallationDelete")
    end
  end

  context "editting", skip_enterprise: true do
    test "adding repositories" do
      installation = make_integration_installation(integration: @integration, target: @org, repositories: [@repo])

      installation.edit(repositories: [@repo, @public_repo], editor: @admin, entry_point: :test_case)

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :ORGANIZATION,
          target_id: @org.id,
          target_name: @org.login,
          repository_selection: :SELECTED,
        },
        repositories_added: [Hydro::EntitySerializer.repository(@public_repo)],
        sender: Hydro::EntitySerializer.user(@admin),
      }, schema: "github.v1.IntegrationInstallationRepositoriesAdded")
    end

    test "removing repositories" do
      installation = make_integration_installation(integration: @integration, target: @org, repositories: [@repo, @public_repo])

      installation.edit(repositories: [@public_repo], editor: @admin, entry_point: :test_case)

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :ORGANIZATION,
          target_id: @org.id,
          target_name: @org.login,
          repository_selection: :SELECTED,
        },
        repositories_removed: [Hydro::EntitySerializer.repository(@repo)],
        sender: Hydro::EntitySerializer.user(@admin),
      }, schema: "github.v1.IntegrationInstallationRepositoriesRemoved")
    end

    test "adding and removing repositories" do
      installation = make_integration_installation(integration: @integration, target: @org, repositories: [@repo])

      installation.edit(repositories: [@public_repo], editor: @admin, entry_point: :test_case)

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :ORGANIZATION,
          target_id: @org.id,
          target_name: @org.login,
          repository_selection: :SELECTED,
        },
        repositories_added: [Hydro::EntitySerializer.repository(@public_repo)],
        sender: Hydro::EntitySerializer.user(@admin),
      }, schema: "github.v1.IntegrationInstallationRepositoriesAdded")

      assert_hydro_published({
        installation: {
          id: installation.id,
          target_type: :ORGANIZATION,
          target_id: @org.id,
          target_name: @org.login,
          repository_selection: :SELECTED,
        },
        repositories_removed: [Hydro::EntitySerializer.repository(@repo)],
        sender: Hydro::EntitySerializer.user(@admin),
      }, schema: "github.v1.IntegrationInstallationRepositoriesRemoved")
    end
  end
end
