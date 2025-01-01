# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::Structs::V1Test < GitHub::TestCase
  test "#all_permissions combines subject types and actions with asymmetric" do
    struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
      subject_types_and_actions: {
        ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
          "metadata" => Permission::Action::Read,
          "contents" => Permission::Action::Read,
        },
        ::ScopedInstallations::AuthorizationDetails::ResourceType::Organization => {
          "members" => Permission::Action::Read
        },
      },
      asymmetric: {
        ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
          "contents" => {
            "write" => [1, 2]
          }
        },
        ::ScopedInstallations::AuthorizationDetails::ResourceType::Organization => {
          "administration" => {
            "read" => [42]
          }
        }
      }
    )

    expected = {
      "metadata" => :read,
      "contents" => :write,
      "members" => :read,
      "administration" => :read,
    }

    assert_same_hash(expected, struct.all_permissions)
  end

  def resource_type_for(name)
    ::ScopedInstallations::AuthorizationDetails::ResourceType.for(name)
  end

  context "#selection_for" do
    test "returns the selection for the given resource type" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        selections: {
          ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ::ScopedInstallations::AuthorizationDetails::Selection::All
        },
      )

      expected = ::ScopedInstallations::AuthorizationDetails::Selection::All
      assert_equal expected, struct.selection_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end

    test "returns None by default" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new

      expected = ::ScopedInstallations::AuthorizationDetails::Selection::None
      assert_equal expected, struct.selection_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end
  end

  context "#set_selection_for" do
    test "sets the selection for the given resource type" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new
      struct.set_selection_for(
        ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository,
        ::ScopedInstallations::AuthorizationDetails::Selection::All
      )

      expected = ::ScopedInstallations::AuthorizationDetails::Selection::All
      assert_equal expected, struct.selection_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end

    test "overwrites the selection for the given resource type" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        selections: {
          ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ::ScopedInstallations::AuthorizationDetails::Selection::All
        }
      )

      expected = ::ScopedInstallations::AuthorizationDetails::Selection::All
      assert_equal expected, struct.selection_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)

      struct.set_selection_for(
        ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository,
        ::ScopedInstallations::AuthorizationDetails::Selection::Subset
      )

      expected = ::ScopedInstallations::AuthorizationDetails::Selection::Subset
      assert_equal expected, struct.selection_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end
  end

  context "#subject_ids_for" do
    test "returns the subject ids for the given resource type" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        subject_ids: {
          ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [42]
        },
      )

      expected = [42]
      assert_equal expected, struct.subject_ids_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end

    test "returns an empty array by default" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new
      assert_empty struct.subject_ids_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end
  end

  context "#set_subject_ids_for" do
    test "sets the subject ids for the given resource type" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new
      struct.set_subject_ids_for(
        ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository, [42]
      )

      expected = [42]
      assert_equal expected, struct.subject_ids_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end

    test "overwrites the subject ids for the given resource type" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        subject_ids: {
          ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [42]
        }
      )

      assert_equal [42], struct.subject_ids_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)

      struct.set_subject_ids_for(
        ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository, [43]
      )

      assert_equal [43], struct.subject_ids_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end
  end

  context "#subject_types_and_actions_for" do
    test "returns the subject types and actions for the given resource type" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        subject_types_and_actions: {
          ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "metadata" => Permission::Action::Read
          }
        },
      )

      expected = { "metadata" => Permission::Action::Read }
      assert_same_hash expected, struct.subject_types_and_actions_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end

    test "returns an empty hash by default" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new
      assert_empty struct.subject_types_and_actions_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end
  end

  context "#set_subject_types_and_actions_for" do
    test "sets the subject types and actions for the given resource type" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new

      struct.set_subject_types_and_actions_for(
        ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository, {
          "metadata" => :read
        }
      )

      expected = { "metadata" => Permission::Action::Read }
      assert_same_hash expected, struct.subject_types_and_actions_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end

    test "overwrites the subject types and actions for the given resource type" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        subject_types_and_actions: {
          ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "metadata" => Permission::Action::Read
          }
        }
      )

      expected = { "metadata" => Permission::Action::Read }
      assert_same_hash expected, struct.subject_types_and_actions_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)

      struct.set_subject_types_and_actions_for(
        ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository, { "contents" => :read }
      )

      expected = { "contents" => Permission::Action::Read }
      assert_same_hash expected, struct.subject_types_and_actions_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end
  end

  context "#asymmetric_for" do
    test "returns the asymmetric subject types and actions for the given resource type" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        asymmetric: {
          ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "contents" => { "read" => [1, 2] }
          }
        }
      )

      expected = { "contents" => { "read" => [1, 2] } }
      assert_same_hash expected, struct.asymmetric_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end

    test "returns an empty hash by default" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new
      assert_empty struct.asymmetric_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end
  end

  context "#set_asymmetric_for" do
    test "sets the asymmetric subject types and actions for the given resource type" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new

      struct.set_asymmetric_for(
        ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "contents", "read", [1, 2]
      )

      expected = { "contents" => { "read" => [1, 2] } }
      assert_same_hash expected, struct.asymmetric_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end

    test "merges subject ids if already set for the permission and action" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        asymmetric: {
          ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "contents" => { "read" => [1, 2] }
          }
        }
      )

      struct.set_asymmetric_for(
        ::ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "contents", "read", [3, 4]
      )

      expected = { "contents" => { "read" => [1, 2, 3, 4] } }
      assert_same_hash expected, struct.asymmetric_for(::ScopedInstallations::AuthorizationDetails::ResourceType::Repository)
    end
  end

  context "#add_permissions_selection" do
    test "does not set anything without permissions" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: {},
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All
      )

      assert_nil struct.selections
      assert_nil struct.subject_types_and_actions
    end

    test "adds a resource with resource type, permissions and selection" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read },
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All
      )

      expected_hash = {
        "version" => 1,
        "selections" => {
          "repository" => "all"
        },
        "subject_types_and_actions" => {
          "repository" => {
            "metadata" => 0,
          }
        }
      }

      assert_same_hash expected_hash, struct.serialize
    end

    test "combines multiple permissions under the same resource when selecting all" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new
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

      expected_hash = {
        "version" => 1,
        "selections" => {
          "repository" => "all"
        },
        "subject_types_and_actions" => {
          "repository" => {
            "contents" => 1,
            "metadata" => 0,
          }
        }
      }

      assert_same_hash expected_hash, struct.serialize
    end

    test "combines multiple permissions under the same resource when same subset" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read },
        selection: [42, 73]
      )
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "contents" => :write },
        selection: [73, 42]
      )

      expected_hash = {
        "version" => 1,
        "selections" => {
          "repository" => "subset"
        },
        "subject_ids" => {
          "repository" => [42, 73]
        },
        "subject_types_and_actions" => {
          "repository" => {
            "contents" => 1,
            "metadata" => 0,
          }
        }
      }

      assert_same_hash expected_hash, struct.serialize
    end

    test "adds specific permission selection into asymmetric" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read },
        selection: [42]
      )

      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "contents" => :write },
        selection: [37, 73]
      )

      expected_hash = {
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
        },
        "asymmetric" => {
          "repository" => {
            "contents" => {
              "write" => [37, 73]
            }
          }
        }
      }

      assert_same_hash expected_hash, struct.serialize
    end

    test "combines specific permission selections into asymmetric" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read },
        selection: [42]
      )

      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "contents" => :write },
        selection: [37, 73]
      )

      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "contents" => :read, "issues" => :read },
        selection: [99]
      )

      expected_hash = {
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
        },
        "asymmetric" => {
          "repository" => {
            "contents" => {
              "write" => [37, 73],
              "read" => [99]
            },
            "issues" => {
              "read" => [99]
            }
          }
        }
      }

      assert_same_hash expected_hash, struct.serialize
    end

    test "sets asymmetric resource types correctly" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new
      struct.add_permissions_selection(
        resource_type: resource_type_for("Repository"),
        permissions: { "metadata" => :read },
        selection: [42]
      )

      struct.add_permissions_selection(
        resource_type: resource_type_for("Package"),
        permissions: { "administration" => :write },
        selection: [73]
      )

      struct.add_permissions_selection(
        resource_type: resource_type_for("protected_branch"),
        permissions: { "contents" => :write },
        selection: [1001]
      )

      expected_hash = {
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
        },
        "asymmetric" => {
          "package" => {
            "administration" => {
              "write" => [73],
            },
          },
          "protected_branch" => {
            "contents" => {
              "write" => [1001],
            }
          }
        }
      }

      assert_same_hash expected_hash, struct.serialize
    end
  end

  context "#explicitly_grants_permission?" do
    test "checks permissions on All selection" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
          "selections" => {
            "repository" => "all"
          },
          "subject_types_and_actions" => {
            "repository" => {
              "contents" => 1,
              "metadata" => 0,
            }
          }
        }
      )

      refute struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::None,
        resource: "contents",
        action: :write
      )

      refute struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [42], # Although details have :all selection, this subject id is included explicitly
        resource: "contents",
        action: :write
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All,
        resource: "contents",
        action: :write
      )

      refute struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All,
        resource: "contents",
        action: :read # it has explicit write, not read
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All,
        resource: "metadata",
        action: :read
      )
    end

    test "checks permissions on Global selection" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
          "selections" => {
            "repository" => "global"
          },
          "subject_types_and_actions" => {
            "repository" => {
              "contents" => 1,
              "metadata" => 0,
            }
          }
        }
      )

      refute struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::None,
        resource: "contents",
        action: :write
      )

      refute struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [42], # Although details have :global selection, this subject id is included explicitly
        resource: "contents",
        action: :write
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::Global,
        resource: "contents",
        action: :write
      )

      refute struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::Global,
        resource: "contents",
        action: :read # it has explicit write, not read
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::Global,
        resource: "metadata",
        action: :read
      )
    end

    test "checks permissions on Parent selection" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        {
          "version" => 1,
          "selections" => {
            "repository" => "parent"
          },
          "subject_types_and_actions" => {
            "repository" => {
              "contents" => 1,
              "metadata" => 0,
            }
          }
        }
      )

      refute struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::None,
        resource: "contents",
        action: :write
      )

      refute struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [42], # Although details have :parent selection, this subject id is included explicitly
        resource: "contents",
        action: :write
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::Parent,
        resource: "contents",
        action: :write
      )

      refute struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::Parent,
        resource: "contents",
        action: :read # it has explicit write, not read
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::Parent,
        resource: "metadata",
        action: :read
      )
    end

    test "checks permission on subsets" do
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
              "contents" => 0,
            }
          },
          "asymmetric" => {
            "repository" => {
              "contents" => {
                "write" => [37, 73],
                "read" => [99]
              },
              "issues" => {
                "read" => [99]
              }
            }
          }
        }
      )

      refute struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [],
        resource: "metadata",
        action: :read
      )

      refute struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All,
        resource: "metadata",
        action: :read
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [42],
        resource: "metadata",
        action: :read
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [37],
        resource: "contents",
        action: :write
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [73, 37],
        resource: "contents",
        action: :write
      )

      assert struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [42, 99],
        resource: "contents",
        action: :read
      )

      refute struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [42, 99, 1001],
        resource: "contents",
        action: :read
      )

      refute struct.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [73, 37],
        resource: "issues",
        action: :write # it has read, not write
      )
    end
  end
end
