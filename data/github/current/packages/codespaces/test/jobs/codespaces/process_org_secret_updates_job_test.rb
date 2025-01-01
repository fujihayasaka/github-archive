# typed: true
# frozen_string_literal: true

require "test_helper"

class ProcessOrgSecretUpdatesJobTest < GitHub::TestCase

  fixtures do
    @organization = create(:codespaces_organization, plan: GitHub::Plan.business)
    @repository = create(:repository, owner: @organization)
    @repositories = [@repository]
    @codespace = create(:codespace, repository: @repository, billable_owner: @organization)
  end

  setup do
    GitHub.flipper[:disable_codespaces_secrets].disable
  end

  test "an org secret is modified" do
    Codespaces::Policy.expects(:can_receive_secrets?).returns(true)
    repository_ids = selected_repository_global_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1].to_i }
    expected = Codespace.where(billable_owner: @organization, repository: repository_ids)
    assert expected.present?
    expected.each do |codespace|
      Codespaces::UpdateSecretsForCodespaceJob.expects(:perform_later).with(codespace: codespace)
    end

    Codespaces::ProcessOrgSecretUpdatesJob.perform_now(selected_repository_global_ids: selected_repository_global_ids, org: @organization)
  end

  test "do not process if codespace state is not AVAILABLE" do
    Codespaces::UpdateSecretsForCodespaceJob.expects(:perform_later).never
    shutdown_codespace = create(:codespace, billable_owner: @organization, repository: @repository)
    shutdown_codespace.environment_data.state = Codespaces::Vscs::State::SHUTDOWN
    Codespace.expects(:where).returns([shutdown_codespace])

    Codespaces::ProcessOrgSecretUpdatesJob.perform_now(selected_repository_global_ids: selected_repository_global_ids, org: @organization)
  end

  test "do not process if codespace environment_data is nill" do
    Codespaces::UpdateSecretsForCodespaceJob.expects(:perform_later).never
    a_codespace = create(:codespace, billable_owner: @organization, repository: @repository)
    a_codespace.environment_data = nil
    Codespace.expects(:where).returns([a_codespace])

    Codespaces::ProcessOrgSecretUpdatesJob.perform_now(selected_repository_global_ids: selected_repository_global_ids, org: @organization)
  end

  test "do not update secret if can_receive_secrets policy returns false" do
    Codespaces::Policy.expects(:can_receive_secrets?).returns(false)
    Codespaces::UpdateSecretsForCodespaceJob.expects(:perform_later).never

    Codespaces::ProcessOrgSecretUpdatesJob.perform_now(selected_repository_global_ids: selected_repository_global_ids, org: @organization)
  end

  def selected_repository_global_ids
    @repositories.map(&:global_relay_id)
  end
end unless GitHub.enterprise?
