# typed: true
# frozen_string_literal: true

namespace :enterprise do
  namespace :dependabot_alerts do
    # Create the Dependabot Alerts default (global) auto-dismissal rules on an instance of GHES.
    #
    # This is run via `ghe-run-migrations`
    task create_default_rule: [:environment] do
      next unless GitHub.enterprise? || Rails.env.development?

      VulnerabilityAlertRule.create_default_auto_dismissal_rule
      VulnerabilityAlertRule.create_default_malware_package_dismissal_rule
    end
  end
end
