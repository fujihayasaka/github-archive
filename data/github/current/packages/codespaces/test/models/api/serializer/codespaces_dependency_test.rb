# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class CodespacesDependencySerializersTest < Api::SerializerTestCase
  fixtures do
    @codespace = create(:codespace)
    @plan = @codespace.plan
  end

  context "#public_codespace_hash" do
    test "indicates the codespace is for a test account if flagged" do
      GitHub.flipper[:codespaces_automated_testing].enable(@codespace.owner)
      serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: @codespace })
      output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
      assert output["test_account"]
    end

    test "does not include `test_account` when not flagged" do
      GitHub.flipper[:codespaces_automated_testing].disable(@codespace.owner)
      # output = public_codespace({ codespace: @codespace })
      serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: @codespace })
      output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
      refute output.key?("test_account")
    end

    test "indicates the codespace's devcontainer path" do
      codespace = create(:codespace, owner: @codespace.owner, devcontainer_path: ".devcontainer.json")

      serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: codespace })
      output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
      assert_equal ".devcontainer.json", output["devcontainer_path"]
    end

    test "does not include `failure_reason` when not present" do
      serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: @codespace })
      output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
      refute output.key?("failure_reason")
    end

    test "includes `failure_reason`` if present" do
      @codespace.merge_environment_data!(user_controlled_failure_reason: "SubnetOutOfIps")
      serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: @codespace })
      output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
      assert_equal "SubnetOutOfIps", output["failure_reason"]
    end

    context "idle_timeout_notice" do
      test "is included if has_max_idle_timeout_policy_override exists" do
        repo = create(:private_repository, owner: create(:codespaces_organization, plan: GitHub::Plan.business))

        codespace = create(:codespace, repository: repo, owner: @codespace.owner, environment_data: {
          auto_shutdown_delay_minutes: 60
        })
        Codespaces::MaximumIdleTimeoutPolicy.set_has_override_key!(codespace.id)

        serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: codespace })
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
        assert_equal output["idle_timeout_notice"], "Idle timeout for this codespace is set to 60 minutes in compliance with your organization's policy"
      end

      test "is not included if has_max_idle_timeout_policy_override does not exist" do
        repo = create(:private_repository, owner: create(:organization))

        codespace = create(:codespace, repository: repo, owner: @codespace.owner, environment_data: {
          auto_shutdown_delay_minutes: 60
        })

        refute Codespaces::MaximumIdleTimeoutPolicy.has_override?(codespace.id)

        serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: codespace })
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
        refute output["idle_timeout_notice"]
      end
    end

    context "last_known_stop_notice" do
      test "is included if last_known_stop_notice exists" do
        GitHub.flipper[:codespaces_automated_testing].enable(@codespace.owner)
        last_known_stop_notice = "spending_limit_reached"
        serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: @codespace, last_known_stop_notice: last_known_stop_notice })
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))

        assert_equal last_known_stop_notice, output["last_known_stop_notice"]
      end

      test "is not included if last_known_stop_notice does not exist" do
        GitHub.flipper[:codespaces_automated_testing].enable(@codespace.owner)
        serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: @codespace })
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))

        refute output["last_known_stop_notice"]
      end
    end

    context "auto_push" do
      test "is included if auto_push is set to true" do
        codespace = build(:codespace, environment_data: { git_status: { "autoPush": true } })
        serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: codespace })
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
        assert output["git_status"]["auto_push"]
      end

      test "is not included if auto_push is set to false" do
        codespace = build(:codespace, environment_data: { git_status: { "autoPush": false } })
        serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: @codespace })
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
        refute output["git_status"]["auto_push"]
      end

      test "is not included if auto_push does not exist" do
        codespace = build(:codespace, environment_data: { git_status: {} })
        serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: @codespace })
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
        refute output["git_status"]["auto_push"]
      end

      test "is not included if git_status does not exist" do
        codespace = build(:codespace)
        serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: @codespace })
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
        refute output["git_status"]["auto_push"]
      end
    end

    context "using_copilot_workspace_config" do
      test "is included if using_copilot_workspace_config is set to true" do
        @codespace.merge_environment_data!(using_copilot_workspace_config: true)
        serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: @codespace })
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
        assert output["using_copilot_workspace_config"]
      end

      test "is not included if using_copilot_workspace_config is set to false" do
        @codespace.merge_environment_data!(using_copilot_workspace_config: false)
        serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: @codespace })
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
        refute output["using_copilot_workspace_config"]
      end

      test "is not included if using_copilot_workspace_config does not exist" do
        serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: @codespace })
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
        refute output["using_copilot_workspace_config"]
      end
    end

    test "includes publish_url for an unpublished codespace" do
      unpublished_codespace = create(:unpublished_codespace)

      serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: @codespace })
      output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
      assert_nil output["publish_url"]

      @codespace.template_repository_id = @codespace.repository_id
      serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: unpublished_codespace })
      output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
      refute_nil output["publish_url"]
    end

    test "includes template for an unpublished codespace" do
      unpublished_codespace = create(:unpublished_codespace)

      serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: @codespace })
      output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
      assert_nil output["template"]

      serialized_output = Api::Serializer.serialize(:public_codespace_hash, { codespace: unpublished_codespace })
      output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
      refute_nil output["template"]
      # Factory sets the template's name to the repo's name.
      assert_equal unpublished_codespace.template_repository.name, output["template"]["name"]
      assert_equal unpublished_codespace.template_repository.nwo, output["template"]["repository"]["full_name"]
    end
  end

  context "#codespace_hash" do
    test "passes the plan's vscs_target if it's not production" do
      (Codespaces::Vscs.targets - [:production]).each do |vscs_target|
        @plan.update!(vscs_target: vscs_target)
        codespace_data = { vscs_target: vscs_target, vscs_target_url: T.let(nil, T.nilable(String)) }
        codespace_data[:vscs_target_url] = "https://codespaces.servicebus.windows.net/monalisa" if vscs_target == :local
        @codespace.update!(codespace_data)
        serialized_output = Api::Serializer.serialize(:codespace_hash, { codespace: @codespace.reload })
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
        assert_equal vscs_target.to_s, output["vscs_target"]
      end
    end

    test "passes the plan's vscs_target if it is production" do
      @plan.update(vscs_target: :production)
      @codespace.update(vscs_target: :production)

      serialized_output = Api::Serializer.serialize(:codespace_hash, { codespace: @codespace })
      output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
      assert_nil output["vscs_target"]
    end

    test "passes the the API URL as vscs_target_url if one not provided" do
      (Codespaces::Vscs.targets - [:local]).each do |vscs_target|
        @plan.update!(vscs_target: vscs_target)
        @codespace.update!(vscs_target: vscs_target)

        serialized_output = Api::Serializer.serialize(:codespace_hash, { codespace: @codespace.reload })
        output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
        assert_equal Codespaces::Vscs.config_for_target(vscs_target)[:api_url], output["vscs_target_url"]
      end
    end

    test "doesn't change the vscs_target_url if already provided" do
      vscs_target = :local
      vscs_target_url = "https://codespaces.servicebus.windows.net/monalisa"
      @plan.update!(vscs_target: vscs_target)
      @codespace.update!(vscs_target: vscs_target, vscs_target_url: vscs_target_url)

      serialized_output = Api::Serializer.serialize(:codespace_hash, { codespace: @codespace.reload })
      output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))
      assert_equal vscs_target_url, output["vscs_target_url"]
    end
  end

  context "#codespaces_permissions_check_hash" do
    test "returns the provided values" do
      example_devcontainer_path = ".devcontainer/.devcontainer.json"
      example_accepted_response = true

      serialized_output = Api::Serializer.serialize(:codespaces_permissions_check_hash, { accepted: example_accepted_response })
      output = GitHub::JSON.parse(GitHub::JSON.encode(serialized_output))

      assert_equal example_accepted_response, output["accepted"]
    end
  end
end unless GitHub.enterprise?
