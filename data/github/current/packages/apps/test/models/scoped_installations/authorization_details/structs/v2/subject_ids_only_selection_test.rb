# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::Structs::V2::SubjectIdsOnlySelectionTest < GitHub::TestCase
  def subject_ids_only_selection(permissions:)
    ScopedInstallations::AuthorizationDetails::Structs::V2::SubjectIdsOnlySelection.new(permissions:)
  end

  test "#granted_access_on_all_subjects" do
    selection = subject_ids_only_selection(
      permissions: {
        "sarifs" => {
          Permission::ActionString::Read => [42, 50, 79]
        }
      }
    )

    assert_nil selection.granted_access_on_all_subjects("sarifs")
  end

  context "#granted_subject_ids_with_actions_for" do
    test "grants access to a subset of the subject ids" do
      selection = subject_ids_only_selection(
        permissions: {
          "sarifs" => {
            Permission::ActionString::Read => [42, 50, 79]
          }
        }
      )

      assert_equal [[42, 0], [50, 0]], selection.granted_subject_ids_with_actions_for("sarifs", [42, 50])
    end

    test "filters subject ids" do
      selection = subject_ids_only_selection(
        permissions: {
          "sarifs" => {
            Permission::ActionString::Read => [42, 50, 79]
          }
        }
      )

      assert_equal [[42, 0]], selection.granted_subject_ids_with_actions_for("sarifs", [42, 80])
    end

    test "returns the highest action for a subject id" do
      selection = subject_ids_only_selection(
        permissions: {
          "sarifs" => {
            Permission::ActionString::Read => [42, 50, 79],
            Permission::ActionString::Write => [79]
          }
        }
      )

      assert_equal [[42, 0], [79, 1]], selection.granted_subject_ids_with_actions_for("sarifs", [42, 79])
    end
  end

  context "#selection" do
    test "collects all of the granted subject ids" do
      selection = subject_ids_only_selection(
        permissions: {
          "contents" => {
            Permission::ActionString::Read => [42],
            Permission::ActionString::Write => [79]
          },
          "administration" => {
            Permission::ActionString::Read => [82],
            Permission::ActionString::Write => [63]
          }
        }
      )

      assert_same_elements([42, 79, 82, 63], selection.selection)
    end
  end

  context "#add_permissions_selection" do
    test "adds a permissions selection" do
      selection = subject_ids_only_selection(
        permissions: {
          "contents" => {
            Permission::ActionString::Read => [42]
          }
        }
      )

      selection.add_permissions_selection(
        permissions: { "contents" => :read },
        selection: [73]
      )

      assert_same_elements [42, 73], selection.permissions["contents"][Permission::ActionString::Read]
    end

    test "only merges permissions into action" do
      selection = subject_ids_only_selection(
        permissions: {
          "contents" => {
            Permission::ActionString::Read => [42]
          }
        }
      )

      selection.add_permissions_selection(
        permissions: { "contents" => :write },
        selection: [42, 73]
      )

      assert_same_elements [42, 73], selection.permissions["contents"][Permission::ActionString::Write]
      assert_equal [42], selection.permissions["contents"][Permission::ActionString::Read] # Dupes are possible, for now
    end
  end

  context "#authzd_proto_attributes" do
    test "applies the <resource>.<action>.ids ID with a list of subject ids" do
      selection = subject_ids_only_selection(
        permissions: {
          "contents" => {
            Permission::ActionString::Read => [42]
          }
        }
      )

      expected = [Authzd::Proto::Attribute.wrap("contents.read.ids", [42])]
      actual = selection.authzd_proto_attributes

      assert_same_elements(expected, actual)
    end

    test "sets the read attribute if granted write" do
      selection = subject_ids_only_selection(
        permissions: {
          "contents" => {
            Permission::ActionString::Write => [42]
          }
        }
      )

      expected = [
        Authzd::Proto::Attribute.wrap("contents.write.ids", [42]),
        Authzd::Proto::Attribute.wrap("contents.read.ids", [42])
      ]

      actual = selection.authzd_proto_attributes

      assert_same_elements(expected, actual)
    end

    test "cascades access" do
      selection = subject_ids_only_selection(
        permissions: {
          "contents" => {
            Permission::ActionString::Read => [37],
            Permission::ActionString::Write => [42],
            Permission::ActionString::Admin => [96]
          }
        }
      )

      expected = [
        Authzd::Proto::Attribute.wrap("contents.admin.ids", [96]),
        Authzd::Proto::Attribute.wrap("contents.write.ids", [42, 96]),
        Authzd::Proto::Attribute.wrap("contents.read.ids", [37, 42, 96])
      ]

      actual = selection.authzd_proto_attributes.map do |attribute|
        Authzd::Proto::Attribute.wrap(attribute.id, attribute.value.unwrap.sort)
      end

      assert_same_elements(expected, actual)
    end
  end
end
