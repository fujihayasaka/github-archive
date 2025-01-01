# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class UpdateSecretsForCodespaceJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @organization = create(:organization)
    @repository = create(:repository, owner: @organization)
    @repositories = [@repository]
    @codespace = create(:codespace, repository: @repository, billable_owner: @organization)
    @user = @codespace.owner
  end

  test "update secrets for codespace" do
    Codespaces::UpdateUserSecrets.expects(:call).with(codespace: @codespace).once

    Codespaces::UpdateSecretsForCodespaceJob.perform_now(codespace: @codespace)
  end

  test "retries when codespace's environment is not in the correct state" do
    assert_retry_on_error(Codespaces::VscsClient::InvalidSecretUpdatingStateError, Codespaces::UpdateSecretsForCodespaceJob, [{ codespace: @codespace }])
  end
end unless GitHub.enterprise?
