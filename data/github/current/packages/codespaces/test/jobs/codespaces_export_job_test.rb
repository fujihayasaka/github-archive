# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodespacesExportJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @user = create(:user)
    @codespace = create(:codespace, owner: @user)
    @active_codespace = create(:codespace)
    @suspending_codespace = create(:codespace)
    @exporting_codespace = create(:codespace)
    @plaintext_token = "Some fake token"
    Codespaces::Tokens.expects(:mint_github_token).returns(@plaintext_token)
    @github_token, @key_version = Codespaces::Tokens.mint_encrypted_github_token(@user, @codespace)
    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => @codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }
    FakeVSOServer.environments << { "id" => @active_codespace.guid, "state" => Codespaces::Vscs::State::AVAILABLE }
    FakeVSOServer.environments << { "id" => @suspending_codespace.guid, "state" => Codespaces::Vscs::State::SHUTTING_DOWN }
    FakeVSOServer.environments << { "id" => @exporting_codespace.guid, "state" => Codespaces::Vscs::State::EXPORTING }
  end

  context "GitHub tokens are encrypted when enqueued as a job", skip_enterprise: true do
    test "GitHub token can't be read in logs or out of db of queued job" do
      @codespace.export!(@github_token, key_version: @key_version)

      refute_equal enqueued_jobs.first["arguments"].first["encrypted_token"], @plaintext_token
    end

    test "GitHub token is decrypted inside job before exporting" do
      perform_enqueued_jobs(only: CodespacesExportJob) do
        decrypted_token = @plaintext_token
        Codespaces::Export.expects(:call).with(@codespace, decrypted_token, actor: nil, new_repository_origin: nil)
        @codespace.export!(@github_token, key_version: @key_version)
      end
    end
  end

  context "Codespaces get suspended on if not already before exporting", skip_enterprise: true do
    test "job is retried and codespace is suspended on active codespace" do
      @active_codespace.exporting!
      Codespaces::SuspendEnvironment.expects(:call).with(@active_codespace)

      CodespacesExportJob.any_instance.expects(:retry_job)

      assert_nothing_raised do
        perform_enqueued_jobs(only: [CodespacesExportJob]) do
          CodespacesExportJob.perform_later(codespace: @active_codespace, encrypted_token: @github_token, key_version: @key_version)
        end
      end
    end

    test "job is retried but suspend is not called when codespace is already suspending" do
      @suspending_codespace.exporting!
      Codespaces::SuspendEnvironment.expects(:call).never

      CodespacesExportJob.any_instance.expects(:retry_job)

      assert_nothing_raised do
        perform_enqueued_jobs(only: [CodespacesExportJob]) do
          CodespacesExportJob.perform_later(codespace: @suspending_codespace, encrypted_token: @github_token, key_version: @key_version)
        end
      end
    end

    test "Job no-ops if codespace is already exporting" do
      @exporting_codespace.exporting!
      Codespaces::SuspendEnvironment.expects(:call).never

      CodespacesExportJob.any_instance.expects(:retry_job).never

      assert_nothing_raised do
        perform_enqueued_jobs(only: [CodespacesExportJob]) do
          CodespacesExportJob.perform_later(codespace: @exporting_codespace, encrypted_token: @github_token)
        end
      end
    end
  end
end unless GitHub.enterprise?
