# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::Structs::V1::PackagesDependencyTest < GitHub::TestCase
  context "#remove_package_permission" do
    test "does nothing without package permissions" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
          "selections" => {
            "repository" => "subset"
          },
          "subject_ids" => {
            "repository" => [42]
          },
          "subject_types_and_actions" => {
            "repository" => {
              "metadata" => 0,
            }
          }
        }
      )

      package = PackageRegistry::PackageSubject.new(id: 42, access_type: :contents)

      assert_no_changes -> { struct.serialize } do
        struct.remove_package_permission(package)
      end
    end

    test "does nothing on other package permissions" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
          "asymmetric" => {
            "package" => {
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
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
          "asymmetric" => {
            "package" => {
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
      assert_equal [98], struct.asymmetric_for(package_resource)["contents"]["read"]
    end

    test "works when access type is a string" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
          "asymmetric" => {
            "package" => {
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
      assert_equal [98], struct.asymmetric_for(package_resource)["contents"]["read"]
    end

    test "removes the subject id when found in administration" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
          "asymmetric" => {
            "package" => {
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
      assert_equal [98], struct.asymmetric_for(package_resource)["administration"]["write"]
    end

    test "does nothing when package has an unexpected access type" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
          "asymmetric" => {
            "package" => {
              "administration" => {
                "write" => [98, 99]
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

    test "clears only empty properties" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
          "asymmetric" => {
            "package" => {
              "contents" => {
                "read" => [99]
              }
            },
            "repository" => {
              "metadata" => {
                "read" => [42]
              }
            }
          }
        }
      )

      expected_struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
          "asymmetric" => {
            "repository" => {
              "metadata" => {
                "read" => [42]
              }
            }
          }
        }
      )

      package = PackageRegistry::PackageSubject.new(id: 99, access_type: :contents)
      struct.remove_package_permission(package)

      assert_same_hash expected_struct.serialize, struct.serialize
    end

    test "clears all the empty properties" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
          "asymmetric" => {
            "package" => {
              "contents" => {
                "read" => [99]
              }
            }
          }
        }
      )

      empty_struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
        }
      )

      package = PackageRegistry::PackageSubject.new(id: 99, access_type: :contents)
      struct.remove_package_permission(package)

      assert_same_hash empty_struct.serialize, struct.serialize
    end

  end
end
