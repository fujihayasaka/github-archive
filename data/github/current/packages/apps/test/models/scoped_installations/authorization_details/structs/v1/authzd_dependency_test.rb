# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::Structs::V1::AuthzdDependencyTest < GitHub::TestCase
  context "#authzd_proto_attributes" do
    test "transforms into version 2 attributes" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        selections: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::All
        },
        subject_types_and_actions: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "metadata" => Permission::Action::Read
          }
        }
      )

      assert_same_elements([
        Authzd::Proto::Attribute.wrap("authorization_details.version", 2),
        Authzd::Proto::Attribute.wrap("authorization_details.v2.repository.selection", "all"),
        Authzd::Proto::Attribute.wrap("authorization_details.v2.repository.permissions", ["metadata:read"])
      ], struct.authzd_proto_attributes)
    end
  end
end
