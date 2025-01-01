# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Serializers::PermissionsDataTest < GitHub::TestCase
  context "#call" do
    context "when the integration has no permissions" do
      test "returns an empty array" do
        integration = create(:integration, default_permissions: {})
        data = Marketplace::Serializers::PermissionsData.new(integration: integration).call

        assert_empty data
      end
    end

    context "when the integration has permissions" do
      test "groups the permissions by scope and permission level and returns the human readable values in an array" do
        integration = create(:integration,
          default_permissions: {
            "metadata" => :read,
            "emails" => :read,
            "contents" => :write,
            "issues" => :read,
            "pull_requests" => :write,
            "organization_projects" => :admin,
            "single_file" => :read,
            "repository_projects" => :admin,
          }, single_file_name: "test.txt")
        data = Marketplace::Serializers::PermissionsData.new(integration: integration).call

        assert_equal [
          { scope: "single file", permissionLevel: "read", values: ["test.txt"] },
          { scope: "repository", permissionLevel: "read", values: %w(issues metadata) },
          { scope: "repository", permissionLevel: "write", values: ["code", "pull requests"] },
          { scope: "repository", permissionLevel: "admin", values: ["repository projects"] },
          { scope: "organization", permissionLevel: "admin", values: ["organization projects"] },
          { scope: "user", permissionLevel: "read", values: ["email addresses"] },
        ], data
      end

      test "excludes permissions types other than repository, organization, or user" do
        integration = create(:integration, default_permissions: { "enterprise_administration" => :read })
        data = Marketplace::Serializers::PermissionsData.new(integration: integration).call

        assert_empty data
      end
    end
  end
end
