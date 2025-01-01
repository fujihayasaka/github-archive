# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::Structs::V1::TransformationDependencyTest < GitHub::TestCase
  context "transform" do
    test "raises for invalid versions" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new

      assert_raises ArgumentError do
        struct.transform(version: 0)
      end
    end
  end

  context "transform_to_v2" do
    test "transforms a v1 struct to a v2 struct" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
          "selections" => {
            "repository" => "all",
            "organization" => "subset"
          },
          "subject_ids" => {
            "organization" => [42]
          },
          "subject_types_and_actions" => {
            "repository" => {
              "metadata" => 0,
            },
            "organization" => {
              "members" => 0,
            }
          }
        }
      )

      expected = ScopedInstallations::AuthorizationDetails::Structs::V2.new(
        repository: ScopedInstallations::AuthorizationDetails::Structs::V2::SelectionWithPermissions.new(
          selection: ScopedInstallations::AuthorizationDetails::Selection::All,
          permissions: {
            "metadata" => Permission::Action::Read
          }
        ),
        organization: ScopedInstallations::AuthorizationDetails::Structs::V2::SelectionWithPermissions.new(
          selection: [42],
          permissions: {
            "members" => Permission::Action::Read
          }
        )
      )

      assert_same_hash expected.serialize, struct.transform_to_v2.serialize
    end

    test "includes asymmetric access" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
          "selections" => {
            "repository" => "all",
          },
          "subject_types_and_actions" => {
            "repository" => {
              "metadata" => 0,
            },
          },
          "asymmetric" => {
            "repository" => {
              "contents" => {
                "read" => [96],
                "write" => [97]
              }
            }
          }
        }
      )

      expected = ScopedInstallations::AuthorizationDetails::Structs::V2.new(
        repository: ScopedInstallations::AuthorizationDetails::Structs::V2::ElevatedAccessSelection.new(
          selection: ScopedInstallations::AuthorizationDetails::Selection::All,
          permissions: {
            "metadata" => Permission::Action::Read,
            "contents" => {
              Permission::ActionString::Read => [96],
              Permission::ActionString::Write => [97]
            }
          }
        )
      )

      assert_same_hash expected.serialize, struct.transform_to_v2.serialize
    end
  end
end
