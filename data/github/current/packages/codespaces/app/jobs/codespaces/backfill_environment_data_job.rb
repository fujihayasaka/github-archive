# typed: true
# frozen_string_literal: true

class Codespaces::BackfillEnvironmentDataJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(codespace:)
    return if codespace.guid.blank?

    client = Codespaces::VscsClient.for_codespace(codespace)
    environment_data = client.fetch_environment!(codespace.guid)
    with_write do
      Codespace.throttle_with_retry { codespace.update(environment_data: environment_data) if environment_data.present? }
    end
  end
end
