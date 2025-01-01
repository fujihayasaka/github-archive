# typed: true
# frozen_string_literal: true

require "github/launch_client"
require "test_helper"
require "test_helpers/secrets_test_helpers"

module Codespaces
  class CreatePrebuildTemplateTest < GitHub::TestCase
    include SecretsTestHelper
    include CodespacesPlanFixtures
    include ::Billing::CodespacesUsageHelpers

    fixtures do
      # use non default path to ensure we are using path from environment options rather than default path
      @devcontainer_path = ".devcontainer/custom/devcontainer.json"

      make_trusted_oauth_apps_owner
      @user = create(:user)
      enable_feature_flag(:codespaces_developer, @user)
      @org = create(:codespaces_organization, admin: @user)
      @repo = create_base_repository
      @branch = "master"
      @workflow_run_id = "3"
      @oid = @repo.refs.find("master").sha

      @integration = create(:codespaces_integration)
      @total_time_saving = "1"
      @template_size = 10.0
      @container_id = "123"
      @schema_version = "0"
      @image_name = "image"

      @template_info = {
        "total_time_saving" => @total_time_saving,
        "template_size" => @template_size,
        "container" => {
          "id" => @container_id,
          "schema_version" => @schema_version,
          "image_name" => @image_name,
        },
      }
      @environment_options = { "template_info" => @template_info, "devcontainer_path" => @devcontainer_path }

      # The existence of a prebuild template determines whether prebuilds are enable
      @prebuild_configuration = create(:codespace_prebuild_configuration, repository: @repo, branch: @branch, devcontainer_path: @devcontainer_path)
    end

    setup do
      @command_args = {
        repository: @repo,
        location: "WestUs2",
        oid: @oid,
        branch: @branch,
        environment_options: @environment_options,
        workflow_run_id: @workflow_run_id,
        configuration_id: @prebuild_configuration.id,
      }
    end

    context "#validate!", skip_enterprise: true do
      test "raises when passing a vscs_target_url but the user isn't a codespaces developer" do
        assert_raises Codespaces::ValidatePrebuildAccess::AuthorizationError do
          Codespaces::CreatePrebuildTemplate.call(
            **@command_args.merge(
              {
                vscs_target_url: "http://myevilurl.com/evil",
              }
            )
          )
        end
      end

      test "raises when passing a vscs_target_url but the vscs_target isn't `local`" do
        enable_feature_flag(:codespaces_developer)

        assert_raises Codespaces::CreatePrebuildTemplate::InvalidPrebuildTemplate do
          Codespaces::CreatePrebuildTemplate.call(
            **@command_args.merge(
              {
                vscs_target_url: "localhost:3000",
                vscs_target: "production",
              }
            )
          )
        end
      end

      test "does not raise error when passing a vscs_target_url and the vscs_target `local`" do
        enable_feature_flag(:codespaces_developer)

        vscs_target_host = "online.dev.core.vsengsaas.visualstudio.com"
        @prebuild_configuration.update(vscs_target: "local", vscs_target_url: "https://#{vscs_target_host}")

        FakeVSOServer.reset!
        Codespaces::CreatePrebuildTemplate.call(
          **@command_args.merge({
            vscs_target_url: "https://#{vscs_target_host}",
            vscs_target: "local"
          })
        )

        request = FakeVSOServer.requests.last
        assert_includes request.env["HTTP_HOST"], vscs_target_host
      end

      test "raises when the org hasn't enabled codespaces" do
        disable_feature_flag(:codespaces_billing_free)

        @org.pending_plan_changes.create!(
          active_on: Time.now,
          plan: GitHub::Plan.free,
          actor: @org.admin,
        ).run

        assert_raises Codespaces::CreatePrebuildTemplate::FeatureNotSupported do
          Codespaces::CreatePrebuildTemplate.call(
            **@command_args
          )
        end
      end
    end

    context "#perform", skip_enterprise: true do
      test "sends the expected request to vscs's prebuild template endpoint" do
        FakeVSOServer.reset!

        Codespaces::CreatePrebuildTemplate.call(
          **@command_args
        )

        request = FakeVSOServer.requests.last
        request_body = GitHub::JSON.parse(request.body)
        assert_equal "/api/v2/prebuilds/templates", request.path
        assert_equal @repo.permalink, request_body["seed"]["moniker"]
      end

      test "raises when passing a vscs_target_url but the vscs_target isn't `local`" do
        enable_feature_flag(:codespaces_developer)

        Codespaces::CreatePrebuildTemplate.any_instance.expects(:validate!).returns(nil)
        FakeVSOServer.reset!
        err = assert_raises Codespaces::CreatePrebuildTemplate::InvalidPrebuildTemplate do
          Codespaces::CreatePrebuildTemplate.call(
            **@command_args.merge(vscs_target: :production, vscs_target_url: "should_fail")
          )
        end
        assert_equal "Invalid prebuild template: Vscs target url must be blank when vscs_target is not local", err.message
      end

      test "Passes params to the the response" do
        FakeVSOServer.reset!
        Codespaces::CreatePrebuildTemplate.call(
          **@command_args
        )

        request = FakeVSOServer.requests.last
        request_body = GitHub::JSON.parse(request.body)
        assert_equal "/api/v2/prebuilds/templates", request.path
        refute_nil request_body["seed"]
        refute_nil request_body["templateInfo"]

        repository_data = request_body["seed"]["repository"]
        assert_equal repository_data["commit"], @oid
        assert_equal repository_data["branch"], @branch
        refute_nil request_body["friendlyName"]
        refute_nil repository_data["prebuild_hash"]

        template_data = request_body["templateInfo"]
        assert_equal @total_time_saving, template_data["totalTimeSavingsInSeconds"]
        assert_equal @template_size, template_data["templateSizeInGB"]
        assert_equal @container_id, template_data["container"]["id"]
        assert_equal @schema_version, template_data["container"]["schemaVersion"]
        assert_equal @image_name, template_data["container"]["imageName"]
      end

      test "Raise feature not supported when there is no prebuild configuration" do

        @prebuild_configuration.destroy

        assert_raises Codespaces::CreatePrebuildTemplate::FeatureNotSupported do
          Codespaces::CreatePrebuildTemplate.call(
            **@command_args
          )
        end
      end

      test "Passes repository seed data to the the response when prebuilds are configured" do
        FakeVSOServer.reset!
        Codespaces::Prebuilds.stubs(:configured?).returns(true)
        Codespaces::CreatePrebuildTemplate.call(
          **@command_args
        )

        request = FakeVSOServer.requests.last
        request_body = GitHub::JSON.parse(request.body)
        assert_equal "/api/v2/prebuilds/templates", request.path
        refute_nil request_body["seed"]["repository"]

        repository_data = request_body["seed"]["repository"]
        assert_equal repository_data["commit"], @oid
        assert_equal repository_data["branch"], @branch
        refute_nil request_body["friendlyName"]
        refute_nil repository_data["prebuild_hash"]
      end

      test "creates a new PrebuildTemplate instance" do
        assert_equal Codespaces::PrebuildTemplate.count, 0
        FakeVSOServer.reset!

        template, storage_sas_url = Codespaces::CreatePrebuildTemplate.call(
          **@command_args
        )

        assert_equal 1, Codespaces::PrebuildTemplate.count
        template = Codespaces::PrebuildTemplate.first
        assert_predicate template, :pending?
        assert_equal FakeVSOServer.prebuild_templates_created.first[:templateId], T.must(template).guid
        assert_equal Codespaces::PrebuildTemplate.count, 1
        assert_equal "testUrl", storage_sas_url
      end

      test "does not create a new environment when the PrebuildTemplate fails to be created with flag enabled" do
        assert_equal Codespaces::PrebuildTemplate.count, 0
        FakeVSOServer.reset!
        stubbed_client = mock
        stubbed_client.expects(:create_prebuild_template).raises(Codespaces::Client::TimeoutError)

        Codespaces::CreatePrebuildTemplate.any_instance.expects(:client).returns(stubbed_client)

        assert_raises Codespaces::Client::TimeoutError do
          Codespaces::CreatePrebuildTemplate.call(
          **@command_args
          )
        end
        assert_empty FakeVSOServer.prebuild_templates_created
        assert_empty FakeVSOServer.requests
        assert_equal Codespaces::PrebuildTemplate.count, 0
      end

      test "logs successful prebuild template creations" do
        FakeVSOServer.reset!

        logging_attrs = {
          "gh.repo.id" => @repo.id,
          "gh.repo.owner.login" => @repo.owner.display_login,
          "gh.codespaces.prebuilds.configuration.id" => @prebuild_configuration.id,
          "gh.codespaces.prebuild_hash" => Codespaces::CalculatePrebuildHash.call(repository: @repo, oid: @oid, devcontainer_path: @devcontainer_path),
          "gh.codespaces.prebuild.workflow_run_id" => @workflow_run_id,
          "gh.codespaces.location" => "WestUs2",
          "gh.codespaces.vscs_target" => :production,
          "code.namespace" => "Codespaces::CreatePrebuildTemplate",
        }

        GitHub.logger.expects(:info).with(
          "Codespaces Prebuild Create Template successfully completed",
          **logging_attrs
        )

        GitHub.logger.stubs(:info).with(anything, Not(equals(logging_attrs)))

        Codespaces::CreatePrebuildTemplate.call(
          **@command_args
        )
      end
    end

    test "raises when template info is not passed in the call" do
      FakeVSOServer.reset!
      @prebuild_configuration.update(devcontainer_path: nil)
      err = assert_raises Codespaces::CreatePrebuildTemplate::InvalidPrebuildTemplate do
        Codespaces::CreatePrebuildTemplate.call(
          repository: @repo,
          location: "WestUs2",
          oid: @oid,
          branch: @branch,
          environment_options: {},
          workflow_run_id: @workflow_run_id,
          configuration_id: @prebuild_configuration.id,
        )
      end
      assert_equal "Invalid prebuild template: template_info is required", err.message
    end

    private

    def create_base_repository
      repository = create(:repository, owner: @org, from_example: :simple)

      devcontainer_json = <<-JSON
        {
          "postCreateCommand": "post-create.sh",
          /*
            Multi
            Line
            Comment
          */
          "prebuildHashPaths": "other-file.txt",
          "onCreateCommand": "on-create-command.sh", // Single line comment and note the trailing comma
        }
      JSON

      repository.refs.find("master").append_commit({ message: "First!", committer: repository.owner }, repository.owner) do |files|
        # add non default path
        files.add(@devcontainer_path, devcontainer_json)
        files.add("post-create.sh", "#!/bin/sh")
        files.add("on-create-command.sh", "#!/bin/sh")
        files.add("other-file.txt", "")
        Codespaces::CalculatePrebuildHash::HASHED_FILES.each do |file|
          files.add(file, "")
        end
      end
      repository
    end
  end
end unless GitHub.enterprise?
