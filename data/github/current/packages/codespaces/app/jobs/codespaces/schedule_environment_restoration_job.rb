# typed: true
# frozen_string_literal: true

class Codespaces::ScheduleEnvironmentRestorationJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

  retry_on Codespaces::Error, wait: :polynomially_longer, attempts: 15
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(codespace:)
    begin
      Codespaces::ScheduleEnvironmentRestoration.call(codespace)
    rescue Codespaces::ScheduleEnvironmentRestoration::UnrestorableEnvironmentError
      GitHub.logger.warn("Unrestorable environment", {
        "code.namespace" => "Codespaces::CodespacesScheduleEnvironmentRestorationJob",
        "code.function" => "perform",
        "gh.codespaces.name" => codespace.name,
        "gh.codespaces.guid" => codespace.guid,
      })
    end
  end
end
