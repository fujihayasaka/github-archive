# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::Structs::V2::SelectionWithPermissionsTest < GitHub::TestCase
  def selection_with_permissions(selection:, permissions:)
    ScopedInstallations::AuthorizationDetails::Structs::V2::SelectionWithPermissions.new(selection:, permissions:)
  end

  context "#granted_access_on_all_subjects" do
    test "selection is 'all'" do
      struct = selection_with_permissions(
        selection: ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      assert_equal Permission::Action::Read, struct.granted_access_on_all_subjects("metadata")
    end

    test "selection is 'all' but the resource isn't granted" do
      struct = selection_with_permissions(
        selection: ScopedInstallations::AuthorizationDetails::Selection::All,
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      assert_nil struct.granted_access_on_all_subjects("contents")
    end

    test "selection is 'global'" do
      struct = selection_with_permissions(
        selection: ScopedInstallations::AuthorizationDetails::Selection::Global,
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      assert_equal Permission::Action::Read, struct.granted_access_on_all_subjects("metadata")
    end

    test "selection is 'parent'" do
      struct = selection_with_permissions(
        selection: ScopedInstallations::AuthorizationDetails::Selection::Parent,
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      assert_equal Permission::Action::Read, struct.granted_access_on_all_subjects("metadata")
    end

    test "selection is a subset of subjects" do
      struct = selection_with_permissions(
        selection: [42],
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      assert_nil struct.granted_access_on_all_subjects("metadata")
    end

    test "selection is a 'none'" do
      struct = selection_with_permissions(
        selection: ScopedInstallations::AuthorizationDetails::Selection::None,
        permissions: {}
      )

      assert_nil struct.granted_access_on_all_subjects("metadata")
    end
  end

  context "#granted_subject_ids_with_actions_for" do
    test "returns granted access on subjects" do
      struct = selection_with_permissions(
        selection: [42],
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      assert_same_elements([[42, 0]], struct.granted_subject_ids_with_actions_for("metadata", [42]))
    end

    test "return subject ids for 'global' selection" do
      struct = selection_with_permissions(
        selection: ScopedInstallations::AuthorizationDetails::Selection::Global,
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      assert_same_elements([[42, 0]], struct.granted_subject_ids_with_actions_for("metadata", [42]))
    end

    test "returns subject ids for 'parent' selection" do
      struct = selection_with_permissions(
        selection: ScopedInstallations::AuthorizationDetails::Selection::Parent,
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      assert_same_elements([[42, 0]], struct.granted_subject_ids_with_actions_for("metadata", [42]))
    end

    test "filters subjects provided" do
      struct = selection_with_permissions(
        selection: [42],
        permissions: {
          "metadata" => Permission::Action::Read
        }
      )

      assert_same_elements([[42, 0]], struct.granted_subject_ids_with_actions_for("metadata", [42, 50]))
    end

    test "resource isn't granted" do
      struct = selection_with_permissions(
        selection: [42],
        permissions: {
          "contents" => Permission::Action::Read
        }
      )

      assert_empty([], struct.granted_subject_ids_with_actions_for("metadata", [42, 50]))
    end
  end
end
