# typed: true
# frozen_string_literal: true

class BackgroundJobQueues
  class ConfigurationEvaluationContext
    class << self
      delegate :evaluation_context, to: :new
    end

    def metered_billing_lowworker_pool_workers
      ENV.fetch("BILLING_WORKERS", 4).to_i
    end

    def maintenance_queue_host_short_name
      GitHub.local_host_name_short
    end

    def page_enterprise_worker_configuration
      %w[true 1].include?(ENV["ENTERPRISE_IS_REPLICA"]) ? false : "low"
    end

    def evaluation_context
      binding
    end
  end
end
