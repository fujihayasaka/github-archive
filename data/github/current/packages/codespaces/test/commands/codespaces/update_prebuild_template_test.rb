
# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdatePrebuildTemplateTest < GitHub::TestCase
  include CodespacesPlanFixtures

  setup do
    FakeVSOServer.reset!
  end

  context ".call" do
    context "prebuild template does not link to the repo" do
      test "returns nil" do
        repo = create(:repository)
        prebuild_template = create(:codespace_prebuild_template)
        state = "archived"

        template = Codespaces::UpdatePrebuildTemplate.call(guid: prebuild_template.guid, repository: repo, state: state)

        assert_nil template
      end
    end

    context "prebuild template guid does not exist" do
      test "returns nil" do
        repo = create(:repository)
        prebuild_template = create(:codespace_prebuild_template, repository: repo)
        state = "archived"

        template = Codespaces::UpdatePrebuildTemplate.call(guid: "something-else", repository: repo, state: state)

        assert_nil template
      end
    end
  end

  context "prebuild template and repo match" do

    test "template state is invalid" do
      repo = create(:repository)
      prebuild_template = create(:codespace_prebuild_template, repository: repo)
      state = "invalid"

      assert_raises Codespaces::UpdatePrebuildTemplate::InvalidTemplateState do
        Codespaces::UpdatePrebuildTemplate.call(guid: prebuild_template.guid, repository: repo, state: state)
      end
    end

    test "template state is set to archived" do
      repo = create(:repository, from_example: :simple)
      locations = ["WestUs2"]
      branch = "master"

      configuration = create(:codespace_prebuild_configuration, repository: repo)

      prebuild_template = create(:codespace_prebuild_template, repository: repo)

      state = "archived"
      FakeVSOServer.reset!

      template = Codespaces::UpdatePrebuildTemplate.call(guid: prebuild_template.guid, repository: repo, state: state)
      request = FakeVSOServer.requests.last
      request_body = GitHub::JSON.parse(request.body)

      assert_equal "POST", request.request_method
      assert_equal "/api/v2/prebuilds/templates/#{prebuild_template.guid}/updatestatus", request.path
      assert_equal true, request_body["isSuccess"]
      assert_equal state, template.state
    end

    test "template state is set to failed" do
      repo = create(:repository, from_example: :simple)
      locations = ["WestUs2"]
      branch = "master"

      configuration = create(:codespace_prebuild_configuration, repository: repo)

      prebuild_template = create(:codespace_prebuild_template, repository: repo)
      state = "failed"
      FakeVSOServer.reset!

      template = Codespaces::UpdatePrebuildTemplate.call(guid: prebuild_template.guid, repository: repo, state: state)
      request = FakeVSOServer.requests.last
      request_body = GitHub::JSON.parse(request.body)

      assert_equal "POST", request.request_method
      assert_equal "/api/v2/prebuilds/templates/#{prebuild_template.guid}/updatestatus", request.path
      assert_equal false, request_body["isSuccess"]
      assert_equal state, template.state
    end

    test "raises connection failed for timeout errors" do
      Codespaces::VscsClient.any_instance.stubs(:update_prebuild_template_status).raises(Codespaces::VscsClient::TimeoutError.new("BOOM!"))
      repo = create(:repository)
      prebuild_template = create(:codespace_prebuild_template, repository: repo)
      state = "archived"

      assert_raises Codespaces::UpdatePrebuildTemplate::ConnectionFailed do
        Codespaces::UpdatePrebuildTemplate.call(guid: prebuild_template.guid, repository: repo, state: state)
      end
    end

    test "raises bad response" do
      Codespaces::VscsClient.any_instance.stubs(:update_prebuild_template_status).raises(Codespaces::Client::BadResponseError.new("BOOM!"))
      repo = create(:repository)
      prebuild_template = create(:codespace_prebuild_template, repository: repo)
      state = "archived"

      assert_raises Codespaces::UpdatePrebuildTemplate::BadResponse do
        Codespaces::UpdatePrebuildTemplate.call(guid: prebuild_template.guid, repository: repo, state: state)
      end
    end

    context "update prebuild template versions job" do
      test "Performs clean up job if vscs_target is nil" do
        repo = create(:repository, from_example: :simple)
        locations = ["WestUs2"]
        state = "archived"
        configuration = create(:codespace_prebuild_configuration, repository: repo, vscs_target: nil)

        prebuild_template = create(:codespace_prebuild_template, repository: repo, codespace_prebuild_configuration_id: configuration.id)

        Codespaces::UpdatePrebuildTemplateVersionsJob.expects(:perform_later).once.with(
          prebuild_configuration_id: configuration.id,
          repository: repo,
          location: "WestUs2",
          vscs_target: :production,
        )

        Codespaces::UpdatePrebuildTemplate.call(guid: prebuild_template.guid, repository: repo, state: state)
      end

      test "Performs clean up job if vscs_target isn't nil" do
        repo = create(:repository, from_example: :simple)
        state = "archived"
        vscs_target_url = "http://localhost.example.com/",
        configuration = create(:codespace_prebuild_configuration, repository: repo, vscs_target: :ppe)

        prebuild_template = create(:codespace_prebuild_template, :ppe, repository: repo, codespace_prebuild_configuration_id: configuration.id)

        Codespaces::UpdatePrebuildTemplateVersionsJob.expects(:perform_later).with(
          prebuild_configuration_id: configuration.id,
          repository: repo,
          location: "CanadaCentral",
          vscs_target: :ppe,
        )

        Codespaces::UpdatePrebuildTemplate.call(guid: prebuild_template.guid, repository: repo, state: state)
      end

      test "Find the right configuration if there are multiple vscs_targets" do
        repo = create(:repository, from_example: :simple)
        state = "archived"

        prod_config = create(:codespace_prebuild_configuration, repository: repo, vscs_target: :production)
        ppe_config = create(:codespace_prebuild_configuration, repository: repo, vscs_target: :ppe)
        dev_config = create(:codespace_prebuild_configuration, repository: repo, vscs_target_url: "https://codespaces.servicebus.windows.net/monalisa",  vscs_target: :local)

        prebuild_template = create(:codespace_prebuild_template, :ppe, repository: repo, codespace_prebuild_configuration_id: ppe_config.id)

        Codespaces::UpdatePrebuildTemplateVersionsJob.expects(:perform_later).with(
          prebuild_configuration_id: ppe_config.id,
          repository: repo,
          location: "CanadaCentral",
          vscs_target: :ppe,
        )

        Codespaces::UpdatePrebuildTemplate.call(guid: prebuild_template.guid, repository: repo, state: state)
      end

      test "Find the right configuration when there are multiple templates with different dev container paths for a configuration" do
        repo = create(:repository, from_example: :simple)

        locations = ["WestUs2"]
        state = "archived"

        devcontainer_path1 = ".devcontainer/devcontainer.json"
        devcontainer_path2 = ".devcontainer/custom/devcontainer.json"
        prebuild_config1 = create(:codespace_prebuild_configuration, repository: repo, devcontainer_path: devcontainer_path1)
        prebuild_config2 = create(:codespace_prebuild_configuration, repository: repo, devcontainer_path: devcontainer_path2)

        prebuild_template_with_default_devcontainer = create(:codespace_prebuild_template, repository: repo, devcontainer_path: devcontainer_path1, codespace_prebuild_configuration_id: prebuild_config1.id)
        prebuild_template_with_custom_devcontainer1 = create(:codespace_prebuild_template, repository: repo, devcontainer_path: devcontainer_path2, codespace_prebuild_configuration_id: prebuild_config2.id)

        Codespaces::UpdatePrebuildTemplateVersionsJob.expects(:perform_later).with(
          prebuild_configuration_id: prebuild_template_with_custom_devcontainer1.codespace_prebuild_configuration_id,
          repository: repo,
          location: "WestUs2",
          vscs_target: prebuild_template_with_custom_devcontainer1.vscs_target,
        )

        Codespaces::UpdatePrebuildTemplate.call(guid: prebuild_template_with_custom_devcontainer1.guid, repository: repo, state: state)
      end
    end
  end
end unless GitHub.enterprise?
