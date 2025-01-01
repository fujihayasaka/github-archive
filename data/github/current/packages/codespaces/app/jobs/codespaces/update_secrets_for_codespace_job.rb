# typed: true
# frozen_string_literal: true
module Codespaces

  # Background job to update user secrets for a given codespace.
  class UpdateSecretsForCodespaceJob < CodespacesJob
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

    retry_on_dirty_exit
    retry_on_recoverable_exceptions
    # methods called bottom to top
    discard_on Codespaces::VscsClient::InvalidSecretUpdatingStateError
    retry_on Codespaces::VscsClient::InvalidSecretUpdatingStateError, wait: 5.seconds, attempts: 6

    def perform(codespace:)
      UpdateUserSecrets.call(codespace: codespace)
    end
  end
end
