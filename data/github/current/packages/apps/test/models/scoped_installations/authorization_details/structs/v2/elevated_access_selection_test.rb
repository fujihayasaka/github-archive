# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::Structs::V2::ElevatedAccessSelectionTest < GitHub::TestCase
  def elevated_access_selection(selection:, permissions:)
    ScopedInstallations::AuthorizationDetails::Structs::V2::ElevatedAccessSelection.new(selection:, permissions:)
  end

  context "#granted_access_on_all_subjects" do
    test "resource is granted via an action" do
      selection = elevated_access_selection(
        selection: ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      assert_equal Permission::Action::Read, selection.granted_access_on_all_subjects("metadata")
    end

    test "resource is granted via inheritance" do
      selection = elevated_access_selection(
        selection: ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: {
          "contents" => {
            Permission::ActionString::Read => "inherit_selection",
            Permission::ActionString::Write => [42]
          }
        }
      )

      assert_equal Permission::Action::Read, selection.granted_access_on_all_subjects("contents")
    end

    test "resource is granted with unknown string value" do
      selection = elevated_access_selection(
        selection: ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: {
          "contents" => {
            Permission::ActionString::Read => "INVALID",
            Permission::ActionString::Write => [42]
          }
        }
      )

      assert_nil selection.granted_access_on_all_subjects("contents")
    end

    test "resource is granted via inheritance with ids object" do
      selection = elevated_access_selection(
        selection: ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: {
          "contents" => {
            Permission::ActionString::Read => ScopedInstallations::AuthorizationDetails::Structs::V2::InheritSelectionWithIds.new(ids: [42])
          }
        }
      )

      assert_equal Permission::Action::Read, selection.granted_access_on_all_subjects("contents")
    end

    test "resource is not granted" do
      selection = elevated_access_selection(
        selection: ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      assert_nil selection.granted_access_on_all_subjects("contents")
    end

    test "selection is an array" do
      selection = elevated_access_selection(
        selection: [],
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      assert_nil selection.granted_access_on_all_subjects("metadata")
    end

    test "resource is granted with ids only" do
      selection = elevated_access_selection(
        selection: ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: {
          "metadata" => Permission::Action::Read,
          "contents" => {
            Permission::ActionString::Read => [42]
          }
        }
      )

      assert_nil selection.granted_access_on_all_subjects("contents")
    end

    test "chooses the highest action" do
      struct = elevated_access_selection(
        selection: ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: {
          "contents" => {
            Permission::ActionString::Read => ScopedInstallations::AuthorizationDetails::Structs::V2::InheritSelectionWithIds.new(ids: [42]),
            Permission::ActionString::Write => ScopedInstallations::AuthorizationDetails::Structs::V2::InheritSelectionWithIds.new(ids: [52]),
          }
        }
      )

      assert_equal Permission::Action::Write, struct.granted_access_on_all_subjects("contents")
    end
  end

  context "#granted_subject_ids_with_actions_for" do
    context "all selection" do
      test "granted access via action" do
        selection = elevated_access_selection(
          selection: ScopedInstallations::AuthorizationDetails::Selection::All,
          permissions: {
            "metadata" => Permission::Action::Read,
          }
        )

        assert_empty(selection.granted_subject_ids_with_actions_for("metadata", [1]))
      end

      test "granted access via action with ids" do
        selection = elevated_access_selection(
          selection: ScopedInstallations::AuthorizationDetails::Selection::All,
          permissions: {
            "metadata" => Permission::Action::Read,
            "contents" => {
              Permission::ActionString::Read => [2]
            }
          }
        )

        assert_same_elements([[2, 0]], selection.granted_subject_ids_with_actions_for("contents", [1, 2]))
      end

      test "granted access via inheritance" do
        selection = elevated_access_selection(
          selection: ScopedInstallations::AuthorizationDetails::Selection::All,
          permissions: {
            "metadata" => Permission::Action::Read,
            "contents" => {
              Permission::ActionString::Read => "inherit_selection"
            }
          }
        )

        assert_empty(selection.granted_subject_ids_with_actions_for("contents", [1]))
      end

      test "granted access via inheritance with ids" do
        selection = elevated_access_selection(
          selection: ScopedInstallations::AuthorizationDetails::Selection::All,
          permissions: {
            "contents" => {
              Permission::ActionString::Read => ScopedInstallations::AuthorizationDetails::Structs::V2::InheritSelectionWithIds.new(ids: [2])
            }
          }
        )

        assert_same_elements([[2, 0]], selection.granted_subject_ids_with_actions_for("contents", [2]))
      end
    end

    context "subset selection" do
      test "accesss granted via action" do
        selection = elevated_access_selection(
          selection: [1],
          permissions: {
            "metadata" => Permission::Action::Read,
          }
        )

        assert_same_elements([[1, 0]], selection.granted_subject_ids_with_actions_for("metadata", [1]))
      end

      test "filters based on subject ids provided" do
        selection = elevated_access_selection(
          selection: [1, 2, 3],
          permissions: {
            "metadata" => Permission::Action::Read,
          }
        )

        assert_same_elements([[1, 0]], selection.granted_subject_ids_with_actions_for("metadata", [1]))
      end

      test "returns nothing if the permission isn't granted" do
        selection = elevated_access_selection(
          selection: [1],
          permissions: {
            "metadata" => Permission::Action::Read,
          }
        )

        assert_empty selection.granted_subject_ids_with_actions_for("contents", [1])
      end

      test "does not include original subset if permission is has its own" do
        selection = elevated_access_selection(
          selection: [1],
          permissions: {
            "contents" => {
              Permission::ActionString::Read => [2]
            }
          }
        )

        assert_same_elements([[2, 0]], selection.granted_subject_ids_with_actions_for("contents", [1, 2]))
      end

      test "includes original subset if permission is inherited with ids" do
        selection = elevated_access_selection(
          selection: [1],
          permissions: {
            "contents" => {
              Permission::ActionString::Read => ScopedInstallations::AuthorizationDetails::Structs::V2::InheritSelectionWithIds.new(ids: [2])
            }
          }
        )

        assert_same_elements([[1, 0], [2, 0]], selection.granted_subject_ids_with_actions_for("contents", [1, 2]))
      end

      test "includes original subset if permission is inherited" do
        selection = elevated_access_selection(
          selection: [1],
          permissions: {
            "contents" => {
              Permission::ActionString::Read => "inherit_selection"
            }
          }
        )

        assert_same_elements([[1, 0]], selection.granted_subject_ids_with_actions_for("contents", [1]))
      end

      test "does not include original subset if granted with invalid string" do
        selection = elevated_access_selection(
          selection: [1],
          permissions: {
            "contents" => {
              Permission::ActionString::Read => "INVALID"
            }
          }
        )

        assert_empty selection.granted_subject_ids_with_actions_for("contents", [1])
      end
    end

    test "returns the highest permission for the subject" do
      selection = elevated_access_selection(
        selection: [1, 2, 3],
        permissions: {
          "contents" => {
            Permission::ActionString::Read => "inherit_selection",
            Permission::ActionString::Write => ScopedInstallations::AuthorizationDetails::Structs::V2::InheritSelectionWithIds.new(ids: [2]),
            Permission::ActionString::Admin => [3]
          }
        }
      )

      assert_same_elements([
        [1, 1], [2, 1], [3, 2]
      ], selection.granted_subject_ids_with_actions_for("contents", [1, 2, 3]))
    end
  end

  context "#custom_selected" do
    test "returns the same selection if it is all" do
      selection = elevated_access_selection(
        selection: ::ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: {}
      )

      assert_equal [1, 2, 3], selection.custom_selected([1, 2, 3])
    end

    test "returns the elements not present in the resource selection" do
      selection = elevated_access_selection(
        selection: [1, 2, 3],
        permissions: {}
      )

      assert_equal [4], selection.custom_selected([3, 4])
    end

    test "returns an empty array if all elements are in the selection" do
      selection = elevated_access_selection(
        selection: [1, 2, 3],
        permissions: {}
      )

      assert_empty selection.custom_selected([1, 2, 3])
    end
  end

  context "#add_permissions_selection" do
    test "adds new permissions and action for fully inherited selections" do
      selection = elevated_access_selection(
        selection: [1, 2, 3], permissions: {}
      )

      selection.add_permissions_selection(
        permissions: { "metadata" => :read },
        selection: [1, 2, 3]
      )

      assert_equal Permission::Action::Read, selection.permissions["metadata"]
    end

    test "adds new permissions and action for fully custom selections" do
      selection = elevated_access_selection(
        selection: [1, 2], permissions: {}
      )

      selection.add_permissions_selection(
        permissions: { "metadata" => :read },
        selection: [42, 73]
      )

      assert_same_hash({ Permission::ActionString::Read => [42, 73] }, selection.permissions["metadata"])
    end

    test "adds new permissions and action for partially inherited custom selections" do
      selection = elevated_access_selection(
        selection: [1, 2], permissions: {}
      )

      selection.add_permissions_selection(
        permissions: { "metadata" => :read },
        selection: [2, 3, 4]
      )

      action_value = selection.permissions["metadata"][Permission::ActionString::Read]

      assert action_value.inherit_selection
      assert_equal [3, 4], action_value.ids
    end

    test "merging permissions into All selection inherited and custom ones" do
      selection = elevated_access_selection(
        selection: ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: { "contents" => Permission::Action::Write }
      )

      selection.add_permissions_selection(
        permissions: { "metadata" => :read, "contents" => :read },
        selection: [42]
      )

      assert_equal [42], selection.permissions["metadata"][Permission::ActionString::Read]
      assert_equal [42], selection.permissions["contents"][Permission::ActionString::Read]

      assert_equal "inherit_selection", selection.permissions["contents"][Permission::ActionString::Write]
    end

    test "adds new permissions alongside existing ones" do
      selection = elevated_access_selection(
        selection: [1, 2], permissions: { "metadata" => Permission::Action::Read }
      )

      selection.add_permissions_selection(
        permissions: { "contents" => :read },
        selection: [3, 4]
      )

      assert_equal Permission::Action::Read, selection.permissions["metadata"]
      assert_same_hash({ Permission::ActionString::Read => [3, 4] }, selection.permissions["contents"])
    end

    test "merges new permissions into fully custom selections" do
      selection = elevated_access_selection(
        selection: [1, 2],
        permissions: {
          "metadata" => {
            Permission::ActionString::Read => [42],
          }
        }
      )

      selection.add_permissions_selection(
        permissions: { "metadata" => :read },
        selection: [73]
      )

      assert_same_hash({ Permission::ActionString::Read => [42, 73] }, selection.permissions["metadata"])
    end

    test "detects inheritance when merging permissions" do
      selection = elevated_access_selection(
        selection: [42],
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      selection.add_permissions_selection(
        permissions: { "metadata" => :read },
        selection: [73]
      )

      assert_instance_of(
        ScopedInstallations::AuthorizationDetails::Structs::V2::InheritSelectionWithIds,
        selection.permissions["metadata"][Permission::ActionString::Read]
      )

      assert_equal [73], selection.permissions["metadata"][Permission::ActionString::Read].ids
    end

    test "merges new permissions into partially inherited selections" do
      inherit_selection = ::ScopedInstallations::AuthorizationDetails::Structs::V2::InheritSelectionWithIds.new(
        ids: [42]
      )
      action = Permission::ActionString::Read

      selection = elevated_access_selection(
        selection: [1, 2],
        permissions: {
          "metadata" => {
            action => inherit_selection
          }
        }
      )

      selection.add_permissions_selection(
        permissions: { "metadata" => :read },
        selection: [1, 73]
      )

      assert_same_elements [42, 73], selection.permissions["metadata"][action].ids
    end

    test "merges new permissions into inherited selection actions" do
      action = Permission::ActionString::Read

      selection = elevated_access_selection(
        selection: [42],
        permissions: {
          "metadata" => {
            Permission::ActionString::Read => "inherit_selection",
            Permission::ActionString::Write => [88],
          }
        }
      )

      selection.add_permissions_selection(
        permissions: { "metadata" => :read },
        selection: [73]
      )

      assert_equal [88], selection.permissions["metadata"][Permission::ActionString::Write]

      action_value = selection.permissions["metadata"][Permission::ActionString::Read]

      assert action_value.inherit_selection
      assert_equal [73], action_value.ids
    end

    test "merges new permissions into fully inherited selections" do
      selection = elevated_access_selection(
        selection: [1, 2],
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      selection.add_permissions_selection(
        permissions: { "contents" => :write },
        selection: [1, 2]
      )

      assert_equal Permission::Action::Read, selection.permissions["metadata"]
      assert_equal Permission::Action::Write, selection.permissions["contents"]
    end
  end
end
