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
    customer_id = payload[:customer_id]
    unless customer_id
      billable_entity = if payload[:enterprise_id]
        Business.find_by(id: payload[:enterprise_id])
      elsif payload[:organization_id]
        Organization.find_by(id: payload[:organization_id])
      end
      customer_id = Licensing::Customer.id_for(billable_entity) if billable_entity
    end

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
      customer_id: customer_id,
      trial_start_date: payload[:trial_start_date] ? Google::Protobuf::Timestamp.new(seconds: payload[:trial_start_date].to_time.to_i, nanos: 0) : nil,
      trial_end_date: payload[:trial_end_date] ? Google::Protobuf::Timestamp.new(seconds: payload[:trial_end_date].to_time.to_i, nanos: 0) : nil,
      secret_protection_retained_private_repos: payload[:secret_protection_retained_private_repos],
      code_security_retained_private_repos: payload[:code_security_retained_private_repos],
      secret_protection_retained_committers: payload[:secret_protection_retained_committers],
      code_security_retained_committers: payload[:code_security_retained_committers],
    }

    Hydro::PublishRetrier.publish(
      message,
      partition_key: payload[:enterprise_id] || payload[:organization_id],
      schema: "github.advanced_security.v0.AdvancedSecurityTrialToggled",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
    )
  end
end
