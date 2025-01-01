# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class DeploymentStatusesTest < Api::SerializerTestCase
  fixtures do
    @deployment_status = create(:deployment_status)
  end

  context "#deployment_status_hash" do
    test "payload is valid" do
      output = deployment_status(@deployment_status)
      assert output.key?("id")
      assert output.key?("node_id")
      assert output.key?("state")
      assert output.key?("url")
    end

    test "payload with performed_via_github_app is valid" do
      installation = make_integration_installation(repository: create(:repository), permissions: { "deployments" => :write })
      deployment_status = create(:deployment_status, performed_via_integration: installation.integration)

      output = deployment_status(deployment_status)
      assert output.key?("id")
      assert output.key?("node_id")
      assert output.key?("state")
      assert output.key?("creator")

    end
  end
end
