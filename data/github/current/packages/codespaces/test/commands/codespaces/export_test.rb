# typed: true
# frozen_string_literal: true
require "test_helper"

module Codespaces
  class ExportTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @codespace = create(:codespace, owner: @user)
      @active_codespace = create(:codespace, owner: @user)
      @suspending_codespace = create(:codespace, owner: @user)
      @exporting_codespace = create(:codespace, owner: @user)

      @github_token = SecureRandom.base64(32)
    end

    setup do
      FakeVSOServer.reset!
      FakeVSOServer.environments << { "id" => @codespace.guid, "state" => Vscs::State::SHUTDOWN }
      FakeVSOServer.environments << { "id" => @active_codespace.guid, "state" => Vscs::State::AVAILABLE }
      FakeVSOServer.environments << { "id" => @suspending_codespace.guid, "state" => Vscs::State::SHUTTING_DOWN }
      FakeVSOServer.environments << { "id" => @exporting_codespace.guid, "state" => Vscs::State::EXPORTING }
    end

    context "when not exporting" do
      test "it makes no API calls if a codespace is not exporting" do
        Codespaces::VscsClient.any_instance.expects(:export_environment).never
        Codespaces::Export.call(@codespace, @github_token)
      end
    end

    context "when the codespace is exporting", skip_enterprise: true do
      test "it deletes the export branch" do
        @codespace.touch(:last_export_start_at)
        @codespace.expects(:delete_export_branch).once

        Codespaces::Export.call(@codespace, @github_token)
      end

      test "it makes the appropriate API call" do
        @codespace.touch(:last_export_start_at)

        Codespaces::Export.call(@codespace, @github_token)

        assert_equal 1, FakeVSOServer.environments_exported.length
      end

      test "it send the correct exported enviroment info" do
        @codespace.touch(:last_export_start_at)
        new_origin = "http://github.com/example/repo.git"

        Codespaces::VscsClient
          .any_instance
          .expects(:export_environment)
          .with(
            @codespace.guid,
            branch_name: @codespace.export_branch_name,
            repository_name: @codespace.repository.name,
            token: @github_token,
            new_repository_origin: new_origin,
            failover_details: nil
          )
          .at_most_once

        Codespaces::Export.call(@codespace, @github_token, new_repository_origin: new_origin)
      end

      test "instruments audit log: codespaces.export_environment event" do
        @codespace.touch(:last_export_start_at)
        events = subscribe "codespaces.export_environment"
        user = create(:user)
        Codespaces::Export.call(@codespace, @github_token, actor: user)

        expected_payload = {
          owner_id: @codespace.owner.id,
          owner: @codespace.owner.login,
          codespace_id: @codespace.id,
          plan_id: @codespace.plan.id,
          environment_id: @codespace.guid,
          repo: @codespace.repository.nwo,
          repo_id: @codespace.repository.id,
          public_repo: @codespace.repository.public?,
          actor_id: user.id,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "fails when environment is not suspended" do
        @active_codespace.touch(:last_export_start_at)

        assert_raises Codespaces::Export::EnvNotSuspendedError do
          Codespaces::Export.call(@active_codespace, @github_token)
        end

        assert_equal 0, FakeVSOServer.environments_exported.length
      end

      test "fails when environment is still suspending" do
        @suspending_codespace.touch(:last_export_start_at)

        assert_raises Codespaces::Export::EnvStillSuspendingError do
          Codespaces::Export.call(@suspending_codespace, @github_token)
        end

        assert_equal 0, FakeVSOServer.environments_exported.length
      end

      test "skips export if already exporting" do
        @exporting_codespace.touch(:last_export_start_at)

        Codespaces::VscsClient.any_instance.expects(:export_environment).never
        assert_raises Codespaces::Export::EnvAlreadyExportingError do
          Codespaces::Export.call(@exporting_codespace, @github_token)
        end
      end
    end

    context "setting failover_details" do
      test "is passed to vscs" do
        @codespace.touch(:last_export_start_at)
        new_origin = "http://github.com/example/repo.git"

        failover_details = { failoverEnabled: true, failoverRegion: "westeurope" }

        Codespaces::GetFailoverDetails
          .expects(:call)
          .with(region: @codespace.location, user: @user, vscs_target: @codespace.vscs_target, is_copilot_workspace: @codespace.copilot_workspace?)
          .returns(failover_details)

        Codespaces::VscsClient
          .any_instance
          .expects(:export_environment)
          .with(
            @codespace.guid,
            branch_name: @codespace.export_branch_name,
            repository_name: @codespace.repository.name,
            token: @github_token,
            new_repository_origin: new_origin,
            failover_details: failover_details
          )
          .at_most_once

        Codespaces::Export.call(@codespace, @github_token, new_repository_origin: new_origin, actor: @user)
      end
    end
  end
end
