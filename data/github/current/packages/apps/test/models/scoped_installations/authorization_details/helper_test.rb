# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::HelperTest < GitHub::TestCase
  fixtures do
    @helper = ScopedInstallations::AuthorizationDetails::Helper

    @repository_type = ScopedInstallations::AuthorizationDetails::ResourceType::Repository
  end

  context "#has_minimum_action?" do
    test "returns false if there is no selection granted" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "subject_types_and_actions" => {
          "repository" => { "metadata" => 0 }
        }
      })

      refute @helper.with(reader).has_minimum_action?(type: @repository_type, resource: nil, min_action: :read)
    end

    test "returns false if the granted permission has less access than requested" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "selections" => { "repository" => "subset" },
        "subject_types_and_actions" => {
          "repository" => { "metadata" => 0, "contents" => 0 }
        }
      })

      refute @helper.with(reader).has_minimum_action?(type: @repository_type, resource: "contents", min_action: :write)
    end

    test "returns true if the granted permission has less access than requested" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "selections" => { "repository" => "subset" },
        "subject_types_and_actions" => {
          "repository" => { "metadata" => 0 }
        }
      })

      assert @helper.with(reader).has_minimum_action?(type: @repository_type, resource: "metadata", min_action: :read)
    end

    test "returns false if the granted action is less than the minimum action" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "selections" => { "repository" => "subset" },
        "subject_types_and_actions" => {
          "repository" => { "metadata" => 0 }
        }
      })

      refute @helper.with(reader).has_minimum_action?(type: @repository_type, resource: nil, min_action: :write)
    end

    test "returns true if the granted action is equal to the minimum action" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "selections" => { "repository" => "subset" },
        "subject_types_and_actions" => {
          "repository" => { "metadata" => 0 }
        }
      })

      assert @helper.with(reader).has_minimum_action?(type: @repository_type, resource: nil, min_action: :read)
    end
  end

  context "#asymmetric_subject_ids_for" do
    test "returns an empty array if there is the resource isn't granted" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({})
      assert_empty @helper.with(reader).asymmetric_subject_ids_for(type: @repository_type, resource: nil, min_action: :read)
    end

    test "returns an empty array if the minimum action hasn't been granted" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "asymmetric" => {
          "repository" => { "metadata" => { "read" => [1] } }
        }
      })

      assert_empty @helper.with(reader).asymmetric_subject_ids_for(type: @repository_type, resource: nil, min_action: :write)
    end

    test "returns the subject ids that have the minimum action" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "asymmetric" => {
          "repository" => { "metadata" => { "read" => [1] } }
        }
      })

      assert_equal [1], @helper.with(reader).asymmetric_subject_ids_for(type: @repository_type, resource: nil, min_action: :read)
    end

    test "returns the subject ids that have the minimum action across all resources" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "asymmetric" => {
          "repository" => { "metadata" => { "read" => [1] }, "contents" => { "read" => [1, 2] } }
        }
      })

      assert_same_elements [1, 2], @helper.with(reader).asymmetric_subject_ids_for(type: @repository_type, resource: nil, min_action: :read)
    end

    test "returns the subject ids that have the minimum action for a specific resource" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "asymmetric" => {
          "repository" => { "metadata" => { "read" => [3] }, "contents" => { "read" => [1, 2] } }
        }
      })

      assert_same_elements [1, 2], @helper.with(reader).asymmetric_subject_ids_for(type: @repository_type, resource: "contents", min_action: :read)
    end

    test "does not include subject ids that do not have the minimum action" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "asymmetric" => {
          "repository" => {
            "metadata" => {
              "read" => [1]
            },
            "contents" => {
              "read"  => [2, 3],
              "write" => [4, 5]
            },
            "issues" => {
              "write" => [6]
            },
            "repository_projects" => {
              "admin" => [7]
            }
          }
        }
      })

      assert_same_elements [4, 5, 6, 7], @helper.with(reader).asymmetric_subject_ids_for(type: @repository_type, resource: nil, min_action: :write)
    end

    test "does not include subject ids that do not have the minimum action for a given resource" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "asymmetric" => {
          "repository" => {
            "metadata" => {
              "read" => [1]
            },
            "repository_projects" => {
              "read"  => [7],
              "admin" => [8]
            }
          }
        }
      })

      assert_same_elements [8], @helper.with(reader).asymmetric_subject_ids_for(type: @repository_type, resource: "repository_projects", min_action: :admin)
    end
  end

end
