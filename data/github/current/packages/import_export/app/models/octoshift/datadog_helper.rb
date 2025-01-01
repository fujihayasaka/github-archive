# typed: true
# frozen_string_literal: true

module Octoshift
  class DatadogHelper
    def self.send_service_unavailable_stats(owner)
      if owner.is_a?(Organization)
        tags = ["customer_org_id:#{owner.id}"]
      elsif owner.is_a?(Business)
        tags = ["customer_enterprise_id:#{owner.id}"]
      else
        return
      end

      increment("octoshift.importer.unavailable", tags: tags)
    end

    def self.increment(metric_name, tags: [])
      GitHub.dogstats.increment(metric_name, tags: tags)
    end
  end
end
