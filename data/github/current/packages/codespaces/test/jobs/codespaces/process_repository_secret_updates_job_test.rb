# typed: true
# frozen_string_literal: true

require "test_helper"

class ProcessRepositorySecretUpdatesJobTest < GitHub::TestCase

  fixtures do
    @repository = create(:repository)
    @codespace = create(:codespace, repository: @repository)
  end

  setup do
    GitHub.flipper[:disable_codespaces_secrets].disable
  end

  test "a repository secret is modified" do
    Codespaces::Policy.expects(:can_receive_secrets?).returns(true)
    expected = Codespace.where(repository: @repository)
    expected.each do |codespace|
      Codespaces::UpdateSecretsForCodespaceJob.expects(:perform_later).with(codespace: codespace)
    end

    Codespaces::ProcessRepositorySecretUpdatesJob.perform_now(repository: @repository)
  end

  test "do not process if codespace state is not AVAILABLE" do
    Codespaces::UpdateSecretsForCodespaceJob.expects(:perform_later).never
    shutdown_codespace = create(:codespace, billable_owner: @organization, repository: @repository)
    shutdown_codespace.environment_data.state = Codespaces::Vscs::State::SHUTDOWN
    Codespace.expects(:where).returns([shutdown_codespace])

    Codespaces::ProcessRepositorySecretUpdatesJob.perform_now(repository: @repository)
  end

  test "do not process if codespace environment_data is nill" do
    Codespaces::UpdateSecretsForCodespaceJob.expects(:perform_later).never
    a_codespace = create(:codespace, billable_owner: @organization, repository: @repository)
    a_codespace.environment_data = nil
    Codespace.expects(:where).returns([a_codespace])

    Codespaces::ProcessRepositorySecretUpdatesJob.perform_now(repository: @repository)
  end

  test "do not update secret if can_receive_secrets policy returns false" do
    Codespaces::Policy.expects(:can_receive_secrets?).returns(false)
    Codespaces::UpdateSecretsForCodespaceJob.expects(:perform_later).never

    Codespaces::ProcessRepositorySecretUpdatesJob.perform_now(repository: @repository)
  end
end
