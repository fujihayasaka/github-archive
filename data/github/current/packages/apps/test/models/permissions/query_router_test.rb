# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class PermissionsQueryRouterTest < GitHub::TestCase
  include PermissionsHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @app = create(:integration)
    @target = create(:organization)
    @installation = make_integration_installation(integration: @app, target: @target)
    @fgp_subject = @target.resources.organization_projects
  end

  context "ACTOR_TYPES_WITH_FINE_GRAINED_PERMISSIONS" do
    test "has the expected actor_types" do
      expected = %w[IntegrationInstallation OauthAuthorization ScopedIntegrationInstallation].sort
      actual   = Permissions::QueryRouter::ACTOR_TYPES_WITH_FINE_GRAINED_PERMISSIONS.sort

      assert_equal expected, actual
    end
  end

  context "model" do
    test "returns Ability for ability sqls" do
      router = Permissions::QueryRouter.for(subject_types: ["Organization"])

      assert_equal Ability, router.model
    end

    test "returns Permission for permission sqls" do
      router = Permissions::QueryRouter.for(subject_types: ["Organization/members"])

      assert_equal Permission, router.model
    end

    test "returns Permission for subject types Repository/metadata" do
      router = Permissions::QueryRouter.for(subject_types: ["Repository/metadata"])

      assert_equal Permission, router.model
    end

    test "returns Permission when all subject types are fine grained" do
      router = Permissions::QueryRouter.for(subject_types: ["Repository/metadata", "User/repositories/metadata"])

      assert_equal Permission, router.model
    end
  end

  context ".delete_app_permissions_on_actor" do
    test "deletes all permissions for a given actor" do
      Permissions::Service.grant_app_permission(actor: @installation, subject: @fgp_subject, action: :read, entry_point: :test_case)

      assert_granted_in_permissions_table(
        actor_id:     @installation.id,
        actor_type:   @installation.ability_type,
        subject_id:   @fgp_subject.ability_id,
        subject_type: @fgp_subject.ability_type,
        action:       :read,
      )

      Permissions::QueryRouter.delete_app_permissions_on_actor(@installation, entry_point: :test_case)

      refute_granted_in_permissions_table(
        actor_id:     @installation.id,
        actor_type:   @installation.ability_type,
        subject_id:   @fgp_subject.ability_id,
        subject_type: @fgp_subject.ability_type,
        action:       :read,
      )
    end
  end

  context ".delete_app_permissions_on_subject" do
    test "deletes all permissions for a given subject" do
      Permissions::Service.grant_app_permission(actor: @installation, subject: @fgp_subject, action: :read, entry_point: :test_case)

      assert_granted_in_permissions_table(
        actor_id: @installation.id,
        actor_type: @installation.ability_type,
        subject_id: @fgp_subject.ability_id,
        subject_type: @fgp_subject.ability_type,
      )

      assert_able @installation, :read, @fgp_subject

      Permissions::QueryRouter.delete_app_permissions_on_subject(@target, entry_point: :test_case)

      refute_granted_in_permissions_table(
        actor_id: @installation.id,
        actor_type: @installation.ability_type,
        subject_id: @fgp_subject.ability_id,
        subject_type: @fgp_subject.ability_type,
        action: :read,
      )
    end
  end
end
