# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("advanced_security.enabled") do |payload|
    message = {
      repository_id: payload[:repository_id],
      feature_enabled: true,
      customer_id: payload[:customer_id]
    }

    Hydro::PublishRetrier.publish(
      message,
      partition_key: payload[:repository_id],
      schema: "github.security_center.v0.AdvancedSecurityToggled",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
    )
  end

  subscribe("advanced_security.disabled") do |payload|
    message = {
      repository_id: payload[:repository_id],
      feature_enabled: false,
      customer_id: payload[:customer_id]
    }

    Hydro::PublishRetrier.publish(
      message,
      partition_key: payload[:repository_id],
      schema: "github.security_center.v0.AdvancedSecurityToggled",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
    )
  end

  subscribe("advanced_security_trial.toggled") do |payload|
    message = {
      enterprise_id: payload[:enterprise_id],
      organization_id: payload[:organization_id],
      action: payload[:action],
      trial_sku: payload[:trial_sku],
      converted_to_paid: payload[:converted_to_paid],
      start_method: payload[:start_method],
      sfdc_poc_url: payload[:sfdc_poc_url],
      total_committers: payload[:total_committers],
      code_security_committers_active: payload[:code_security_committers_active],
      secret_protection_committers_active: payload[:secret_protection_committers_active],
      total_repos: payload[:total_repos],
      code_security_repos_enabled: payload[:code_security_repos_enabled],
      code_scanning_pr_reviews_enabled: payload[:code_scanning_pr_reviews_enabled],
      code_scanning_auto_codeql_enabled: payload[:code_scanning_auto_codeql_enabled],
      dependabot_alerts_enabled: payload[:dependabot_alerts_enabled],
      dependabot_security_updates_enabled: payload[:dependabot_security_updates_enabled],
      secret_protection_repos_enabled: payload[:secret_protection_repos_enabled],
      secret_scanning_push_protection_enabled: payload[:secret_scanning_push_protection_enabled],
      reset_all_private_repos: payload[:reset_all_private_repos],
    }

    Hydro::PublishRetrier.publish(
      message,
      partition_key: payload[:enterprise_id] || payload[:organization_id],
      schema: "github.advanced_security.v0.AdvancedSecurityTrialToggled",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
    )
  end
end
