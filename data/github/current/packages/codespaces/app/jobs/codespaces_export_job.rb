# typed: true
# frozen_string_literal: true

class CodespacesExportJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

  retry_on Codespaces::Error, wait: :polynomially_longer
  retry_on Codespaces::Export::EnvNotSuspendedError, Codespaces::Export::EnvStillSuspendingError, wait: :polynomially_longer, attempts: 10
  retry_on_dirty_exit

  def perform(codespace:, encrypted_token:, key_version: nil, actor: nil, new_repository_origin: nil)
    github_token = Codespaces::Tokens.decrypt_github_token(encrypted_token, key_version: key_version)

    begin
      Codespaces::Export.call(codespace, github_token, actor: actor, new_repository_origin: new_repository_origin)
    rescue Codespaces::Export::EnvNotSuspendedError
      Codespaces::SuspendEnvironment.call(codespace)
      raise
    # NoOp if we're already exporting
    rescue Codespaces::Export::EnvAlreadyExportingError
    end
  end
end
