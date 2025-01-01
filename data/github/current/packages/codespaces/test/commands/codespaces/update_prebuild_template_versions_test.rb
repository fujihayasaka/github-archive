
# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdatePrebuildTemplateVersionsTest < GitHub::TestCase
  include CodespacesPlanFixtures

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :simple)
    @maximum_template_versions = 2
    @devcontainer_path = ".devcontainer/custom/devcontainer.json"
    @prebuild_configuration = create(
      :codespace_prebuild_configuration,
      repository: @repo,
      branch: @repo.default_branch,
      maximum_template_versions: @maximum_template_versions,
      devcontainer_path: @devcontainer_path,
      with_locations: %w[WestUs2 EastUs])
  end

  setup do
    FakeVSOServer.reset!
  end

  context ".call" do
    test "prebuild configuration does not exist, no operations" do
      Codespaces::VscsClient.any_instance.expects(:update_prebuild_template_versions).never
      Codespaces::UpdatePrebuildTemplateVersions.call(
        prebuild_configuration_id: "invalid",
        location: "WestUs2")
    end

    test "prebuild configuration exists, invalid location" do
      assert_raises Codespaces::UpdatePrebuildTemplateVersions::InvalidLocation do
        Codespaces::UpdatePrebuildTemplateVersions.call(
          prebuild_configuration_id: @prebuild_configuration.id,
          location: "WestEurope")
      end
    end

    test "prebuild configuration exists, send request to the right location" do
      Codespaces::UpdatePrebuildTemplateVersions.call(
        prebuild_configuration_id: @prebuild_configuration.id,
        location: "WestUs2")

      expected_path = "/api/v2/prebuilds/templates/updatemaxversions"
      request = FakeVSOServer.requests.last
      assert_includes request.env["HTTP_HOST"], "westus2"

      assert_equal "POST", request.request_method
      assert_equal expected_path, request.path
      request_body = GitHub::JSON.parse(request.body)
      assert_equal @repo.id, request_body["repoId"]
      assert_equal @repo.default_branch, request_body["branchName"]
      assert_equal @maximum_template_versions, request_body["maxPrebuildTemplateVersions"]
      assert_equal @devcontainer_path, request_body["devContainerPath"]
    end

    test "raises connection failed for timeout errors" do
      Codespaces::VscsClient.any_instance.stubs(:update_prebuild_template_versions).raises(Codespaces::VscsClient::TimeoutError.new("BOOM!"))

      assert_raises Codespaces::UpdatePrebuildTemplateVersions::ConnectionFailed do
        Codespaces::UpdatePrebuildTemplateVersions.call(
          prebuild_configuration_id: @prebuild_configuration.id,
          location: "WestUs2")
      end
    end

    test "raises bad response" do
      Codespaces::VscsClient.any_instance.stubs(:update_prebuild_template_versions).raises(Codespaces::Client::BadResponseError.new("BOOM!"))

      assert_raises Codespaces::UpdatePrebuildTemplateVersions::BadResponse do
        Codespaces::UpdatePrebuildTemplateVersions.call(
          prebuild_configuration_id: @prebuild_configuration.id,
          location: "WestUs2")
      end
    end

    test "logs the template version count when job is queued" do
      GitHub.logger.expects(:info).at_least_once
      GitHub.logger.expects(:info).with(
        "template versions updated",
        "gh.catalog_service" => "github/codespaces",
        "gh.codespaces.prebuild_configuration.id" => @prebuild_configuration.id,
        "gh.codespaces.maximum_prebuild_template_versions" => @prebuild_configuration.maximum_template_versions,
      ).once

      Codespaces::UpdatePrebuildTemplateVersions.call(
        prebuild_configuration_id: @prebuild_configuration.id,
        location: "WestUs2")
    end
  end
end
