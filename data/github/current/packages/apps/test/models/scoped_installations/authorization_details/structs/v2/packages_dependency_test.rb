# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::Structs::V2::PackagesDependencyTest < GitHub::TestCase
  context "#remove_package_permission" do
    test "does nothing without package permissions" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 2,
        }
      )

      package = PackageRegistry::PackageSubject.new(id: 42, access_type: :contents)

      assert_no_changes -> { struct.serialize } do
        struct.remove_package_permission(package)
      end
    end

    test "does nothing on other package permissions" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "package" => {
            "permissions" => {
              "contents" => {
                "read" => [99]
              }
            }
          }
        }
      )

      package = PackageRegistry::PackageSubject.new(id: 42, access_type: :contents)

      assert_no_changes -> { struct.serialize } do
        struct.remove_package_permission(package)
      end
    end

    test "removes the subject id when found in contents" do
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

      package = PackageRegistry::PackageSubject.new(id: 99, access_type: :contents)
      struct.remove_package_permission(package)

      package_resource = ScopedInstallations::AuthorizationDetails::ResourceType::PackageRegistry
      assert_equal [98], struct.granted_subject_ids_for(package_resource, "contents", min_action: :read)
    end

    test "works when access_type is a string" do
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

      package = PackageRegistry::PackageSubject.new(id: 99, access_type: "contents")
      struct.remove_package_permission(package)

      package_resource = ScopedInstallations::AuthorizationDetails::ResourceType::PackageRegistry
      assert_equal [98], struct.granted_subject_ids_for(package_resource, "contents", min_action: :read)
    end

    test "removes the subject id when found in administration" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "package" => {
            "permissions" => {
              "administration" => {
                "write" => [98, 99]
              }
            }
          }
        }
      )

      package = PackageRegistry::PackageSubject.new(id: 99, access_type: :administration)
      struct.remove_package_permission(package)

      package_resource = ScopedInstallations::AuthorizationDetails::ResourceType::PackageRegistry
      assert_equal [98], struct.granted_subject_ids_for(package_resource, "administration", min_action: :write)
    end

    test "does nothing when package has an unexpected access type" do
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

      package = PackageRegistry::PackageSubject.new(id: 99, access_type: :unexpected)

      assert_no_changes -> { struct.serialize } do
        struct.remove_package_permission(package)
      end
    end

    test "clears empty permission" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "repository" => {
            "selection" => [42],
            "permissions" => {
              "metadata" => 0
            }
          },
          "package" => {
            "permissions" => {
              "contents" => {
                "read" => [99]
              },
              "administration" => {
                "write" => [101]
              }
            }
          }
        }
      )

      expected_struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "repository" => {
            "selection" => [42],
            "permissions" => {
              "metadata" => 0
            }
          },
          "package" => {
            "permissions" => {
              "administration" => {
                "write" => [101]
              }
            }
          }
        }
      )

      package = PackageRegistry::PackageSubject.new(id: 99, access_type: :contents)
      struct.remove_package_permission(package)

      assert_same_hash expected_struct.serialize, struct.serialize
    end

    test "clears empty resource" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "package" => {
            "permissions" => {
              "contents" => {
                "read" => [99]
              }
            }
          }
        }
      )

      expected_struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
        }
      )

      package = PackageRegistry::PackageSubject.new(id: 99, access_type: :contents)
      struct.remove_package_permission(package)

      assert_same_hash expected_struct.serialize, struct.serialize
    end
  end
end
