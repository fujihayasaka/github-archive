# typed: true
# frozen_string_literal: true

require "test_helper"

class DeletePrebuildTemplatesTest < GitHub::TestCase
  include CodespacesPlanFixtures

  fixtures do
    make_trusted_oauth_apps_owner
    @user = create(:user)
    enable_feature_flag(:codespaces_developer, @user)
    @org = create(:codespaces_organization, admin: @user)
    @repo = create(:repository, owner: @org, from_example: :simple)
    @branch = "master"
    @locations = %w[WestUs2 WestEurope]
  end

  setup do
    FakeVSOServer.reset!
    @command_args = {
      repository_id: @repo.id,
      locations: @locations,
      branch: @branch
    }
  end

  context "#validate!", skip_enterprise: true do

    test "raises when passing a vscs_target but the repo owner isn't a codespaces developer" do
      disable_feature_flag(:codespaces_developer)

      assert_raises Codespaces::ValidatePrebuildAccess::AuthorizationError do
        Codespaces::DeletePrebuildTemplates.call(
          **@command_args.merge(
            {
              vscs_target: "ppe",
            }
          )
        )
      end
    end

    test "does not raise error when passing a vscs_target_url and the vscs_target `local`" do
      enable_feature_flag(:codespaces_developer)

      vscs_target_host = "vscstest.ngrok.io"
      FakeVSOServer.reset!
      Codespaces::DeletePrebuildTemplates.call(
        **@command_args.merge({
          vscs_target_url: "https://#{vscs_target_host}",
          vscs_target: "local"
        })
      )

      request = FakeVSOServer.requests.last
      assert_includes request.env["HTTP_HOST"], vscs_target_host
    end

    test "does not raise when the org has disabled codespaces" do
      Codespaces::OrgPolicy.stubs(:enabled_for_organization?).returns(false)
      assert_nothing_raised do
        Codespaces::DeletePrebuildTemplates.call(
          **@command_args
        )
      end
    end

    test "bypasses validation if org disabled codespaces" do
      org = create(:organization)
      repo = create(:repository, owner: org)

      Codespaces::OrgPolicy.stubs(:enabled_for_organization?).returns(false)

      Codespaces::DeletePrebuildTemplates.call(
        repository_id: repo.id,
        locations: @locations,
         branch: @branch
      )

      delete_templates_requests = FakeVSOServer.delete_templates_triggered
      assert_equal 2, delete_templates_requests.count
    end
  end

  context "#validate_prebuild_templates!", skip_enterprise: true do
    test "deletes prebuild templates that do not match the configuration" do
      FakeVSOServer.reset!
      locations = %w[WestUs2 WestEurope EastUs]
      configuration = create(:codespace_prebuild_configuration, repository: @repo, branch: @branch, devcontainer_path: ".devcontainer.json", with_locations: locations)

      locations.each do |location|
        create(:codespace_prebuild_template, repository: @repo, branch: @branch, devcontainer_path: ".devcontainer.json", location: location, configuration: configuration)
      end

      templates = configuration.reload.prebuild_templates
      assert_equal 3, templates.count

      template1, template2, template3 = templates

      # missmatched location
      template1.update!(location: "SouthEastAsia")

      # mismatched branch
      template2.update!(branch: "not_main")

      Codespaces::DeletePrebuildTemplates.call(
        repository_id: @repo.id,
        locations: @locations,
        branch: @branch,
        devcontainer_path: ".devcontainer.json",
        configuration_id: configuration.id
      )

      templates = configuration.reload.prebuild_templates
      assert_equal 1, templates.count
      assert_equal [template3], templates
    end
  end

  context "#perform" do
    test "deletes templates vscs endpoint is called" do
      FakeVSOServer.reset!
      configuration = create(:codespace_prebuild_configuration)

      Codespaces::DeletePrebuildTemplates.call(
        repository_id: @repo.id,
        locations: @locations,
        branch: @branch,
        devcontainer_path: ".devcontainer.json",
        configuration_id: configuration.id
      )

      delete_templates_requests = FakeVSOServer.delete_templates_triggered
      assert_equal 2, delete_templates_requests.count

      assert_equal "POST", delete_templates_requests[0].request_method
      assert_equal "/api/v2/prebuilds/delete", delete_templates_requests[0].path
      assert_includes delete_templates_requests[0].env["HTTP_HOST"], "westus2"

      assert_equal "POST", delete_templates_requests[1].request_method
      assert_equal  "/api/v2/prebuilds/delete", delete_templates_requests[1].path
      assert_includes delete_templates_requests[1].env["HTTP_HOST"], "westeurope"
    end

    test "failure in one region does not impact other regions for template deletion" do
      configuration = create(:codespace_prebuild_configuration)

      Codespaces::VscsClient.any_instance.stubs(:delete_prebuild_templates!)
        .with(location: "WestUs2", repository_id: @repo.id, branch: @branch, devcontainer_path: "devcontainer.json", configuration_id: configuration.id)
        .raises(Codespaces::Client::BadResponseError.new("BOOM!"))

      Codespaces::VscsClient.any_instance.expects(:delete_prebuild_templates!)
        .with(location: "WestEurope", repository_id: @repo.id, branch: @branch, devcontainer_path: "devcontainer.json", configuration_id: configuration.id).once

      FakeVSOServer.reset!
      Codespaces::DeletePrebuildTemplates.call(
        repository_id: @repo.id,
        locations: @locations,
        branch: @branch,
        devcontainer_path: "devcontainer.json",
        configuration_id: configuration.id
      )
    end
  end
end unless GitHub.enterprise?
