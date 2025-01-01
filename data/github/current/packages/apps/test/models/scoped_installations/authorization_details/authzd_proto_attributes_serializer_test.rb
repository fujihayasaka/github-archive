# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::AuthzdProtoSerializerTest < GitHub::TestCase
  fixtures do
    @serializer = ::ScopedInstallations::AuthorizationDetails::AuthzdProtoAttributesSerializer
  end

  context ".generate" do
    test "version" do
      struct = ::ScopedInstallations::AuthorizationDetails::Structs::V1.new

      expected = [
        Authzd::Proto::Attribute.wrap("test.authorization_details.version", struct.version)
      ]

      assert_same_elements expected, @serializer.generate(struct: struct, namespace: "test")
    end

    test "selections" do
      struct = ::ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "selections" => {
          "repository" => "subset"
        }
      })

      expected = [
        Authzd::Proto::Attribute.wrap("test.authorization_details.version", struct.version),
        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.selections.repository", "subset")
      ]

      assert_same_elements expected, @serializer.generate(struct: struct, namespace: "test")
    end

    test "subject_ids" do
      struct = ::ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "subject_ids" => {
          "repository" => [1, 2, 3]
        }
      })

      expected = [
        Authzd::Proto::Attribute.wrap("test.authorization_details.version", struct.version),
        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.subject_ids.repository", [1, 2, 3])
      ]

      assert_same_elements expected, @serializer.generate(struct: struct, namespace: "test")
    end

    test "subject_types_and_actions" do
      struct = ::ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash({
        "subject_types_and_actions" => {
          "repository" => { "metadata" => 0, "contents" => 1, "repository_projects" => 2 }
        }
      })

      expected = [
        Authzd::Proto::Attribute.wrap("test.authorization_details.version", struct.version),

        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.subject_types_and_actions.repository.metadata.read", true),

        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.subject_types_and_actions.repository.contents.read", true),
        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.subject_types_and_actions.repository.contents.write", true),

        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.subject_types_and_actions.repository.repository_projects.read", true),
        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.subject_types_and_actions.repository.repository_projects.write", true),
        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.subject_types_and_actions.repository.repository_projects.admin", true)
      ]

      assert_same_elements expected, @serializer.generate(struct: struct, namespace: "test")
    end

    test "asymmetric" do
      struct = ::ScopedInstallations::AuthorizationDetails::Structs::V1.new(
        asymmetric: {
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository => {
            "metadata" => { "read" => [1, 2, 3] },
            "contents" => { "read" => [6], "write" => [3, 4, 5] },
          },
          ScopedInstallations::AuthorizationDetails::ResourceType::WorkflowRun => {
            "codespace_prebuild" => { "write" => [42] }
          }
        }
      )

      expected = [
        Authzd::Proto::Attribute.wrap("test.authorization_details.version", struct.version),

        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.selections.repository.asymmetric", true),

        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.asymmetric.repository.metadata.read", [1, 2, 3]),

        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.asymmetric.repository.contents.read", [3, 4, 5, 6]),
        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.asymmetric.repository.contents.write", [3, 4, 5]),

        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.selections.workflow_run.asymmetric", true),

        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.asymmetric.workflow_run.codespace_prebuild.read", [42]),
        Authzd::Proto::Attribute.wrap("test.authorization_details.v1.asymmetric.workflow_run.codespace_prebuild.write", [42])
      ]

      assert_same_elements expected, @serializer.generate(struct: struct, namespace: "test")
    end
  end
end
