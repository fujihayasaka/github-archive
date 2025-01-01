# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::ResourceTypeTest < GitHub::TestCase
  context ".for" do
    test "returns the correct resource type" do
      assert_equal(
        ScopedInstallations::AuthorizationDetails::ResourceType::Repository,
        ScopedInstallations::AuthorizationDetails::ResourceType.for("repository")
      )
    end

    test "returns the same resource when is already a resource type" do
      assert_equal(
        ScopedInstallations::AuthorizationDetails::ResourceType::Repository,
        ScopedInstallations::AuthorizationDetails::ResourceType.for(
          ScopedInstallations::AuthorizationDetails::ResourceType::Repository
        )
      )
    end

    test "returns the correct resource type when resource is a string" do
      assert_equal(
        ScopedInstallations::AuthorizationDetails::ResourceType::WorkflowRun,
        ScopedInstallations::AuthorizationDetails::ResourceType.for("WorkflowRun")
      )
    end

    test "returns the correct resource type when resource an instance" do
      assert_equal(
        ScopedInstallations::AuthorizationDetails::ResourceType::Organization,
        ScopedInstallations::AuthorizationDetails::ResourceType.for(build(:organization))
      )
    end
  end
end
