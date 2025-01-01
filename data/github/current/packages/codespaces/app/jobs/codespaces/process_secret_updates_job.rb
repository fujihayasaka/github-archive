# typed: true
# frozen_string_literal: true
module Codespaces

  # Background job to find the codespaces impacted by a secret change,
  # and to asynchronously fire a secret update job for each of them.
  class ProcessSecretUpdatesJob < CodespacesJob
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    protected

    def process_codespaces(codespaces:)
      return if Codespaces::Policy.secrets_disabled?

      codespaces.each do |codespace|
        next if codespace.environment_data.nil?
        next unless codespace.environment_data.state == Vscs::State::AVAILABLE
        UpdateSecretsForCodespaceJob.perform_later(codespace: codespace)
      end
    end
  end
end
