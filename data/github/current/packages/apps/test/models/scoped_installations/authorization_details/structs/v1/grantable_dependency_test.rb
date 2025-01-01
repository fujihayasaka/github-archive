# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::Structs::V1::GrantableDependencyTest < GitHub::TestCase
  context "#granted_access_on_all_subjects" do
    test "selection is 'all'" do
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

      assert_equal 0, struct.granted_access_on_all_subjects(ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "metadata")
    end

    test "selection is 'all' but the resource isn't granted" do
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

      assert_nil struct.granted_access_on_all_subjects(ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "contents")
    end

    test "selection is 'global'" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        selections: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Global
        },
        subject_types_and_actions: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "metadata" => Permission::Action::Read
          }
        }
      )

      assert_equal 0, struct.granted_access_on_all_subjects(ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "metadata")
    end

    test "selection is 'parent'" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        selections: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Parent
        },
        subject_types_and_actions: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "metadata" => Permission::Action::Read
          }
        }
      )

      assert_equal 0, struct.granted_access_on_all_subjects(ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "metadata")
    end

    test "selection is 'subset'" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        selections: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset
        },
        subject_types_and_actions: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "metadata" => Permission::Action::Read
          }
        },
        subject_ids: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [42]
        }
      )

      assert_nil struct.granted_access_on_all_subjects(ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "metadata")
    end

    test "selection is 'none'" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new
      assert_nil struct.granted_access_on_all_subjects(ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "metadata")
    end
  end

  context "#granted_subject_ids_with_actions_for" do
    test "returns subject_ids granted access" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        selections: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset
        },
        subject_types_and_actions: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "metadata" => Permission::Action::Read
          }
        },
        subject_ids: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [42]
        }
      )

      actual = struct.granted_subject_ids_with_actions_for(ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "metadata", [42])
      assert_same_elements([[42, 0]], actual)
    end

    test "filters ids that aren't granted access" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        selections: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset
        },
        subject_types_and_actions: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "metadata" => Permission::Action::Read
          }
        },
        subject_ids: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [42]
        }
      )

      actual = struct.granted_subject_ids_with_actions_for(ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "metadata", [42, 50])
      assert_same_elements([[42, 0]], actual)
    end

    test "returns all subject ids for 'global' selection" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        selections: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Global
        },
        subject_types_and_actions: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "metadata" => Permission::Action::Read
          }
        }
      )

      actual = struct.granted_subject_ids_with_actions_for(ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "metadata", [42])
      assert_same_elements([[42, 0]], actual)
    end

    test "returns all subject ids for 'parent' selection" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        selections: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Parent
        },
        subject_types_and_actions: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "metadata" => Permission::Action::Read
          }
        }
      )

      actual = struct.granted_subject_ids_with_actions_for(ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "metadata", [42])
      assert_same_elements([[42, 0]], actual)
    end

    test "returns asymmetric and typical subject ids" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        selections: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset
        },
        subject_types_and_actions: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "contents" => Permission::Action::Read
          }
        },
        subject_ids: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [42]
        },
        asymmetric: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "contents" => {
              "write" => [50]
            }
          }
        }
      )

      actual = struct.granted_subject_ids_with_actions_for(ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "contents", [42, 50])
      assert_same_elements([[42, 0], [50, 1]], actual)
    end

    test "returns asymmetric if susbset doesn't have access" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        selections: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset
        },
        subject_types_and_actions: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "metadata" => Permission::Action::Read
          }
        },
        subject_ids: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [42]
        },
        asymmetric: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "contents" => {
              "write" => [50]
            }
          }
        }
      )

      actual = struct.granted_subject_ids_with_actions_for(ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "contents", [42, 50])
      assert_same_elements([[50, 1]], actual)
    end

    test "returns asymmetric ids for 'all' and no access" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        selections: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::All
        },
        subject_types_and_actions: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "metadata" => Permission::Action::Read
          }
        },
        asymmetric: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "contents" => {
              "write" => [50]
            }
          }
        }
      )

      actual = struct.granted_subject_ids_with_actions_for(ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "contents", [42, 50])
      assert_same_elements([[50, 1]], actual)
    end

    test "asymmetric ids return the highest level of action" do
      struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        selections: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::All
        },
        subject_types_and_actions: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "metadata" => Permission::Action::Read
          }
        },
        asymmetric: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "contents" => {
              "read" => [42, 50],
              "write" => [50]
            }
          }
        }
      )

      actual = struct.granted_subject_ids_with_actions_for(ScopedInstallations::AuthorizationDetails::ResourceType::Repository, "contents", [42, 50])
      assert_same_elements([[42, 0], [50, 1]], actual)
    end
  end
end
