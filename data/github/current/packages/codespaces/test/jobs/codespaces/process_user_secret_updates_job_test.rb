# typed: true
# frozen_string_literal: true

require "test_helper"

class ProcessSecretUpdatesJobTest < GitHub::TestCase

  fixtures do
    @repository = create(:repository)
    @repositories = [@repository]
    @codespace = create(:codespace, repository: @repository, billable_owner: @organization)
    @user = @codespace.owner
  end

  setup do
    GitHub.flipper[:disable_codespaces_secrets].disable
  end

  test "a user secret is modified" do
    repository_ids = selected_repository_global_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1].to_i }
    expected = Codespace.where(owner: @user, repository: repository_ids)
    assert expected.present?
    expected.each do |codespace|
      Codespaces::UpdateSecretsForCodespaceJob.expects(:perform_later).with(codespace: codespace)
    end

    Codespaces::ProcessUserSecretUpdatesJob.perform_now(selected_repository_global_ids: selected_repository_global_ids, user: @user)
  end

  test "do not process if codespace state is not AVAILABLE" do
    Codespaces::UpdateSecretsForCodespaceJob.expects(:perform_later).never
    shutdown_codespace = create(:codespace, billable_owner: @organization, repository: @repository)
    shutdown_codespace.environment_data.state = Codespaces::Vscs::State::SHUTDOWN
    Codespace.expects(:where).returns([shutdown_codespace])

    Codespaces::ProcessUserSecretUpdatesJob.perform_now(selected_repository_global_ids: selected_repository_global_ids, user: @user)
  end

  test "do not process if codespace environment_data is nill" do
    Codespaces::UpdateSecretsForCodespaceJob.expects(:perform_later).never
    a_codespace = create(:codespace, billable_owner: @organization, repository: @repository)
    a_codespace.environment_data = nil
    Codespace.expects(:where).returns([a_codespace])

    Codespaces::ProcessUserSecretUpdatesJob.perform_now(selected_repository_global_ids: selected_repository_global_ids, user: @user)
  end

  def selected_repository_global_ids
    @repositories.map(&:global_relay_id)
  end
end
