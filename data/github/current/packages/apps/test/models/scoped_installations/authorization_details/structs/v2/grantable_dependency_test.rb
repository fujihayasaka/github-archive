# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::Structs::V2::GrantableDependencyTest < GitHub::TestCase
  context "#granted_subject_ids_for" do
    test "returns an empty array when resource has no permissions" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new
      resource = ScopedInstallations::AuthorizationDetails::ResourceType::PackageRegistry

      assert_equal [], struct.granted_subject_ids_for(resource)
    end

    test "returns an empty array when resource does not include the permission" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "package" => {
            "permissions" => {
              "contents" => {
                "read" => [98, 99]
              }
            }
          }
        }
      )

      resource = ScopedInstallations::AuthorizationDetails::ResourceType::PackageRegistry
      assert_equal [], struct.granted_subject_ids_for(resource, "metadata")
    end

    test "returns an empty array when permissions with min_action cannot be found" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "package" => {
            "permissions" => {
              "contents" => {
                "read" => [98, 99]
              }
            }
          }
        }
      )

      resource = ScopedInstallations::AuthorizationDetails::ResourceType::PackageRegistry
      assert_equal [], struct.granted_subject_ids_for(resource, "contents", min_action: :write)
    end

    test "find subject ids on a subject ids only selection" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "package" => {
            "permissions" => {
              "contents" => {
                "read" => [98, 99]
              }
            }
          }
        }
      )

      resource = ScopedInstallations::AuthorizationDetails::ResourceType::PackageRegistry
      assert_equal [98, 99], struct.granted_subject_ids_for(resource, "contents", min_action: :read)
    end

    test "finds subject ids with equal or higher action" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "package" => {
            "permissions" => {
              "contents" => {
                "read" => [98],
                "write" => [99]
              }
            }
          }
        }
      )

      resource = ScopedInstallations::AuthorizationDetails::ResourceType::PackageRegistry
      assert_equal [98, 99], struct.granted_subject_ids_for(resource, "contents", min_action: :read)
    end

    test "finds subject ids on selection with permissions" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "repository" => {
            "selection" => [42],
            "permissions" => {
              "contents" => 0
            }
          }
        }
      )

      resource = ScopedInstallations::AuthorizationDetails::ResourceType::Repository
      assert_equal [42], struct.granted_subject_ids_for(resource, "contents", min_action: :read)
    end

    test "finds subject ids on selection with permissions for any permission" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "repository" => {
            "selection" => ScopedInstallations::AuthorizationDetails::Selection::All,
            "permissions" => {
              "metadata" => {
                "read" => [42]
              },
              "contents" => {
                "read" => [42],
                "write" => [73]
              }
            }
          }
        }
      )

      resource = ScopedInstallations::AuthorizationDetails::ResourceType::Repository
      assert_equal [42, 73], struct.granted_subject_ids_for(resource)
      assert_equal [73], struct.granted_subject_ids_for(resource, "contents", min_action: :write)
    end

    test "finds subject ids on elevated selection" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "repository" => {
            "selection" => "all",
            "permissions" => {
              "metadata" => {
                "read" => {
                  "inherit_selection" => true,
                  "ids" => [231]
                }
              }
            }
          }
        }
      )

      resource = ScopedInstallations::AuthorizationDetails::ResourceType::Repository
      assert_equal [231], struct.granted_subject_ids_for(resource)
    end
  end
end
