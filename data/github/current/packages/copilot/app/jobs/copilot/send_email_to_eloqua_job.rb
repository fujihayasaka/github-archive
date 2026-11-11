# typed: true
# frozen_string_literal: true

class Copilot::SendEmailToEloquaJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  exempt_from_tenant_context_requirement

  def perform(args)
    GitHub.dogstats.increment("copilot.send_email_to_eloqua_job")
    Net::HTTP.post_form(URI(args[:uri]), "emailAddress" => args[:email])
  end
end
