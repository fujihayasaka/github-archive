# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalIntegrationInstallationTest < GitHub::TestCase
  fixtures do
    @integration = create_global_integration(permissions: { "metadata" => :read, "contents" => :write, "members" => :read })
    @target = create(:organization)
  end

  setup do
    @global_installation = GlobalIntegrationInstallation.new(@integration, @target)
  end

  context "#can_self_install?" do
    test "returns false if the app doesn't have repo administration write" do
      global_integration = create_global_integration(permissions: { "metadata" => :read, "administration" => :read })
      global_installation = GlobalIntegrationInstallation.new(global_integration, global_integration.owner)

      refute global_installation.can_self_install?(global_integration.owner)
    end

    test "returns true if the app has repo administration write" do
      global_integration = create_global_integration(permissions: { "metadata" => :read, "administration" => :write })
      global_installation = GlobalIntegrationInstallation.new(global_integration, global_integration.owner)

      assert global_installation.can_self_install?(global_integration.owner)
    end

    test "returns false for a random target with the right permissions" do
      rando = create(:user)

      global_integration = create_global_integration(permissions: { "metadata" => :read, "administration" => :write })
      global_installation = GlobalIntegrationInstallation.new(global_integration, global_integration.owner)

      refute global_installation.can_self_install?(rando)
    end
  end

  test "#id" do
    assert_equal @integration.id, @global_installation.id
  end

  context "#installed_on_all_repositories" do
    test "returns true if there are any repo permissions" do
      assert_predicate @global_installation, :installed_on_all_repositories?
    end

    test "returns false if there are no repo permissions" do
      global_integration = create_global_integration(permissions: {})
      global_installation = GlobalIntegrationInstallation.new(global_integration, global_integration.owner)

      refute_predicate global_installation, :installed_on_all_repositories?
    end

    test "returns false if the resource is not available" do
      refute @global_installation.installed_on_all_repositories?(resource: :issues)
    end

    test "returns false if the minimum action is not met" do
      refute @global_installation.installed_on_all_repositories?(min_action: :write, resource: :metadata)
    end
  end

  test "#installed_on_individual_repository_ids" do
    assert_empty @global_installation.installed_on_individual_repository_ids
  end

  test "#new_record?" do
    refute_predicate @global_installation, :new_record?
  end

  test "#permission_results" do
    assert_same_hash @global_installation.permission_results, @integration.default_permissions
  end

  context "#repositories_count" do
    test "returns 0 if there are no repo permissions" do
      global_integration = create_global_integration(permissions: {})
      global_installation = GlobalIntegrationInstallation.new(global_integration, global_integration.owner)

      assert_equal 0, global_installation.repositories_count
    end

    test "returns the number of repos on the target if it has repo access" do
      repo = create(:repository, owner: @target)
      assert_equal 1, @global_installation.repositories_count
    end
  end

  test "#abilities" do
    assert_kind_of ActiveRecord::Relation, @global_installation.abilities
    assert_empty @global_installation.abilities.to_a
  end

  test "#authorization_details" do
    details = @global_installation.authorization_details_struct

    assert_equal 1, details.version

    assert details.explicitly_grants_permission?(
      resource_type: ScopedInstallations::AuthorizationDetails::ResourceType::Organization,
      selection: ScopedInstallations::AuthorizationDetails::Selection::Global,
      resource: "members"
    )

    assert details.explicitly_grants_permission?(
      resource_type: ScopedInstallations::AuthorizationDetails::ResourceType::Repository,
      selection: ScopedInstallations::AuthorizationDetails::Selection::Global,
      resource: "metadata",
    )

    assert details.explicitly_grants_permission?(
      resource_type: ScopedInstallations::AuthorizationDetails::ResourceType::Repository,
      selection: ScopedInstallations::AuthorizationDetails::Selection::Global,
      resource: "contents",
      action: :write
    )
  end

  test "#authzd_proto_attributes" do
    expected = [
      Authzd::Proto::Attribute.wrap("authorization_details.version", 2),

      Authzd::Proto::Attribute.wrap("authorization_details.v2.organization.selection", "global"),
      Authzd::Proto::Attribute.wrap("authorization_details.v2.organization.permissions", ["members:read"]),

      Authzd::Proto::Attribute.wrap("authorization_details.v2.repository.selection", "global"),
      Authzd::Proto::Attribute.wrap("authorization_details.v2.repository.permissions", ["contents:read", "contents:write", "metadata:read"]),

      Authzd::Proto::Attribute.wrap("installation.global.authorization_details.version", 1),

      Authzd::Proto::Attribute.wrap("installation.global.authorization_details.v1.selections.repository", "global"),
      Authzd::Proto::Attribute.wrap("installation.global.authorization_details.v1.selections.organization", "global"),

      Authzd::Proto::Attribute.wrap("installation.global.authorization_details.v1.subject_types_and_actions.repository.metadata.read", true),
      Authzd::Proto::Attribute.wrap("installation.global.authorization_details.v1.subject_types_and_actions.repository.contents.read", true),
      Authzd::Proto::Attribute.wrap("installation.global.authorization_details.v1.subject_types_and_actions.repository.contents.write", true),
      Authzd::Proto::Attribute.wrap("installation.global.authorization_details.v1.subject_types_and_actions.organization.members.read", true),
    ]

    actual = @global_installation.authzd_proto_attributes.map do |attribute|
      attribute_value = attribute.value.unwrap
      next attribute unless attribute_value.is_a?(Google::Protobuf::RepeatedField)

      Authzd::Proto::Attribute.wrap(attribute.id, attribute_value.sort)
    end

    assert_same_elements expected, actual
  end

  test "#for_target" do
    user = create(:user)
    installation = GlobalIntegrationInstallation.for_target(@integration, user)

    assert_equal @global_installation.class, installation.class
    assert_equal @global_installation.integration_id, installation.integration_id
    assert_equal @global_installation.authorization_details, installation.authorization_details

    assert_nil GlobalIntegrationInstallation.for_target(@integration, nil)
    assert_nil GlobalIntegrationInstallation.for_target(nil, user)
    assert_nil GlobalIntegrationInstallation.for_target(nil, nil)
  end

  test "#for_repository" do
    repo = create(:private_repository)
    installation = GlobalIntegrationInstallation.for_repository(@integration, repo)

    assert_equal @global_installation.class, installation.class
    assert_equal @global_installation.integration_id, installation.integration_id
    assert_equal @global_installation.authorization_details, installation.authorization_details

    other_integration = create_global_integration(permissions: {})
    assert_nil GlobalIntegrationInstallation.for_repository(other_integration, repo)

    assert_nil GlobalIntegrationInstallation.for_repository(@integration, nil)
    assert_nil GlobalIntegrationInstallation.for_repository(nil, repo)
    assert_nil GlobalIntegrationInstallation.for_repository(nil, nil)
  end
end
