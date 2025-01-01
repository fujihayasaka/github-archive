# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::HelperTest < GitHub::TestCase
  fixtures do
    @helper = ScopedInstallations::AuthorizationDetails::Helper

    @repository_type = ScopedInstallations::AuthorizationDetails::ResourceType::Repository
  end

  context "with V1" do
    test "returns false if there is no selection granted" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "subject_types_and_actions" => {
          "repository" => { "metadata" => 0 }
        }
      })

      refute @helper.with(reader).has_minimum_action?(resource_type: @repository_type, resource: nil, min_action: :read)
    end

    test "returns false if the granted permission has less access than requested" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "selections" => { "repository" => "subset" },
        "subject_types_and_actions" => {
          "repository" => { "metadata" => 0, "contents" => 0 }
        }
      })

      refute @helper.with(reader).has_minimum_action?(resource_type: @repository_type, resource: "contents", min_action: :write)
    end

    test "returns true if the granted permission has less access than requested" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "selections" => { "repository" => "subset" },
        "subject_types_and_actions" => {
          "repository" => { "metadata" => 0 }
        }
      })

      assert @helper.with(reader).has_minimum_action?(resource_type: @repository_type, resource: "metadata", min_action: :read)
    end

    test "returns false if the granted action is less than the minimum action" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "selections" => { "repository" => "subset" },
        "subject_types_and_actions" => {
          "repository" => { "metadata" => 0 }
        }
      })

      refute @helper.with(reader).has_minimum_action?(resource_type: @repository_type, resource: nil, min_action: :write)
    end

    test "returns true if the granted action is equal to the minimum action" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "selections" => { "repository" => "subset" },
        "subject_types_and_actions" => {
          "repository" => { "metadata" => 0 }
        }
      })

      assert @helper.with(reader).has_minimum_action?(resource_type: @repository_type, resource: nil, min_action: :read)
    end
  end

  context "with V2" do
    test "returns false if there is no selection granted" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash({
        "repository" => {
          "selection" => ScopedInstallations::AuthorizationDetails::Selection::None,
          "permissions" => {
            "metadata" => 0
          }
        }
      })

      refute @helper.with(reader).has_minimum_action?(resource_type: @repository_type, resource: nil, min_action: :read)
    end

    test "returns false if the granted permission has less access than requested" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash({
        "repository" => {
          "selection" => [42],
          "permissions" => {
            "metadata" => 0,
            "contents" => 0
          }
        }
      })

      refute @helper.with(reader).has_minimum_action?(resource_type: @repository_type, resource: "contents", min_action: :write)
    end

    test "returns true if the granted permission has less access than requested" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash({
        "repository" => {
          "selection" => [42],
          "permissions" => {
            "metadata" => 0,
            "contents" => 0
          }
        }
      })

      assert @helper.with(reader).has_minimum_action?(resource_type: @repository_type, resource: "metadata", min_action: :read)
    end

    test "returns false if the granted action is less than the minimum action" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash({
        "repository" => {
          "selection" => [42],
          "permissions" => {
            "metadata" => 0
          }
        }
      })

      refute @helper.with(reader).has_minimum_action?(resource_type: @repository_type, resource: nil, min_action: :write)
    end

    test "returns true if the granted action is equal to the minimum action" do
      reader = ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash({
        "repository" => {
          "selection" => [42],
          "permissions" => {
            "metadata" => 0,
          }
        }
      })

      assert @helper.with(reader).has_minimum_action?(resource_type: @repository_type, resource: nil, min_action: :read)
    end
  end

end
