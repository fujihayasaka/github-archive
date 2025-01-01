# typed: true
# frozen_string_literal: true

# See EmailDomainReputationRecord for more details.
class ProcessEmailDomainForReputationDataJob < ApplicationJob
  queue_as :spam

  retry_on_dirty_exit

  # Only run one job per unique domain at a time.
  locked_by timeout: 1.hour, key: -> (job) { "process_email_domain_for_reputation_data::#{job.arguments[0]}" }

  # Don't run on enterprise
  around_enqueue do |_job, block|
    if GitHub.spamminess_check_enabled?
      block.call
    end
  end

  def perform(domain)
    SlowQueryLogger.disabled do
      with_write { EmailDomainReputationRecord.process(domain) }
    end
  end
end
