# typed: true
# frozen_string_literal: true

require "test_helper"

module ProgrammaticActor
  class OrganizationFilterTest < GitHub::TestCase
    include ApiProgrammaticGrantHelpers

    fixtures do
      @admin = create(:user)

      @org1 = create(:organization, admin: @admin)
      @org2 = create(:organization, admin: @admin)

      @integration = create(:integration, default_permissions: { "members" => :read })
    end

    def described_class
      ::ProgrammaticActor::OrganizationFilter
    end

    context ".applicable?" do
      test "returns true for user-to-server requests" do
        @admin.oauth_access = @integration.grant(@admin, entry_point: :test_case)

        assert_predicate @admin, :using_auth_via_integration?
        assert described_class.applicable?(@admin)
      end

      test "returns true for user programmatic access requests" do
        access = create(:user_programmatic_access, owner: @admin)
        @admin.programmatic_access = access

        assert_predicate @admin, :using_auth_via_user_programmatic_access?
        assert described_class.applicable?(@admin)
      end

      test "returns false for OAuth requests" do
        access = create(:oauth_access, :personal_token, user: @admin)
        @admin.oauth_access = access

        assert_predicate @admin, :using_personal_access_token?
        refute described_class.applicable?(@admin)
      end
    end

    context ".perform" do
      test "filters user-to-server requests" do
        make_integration_installation(integration: @integration, target: @org1)
        @admin.oauth_access = @integration.grant(@admin, entry_point: :test_case)

        organization_ids = described_class.perform(
          actor: @admin, resource: "members",
          organization_ids: @admin.organization_ids,
        )

        assert_same_elements [@org1.id, @org2.id], @admin.organization_ids
        assert_same_elements [@org1.id], organization_ids
      end

      test "filters scoped user-to-server requests" do
        parent_installation = make_integration_installation(integration: @integration, target: @org1)
        make_integration_installation(integration: @integration, target: @org2)

        access = @integration.grant(@admin, entry_point: :test_case)
        @admin.oauth_access = access

        organization_ids = described_class.perform(
          actor: @admin, resource: "members",
          organization_ids: @admin.organization_ids,
        )

        assert_same_elements [@org1.id, @org2.id], organization_ids

        result = ScopedIntegrationInstallation::Creator.perform(parent_installation, entry_point: :test_case)
        assert_predicate result, :success?

        access.update!(installation: result.installation)
        access.reload

        @admin.oauth_access = access

        organization_ids = described_class.perform(
          actor: @admin, resource: "members",
          organization_ids: @admin.organization_ids,
        )

        assert_same_elements [@org1.id], organization_ids
      end

      test "filters scoped user-to-server with authorization details only", skip_if_feature_disabled: :scoped_installations_authorization_details_ga do
        parent_installation = make_integration_installation(integration: @integration, target: @org1)
        make_integration_installation(integration: @integration, target: @org2)

        access = @integration.grant(@admin, entry_point: :test_case)
        @admin.oauth_access = access

        organization_ids = described_class.perform(
          actor: @admin, resource: "members",
          organization_ids: @admin.organization_ids,
        )

        assert_same_elements [@org1.id, @org2.id], organization_ids

        result = ScopedIntegrationInstallation::Creator.perform(parent_installation, entry_point: :test_case)
        assert_predicate result, :success?

        access.update!(installation: result.installation)
        access.reload

        @admin.oauth_access = access

        installation = result.installation
        Permission.where(actor_id: installation.ability_id, actor_type: installation.ability_type).destroy_all

        assert installation.authorization_details_struct.explicitly_grants_permission?(
          resource_type: ScopedInstallations::AuthorizationDetails::ResourceType::Organization,
          selection: [@org1.id],
          resource: "members"
        )

        organization_ids = described_class.perform(
          actor: @admin, resource: "members",
          organization_ids: @admin.organization_ids,
        )

        assert_same_elements [@org1.id], organization_ids
      end

      test "filters user programmatic access requests" do
        @admin.programmatic_access = make_user_programmatic_access_with_grant(
          requester: @admin, target: @org2, permissions: { "members" => :read }
        )

        organization_ids = described_class.perform(
          actor: @admin, resource: "members",
          organization_ids: @admin.organization_ids,
        )

        assert_same_elements [@org2.id], organization_ids
      end
    end
  end
end
