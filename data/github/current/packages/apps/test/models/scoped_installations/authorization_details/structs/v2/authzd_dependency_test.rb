# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::Structs::V2::AuthzdDependencyTest < GitHub::TestCase
  context "#authzd_proto_attributes" do
    test "version is set" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new

      assert_same_elements([
        Authzd::Proto::Attribute.wrap("authorization_details.version", 2)
      ], struct.authzd_proto_attributes)
    end

    test "prefixes attributes property name" do
      property = ScopedInstallations::AuthorizationDetails::Structs::V2::SelectionWithPermissions.new(
        selection: ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new(repository: property)

      assert_same_elements([
        Authzd::Proto::Attribute.wrap("authorization_details.version", 2),
        Authzd::Proto::Attribute.wrap("authorization_details.v2.repository.selection", "all"),
        Authzd::Proto::Attribute.wrap("authorization_details.v2.repository.permissions", ["metadata:read"])
      ], struct.authzd_proto_attributes)
    end
  end
end
