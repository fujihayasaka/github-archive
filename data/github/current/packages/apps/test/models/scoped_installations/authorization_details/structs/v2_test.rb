# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::Structs::V2Test < GitHub::TestCase
  def resource_type_for(name)
    ::ScopedInstallations::AuthorizationDetails::ResourceType.for(name)
  end

  context ".from_hash" do
    test "string selection with permissions hash" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash({
        "version" => 2,
        "organization" => {
          "selection" => "global",
          "permissions" => {
            "members" => 0
          }
        }
      })

      assert_kind_of(ScopedInstallations::AuthorizationDetails::Structs::V2::SelectionWithPermissions, struct.organization)

      assert_kind_of(ScopedInstallations::AuthorizationDetails::Selection, T.must(struct.organization).selection)
      assert_same_hash({ "members" => Permission::Action::Read }, T.must(T.must(struct.organization).permissions))
    end

    test "array selection with permissions hash" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash({
        "version" => 2,
        "organization" => {
          "selection" => [9919],
          "permissions" => {
            "members" => 0
          }
        }
      })

      assert_kind_of(ScopedInstallations::AuthorizationDetails::Structs::V2::SelectionWithPermissions, struct.organization)

      assert_same_elements([9919], T.must(struct.organization).selection)
      assert_same_hash({ "members" => Permission::Action::Read }, T.must(T.must(struct.organization).permissions))
    end

    test "transforms action strings into the appropriate enum" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash({
        "version" => 2,
        "repository" => {
          "selection" => "all",
          "permissions" => {
            "metadata" => {
              "read" => "inherit_selection"
            }
          }
        }
      })

      assert_kind_of(ScopedInstallations::AuthorizationDetails::Structs::V2::ElevatedAccessSelection, struct.repository)

      metadata_access = T.must(T.must(struct.repository).permissions["metadata"])

      # This is due to Sorbet's inability to understand type check control flows except for case statements.
      case metadata_access
      when Hash
        assert_same_elements([Permission::ActionString::Read], metadata_access.keys)
      else
        assert_kind_of(Hash, metadata_access)
      end
    end

    test "transforms inherit_selection with subject ids into a InheritSelectionWithIds struct" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash({
        "version" => 2,
        "repository" => {
          "selection" => "all",
          "permissions" => {
            "metadata" => {
              "read" => {
                "inherit_selection" => true,
                "ids" => [88]
              }
            }
          }
        }
      })

      assert_kind_of(ScopedInstallations::AuthorizationDetails::Structs::V2::ElevatedAccessSelection, struct.repository)

      metadata_access = T.must(T.must(struct.repository).permissions["metadata"])

      # This is due to Sorbet's inability to understand type check control flows except for case statements.
      case metadata_access
      when Hash
        assert_same_elements([Permission::ActionString::Read], metadata_access.keys)

        value = metadata_access[Permission::ActionString::Read]

        case value
        when ScopedInstallations::AuthorizationDetails::Structs::V2::InheritSelectionWithIds
          assert_same_elements([88], value.ids)
        else
          assert_kind_of(ScopedInstallations::AuthorizationDetails::Structs::V2::InheritSelectionWithIds, metadata_access)
        end
      else
        assert_kind_of(Hash, metadata_access)
      end
    end
  end

  context "#all_permissions" do
    test "returns the expected hash of string resource and symbol actions" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new(
        repository: ScopedInstallations::AuthorizationDetails::Structs::V2::SelectionWithPermissions.new(
          selection: ScopedInstallations::AuthorizationDetails::Selection::All,
          permissions: {
            "metadata" => Permission::Action::Read,
            "contents" => Permission::Action::Write
          }
        )
      )

      assert_same_hash({ "metadata" => :read, "contents" => :write }, struct.all_permissions)
    end

    test "collects the highest action per resource" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new(
        repository: ScopedInstallations::AuthorizationDetails::Structs::V2::ElevatedAccessSelection.new(
          selection: ScopedInstallations::AuthorizationDetails::Selection::All,
          permissions: {
            "metadata" => Permission::Action::Read,
            "contents" => {
              Permission::ActionString::Read => "inherit_selection",
              Permission::ActionString::Write => [42]
            }
          }
        )
      )

      assert_same_hash({ "metadata" => :read, "contents" => :write }, struct.all_permissions)
    end

    context "selection type support" do
      test "selection with permissions" do
        struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new(
          repository: ScopedInstallations::AuthorizationDetails::Structs::V2::SelectionWithPermissions.new(
            selection: ScopedInstallations::AuthorizationDetails::Selection::All,
            permissions: {
              "metadata" => Permission::Action::Read,
              "contents" => Permission::Action::Write
            }
          )
        )

        assert_same_hash({ "metadata" => :read, "contents" => :write }, struct.all_permissions)
      end

      test "subject ids only" do
        struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new(
          package: ScopedInstallations::AuthorizationDetails::Structs::V2::SubjectIdsOnlySelection.new(
            permissions: {
              "maintainer" => {
                Permission::ActionString::Read => [2239385]
              }
            }
          )
        )

        assert_same_hash({ "maintainer" => :read }, struct.all_permissions)
      end

      test "elevated access" do
        struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new(
          repository: ScopedInstallations::AuthorizationDetails::Structs::V2::ElevatedAccessSelection.new(
            selection: [3],
            permissions: {
              "metadata" => Permission::Action::Read,
              "contents" => {
                Permission::ActionString::Read => "inherit_selection",
                Permission::ActionString::Write => [42]
              },
              "actions" => {
                Permission::ActionString::Write => [1, 2]
              },
              "administration" => {
                Permission::ActionString::Read => ScopedInstallations::AuthorizationDetails::Structs::V2::InheritSelectionWithIds.new(
                  ids: [88]
                ),
                Permission::ActionString::Write => [42]
              }
            }
          )
        )

        assert_same_hash({ "metadata" => :read, "contents" => :write, "actions" => :write, "administration" => :write }, struct.all_permissions)
      end
    end
  end

  test "#serialize" do
    struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new(
      codespace: ScopedInstallations::AuthorizationDetails::Structs::V2::SelectionWithPermissions.new(
        selection: [8675309],
        permissions: {
          "codespace_metadata" => Permission::Action::Read
        }
      ),
      repository: ScopedInstallations::AuthorizationDetails::Structs::V2::ElevatedAccessSelection.new(
        selection: ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: {
          "metadata" => Permission::Action::Read,
          "contents" => {
            Permission::ActionString::Read => "inherit_selection",
            Permission::ActionString::Write => ScopedInstallations::AuthorizationDetails::Structs::V2::InheritSelectionWithIds.new(ids: [42])
          },
          "actions" => Permission::Action::Admin,
          "administration" => {
            Permission::ActionString::Read => [98]
          }
        }
      ),
      package: ScopedInstallations::AuthorizationDetails::Structs::V2::SubjectIdsOnlySelection.new(
        permissions: {
          "maintainer" => {
            Permission::ActionString::Read => [2239385]
          }
        }
      )
    )

    assert_same_hash({
      "version" => 2,
      "codespace" => {
        "selection" => [8675309],
        "permissions" => {
          "codespace_metadata" => 0
        }
      },
      "repository" => {
        "selection" => "all",
        "permissions" => {
          "metadata" => 0,
          "contents" => {
            "read" => "inherit_selection",
            "write" => {
              "inherit_selection" => true,
              "ids" => [42]
            }
          },
          "actions" => 2,
          "administration" => {
            "read" => [98]
          }
        }
      },
      "package" => {
        "permissions" => {
          "maintainer" => {
            "read" => [2239385]
          }
        }
      }
    }, struct.serialize)
  end

  context "#add_permissions_selection" do
    test "does not set anything without permissions" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: {},
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All
      )

      assert_nil struct.repository
    end

    test "adds a resource with resource type, permissions and selection" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read },
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All
      )

      expected_hash = {
        "version" => 2,
        "repository" => {
          "selection" => "all",
          "permissions" => {
            "metadata" => 0
          }
        }
      }

      assert_same_hash expected_hash, struct.serialize
    end

    test "combines multiple permissions in the same resource for an All selection" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read },
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All
      )

      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "contents" => :write },
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All
      )

      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "contents" => :read, "issues" => :read },
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All
      )

      expected_hash = {
        "version" => 2,
        "repository" => {
          "selection" => "all",
          "permissions" => {
            "metadata" => 0,
            "contents" => 1,
            "issues" => 0
          }
        }
      }

      assert_same_hash expected_hash, struct.serialize
    end

    test "adds permissions for a subset of subject ids" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read, "contents" => :write },
        selection: [42, 73]
      )

      expected_hash = {
        "version" => 2,
        "repository" => {
          "selection" => [42, 73],
          "permissions" => {
            "metadata" => 0,
            "contents" => 1
          }
        }
      }

      assert_same_hash expected_hash, struct.serialize
    end

    test "combines multiple permissions for same subset of subject ids" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read, "contents" => :write },
        selection: [42, 73]
      )

      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read, "issues" => :read },
        selection: [73, 42]
      )

      expected_hash = {
        "version" => 2,
        "repository" => {
          "selection" => [42, 73],
          "permissions" => {
            "metadata" => 0,
            "contents" => 1,
            "issues" => 0
          }
        }
      }

      assert_same_hash expected_hash, struct.serialize
    end

    test "adds multiple resources with single selections" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read },
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All
      )

      struct.add_permissions_selection(
        resource_type: resource_type_for("Organization"),
        permissions: { "organization_packages" => :read },
        selection: [88]
      )

      expected_hash = {
        "version" => 2,
        "repository" => {
          "selection" => "all",
          "permissions" => {
            "metadata" => 0
          }
        },
        "organization" => {
          "selection" => [88],
          "permissions" => {
            "organization_packages" => 0
          }
        }
      }

      assert_same_hash expected_hash, struct.serialize
    end

    test "adds elevated permissions on the same resource" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read },
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All
      )

      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read },
        selection: [42]
      )

      expected_hash = {
        "version" => 2,
        "repository" => {
          "selection" => "all",
          "permissions" => {
            "metadata" => {
              "read" => {
                "inherit_selection" => true,
                "ids" => [42]
              }
            }
          }
        }
      }

      assert_same_hash expected_hash, struct.serialize
    end

    test "merges elevated permissions on the same resource" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read },
        selection: [42]
      )

      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read, "contents" => :write },
        selection: [73]
      )

      expected_hash = {
        "version" => 2,
        "repository" => {
          "selection" => [42],
          "permissions" => {
            "metadata" => {
              "read" => {
                "inherit_selection" => true,
                "ids" => [73]
              }
            },
            "contents" => {
              "write" => [73]
            }
          }
        }
      }

      assert_same_hash expected_hash, struct.serialize
    end

    test "adds subject ids only selections" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read },
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All
      )

      struct.add_permissions_selection(
        resource_type: resource_type_for("Package"),
        permissions: { "administration" => :write },
        selection: [42]
      )

      struct.add_permissions_selection(
        resource_type: resource_type_for("workflow_run"),
        permissions: { "reachability_analysis" => :write },
        selection: [42]
      )

      expected_hash = {
        "version" => 2,
        "repository" => {
          "selection" => "all",
          "permissions" => {
            "metadata" => 0
          }
        },
        "package" => {
          "permissions" => {
            "administration" => {
              "write" => [42]
            },
          },
        },
        "workflow_run" => {
          "permissions" => {
            "reachability_analysis" => {
              "write" => [42]
            }
          }
        }
      }

      assert_same_hash expected_hash, struct.serialize
    end
  end

  context "#explicitly_grants_permission?" do
    test "checks permissions on a resource with All selection" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "repository" => {
            "selection" => "all",
            "permissions" => {
              "metadata" => {
                "read" => {
                  "inherit_selection" => true,
                  "ids" => [42]
                }
              }
            }
          }
        }
      )

      refute struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All,
        resource: "metadata",
        action: :write # Only read was granted
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All,
        resource: "metadata",
        action: :read
      )
    end

    test "checks permissions on a resource with subset selection" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "repository" => {
            "selection" => [42, 73],
            "permissions" => {
              "metadata" => {
                "read" => {
                  "inherit_selection" => true,
                  "ids" => [1088]
                }
              }
            }
          },
          "organization" => {
            "selection" => [88],
            "permissions" => {
              "organization_packages" => 0
            }
          }
        }
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [42],
        resource: "metadata",
        action: :read
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [73, 42],
        resource: "metadata",
        action: :read
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [1088],
        resource: "metadata",
        action: :read
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Organization"),
        selection: [88],
        resource: "organization_packages",
        action: :read
      )
    end

    test "checks Global selection" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "repository" => {
            "selection" => "global",
            "permissions" => {
              "metadata" => 0
            }
          }
        }
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ScopedInstallations::AuthorizationDetails::Selection::Global,
        resource: "metadata",
        action: :read
      )
    end

    test "checks Parent selection" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash(
        {
          "version" => 2,
          "repository" => {
            "selection" => "parent",
            "permissions" => {
              "metadata" => 0
            }
          }
        }
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ScopedInstallations::AuthorizationDetails::Selection::Global,
        resource: "metadata",
        action: :read
      )
    end
  end

end
