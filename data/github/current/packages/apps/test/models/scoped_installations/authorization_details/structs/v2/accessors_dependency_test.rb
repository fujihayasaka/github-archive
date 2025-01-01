# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::Structs::V2::AccessorsDependencyTest < GitHub::TestCase
  context "#get" do
    test "property has been set" do
      property = ScopedInstallations::AuthorizationDetails::Structs::V2::SelectionWithPermissions.new(
        selection: ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new(repository: property)
      selection = struct.get(ScopedInstallations::AuthorizationDetails::ResourceType::Repository)

      assert_equal(property, selection)
    end

    test "property has not been set" do
      property = ScopedInstallations::AuthorizationDetails::Structs::V2::SelectionWithPermissions.new(
        selection: ScopedInstallations::AuthorizationDetails::Selection::None,
        permissions: {}
      )

      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new
      selection = struct.get(ScopedInstallations::AuthorizationDetails::ResourceType::Repository)

      assert_same_hash(property.serialize, selection.serialize)
    end

    test "gets a correct default value per each registered resource type" do
      properties = ScopedInstallations::AuthorizationDetails::Structs::V2::AccessorsDependency::DEFAULT_RESOURCE_SELECTION_BY_PROPERTY
      properties.each do |property, default_value_class|
        resource_type = ScopedInstallations::AuthorizationDetails::ResourceType.for(property.to_s)
        value = ScopedInstallations::AuthorizationDetails::Structs::V2.new.get(resource_type)

        assert_instance_of(default_value_class, value)
      end
    end
  end

  context "#selection_for" do
    test "property has an enum selection" do
      property = ScopedInstallations::AuthorizationDetails::Structs::V2::SelectionWithPermissions.new(
        selection: ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new(repository: property)
      selection = struct.selection_for(ScopedInstallations::AuthorizationDetails::ResourceType::Repository)

      assert_equal(ScopedInstallations::AuthorizationDetails::Selection::All, selection)
    end

    test "property has an array selection" do
      property = ScopedInstallations::AuthorizationDetails::Structs::V2::SelectionWithPermissions.new(
        selection: [42],
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new(repository: property)
      selection = struct.selection_for(ScopedInstallations::AuthorizationDetails::ResourceType::Repository)

      assert_equal(ScopedInstallations::AuthorizationDetails::Selection::Subset, selection)
    end
  end
end
