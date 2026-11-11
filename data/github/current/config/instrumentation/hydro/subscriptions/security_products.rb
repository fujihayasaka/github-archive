# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("security_products.organization_advanced_security_license_toggled_per_repository") do |payload|
    original_payload = ::Hydro::Schemas::Github::SecurityCenter::V0::OrganizationAdvancedSecurityLicenseToggled.new(payload[:original_message])

    message = {
      repository_id: payload[:repository_id],
      organization_advanced_security_license_toggled: {
        organization_id: original_payload.organization_id,
        enabled: original_payload.enabled,
        enterprise_advanced_security_license_toggled: original_payload.enterprise_advanced_security_license_toggled,
        license_toggled_for_org_at: original_payload.license_toggled_for_org_at,
      }
    }

    # Using the repo id as partition key can ensure that events for a given repo are processed in order
    # Note that when using aqueduct bridge partition key is not respected, and events are not processed in order
    partition_key = payload[:repository_id]

    Hydro::PublishRetrier.publish(
      message,
      partition_key: partition_key,
      schema: "github.security_center.v0.OrganizationAdvancedSecurityLicenseToggledPerRepository",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 })
  end

  subscribe("security_products.organization_advanced_security_license_toggled") do |payload|
    message = {
      organization_id: payload[:organization_id],
      enabled: payload[:enabled],
      license_toggled_for_org_at: payload[:license_toggled_for_org_at],
    }

    # Using the org id as partition key can ensure that events for a given org are processed in order
    # Note that when using aqueduct bridge partition key is not respected, and events are not processed in order
    partition_key = payload[:organization_id]

    Hydro::PublishRetrier.publish(
      message,
      partition_key: partition_key,
      schema: "github.security_center.v0.OrganizationAdvancedSecurityLicenseToggled",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 })
  end

  subscribe("security_products.enterprise_advanced_security_license_toggled") do |payload|
    message = {
      business_id: payload[:business_id],
      enabled: payload[:enabled],
      license_toggled_at: payload[:license_toggled_at],
    }

    # Using the business id as partition key can ensure that events for a given business are processed in order
    # Note that when using aqueduct bridge partition key is not respected, and events are not processed in order
    partition_key = payload[:business_id]

    Hydro::PublishRetrier.publish(
      message,
      partition_key: partition_key,
      schema: "github.security_center.v0.EnterpriseAdvancedSecurityLicenseToggled",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 })
  end

  subscribe("newsletter.preference.change") do |payload|
    publish(payload, schema: "github.v1.NewsletterPreferenceChange", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("security_analysis.update") do |payload|
    case payload[:owner]
    when Business
      owner_type = :ENTERPRISE
    when Organization
      owner_type = :ORGANIZATION
    when User
      owner_type = :USER
    else
      owner_type = :UNKNOWN
    end

    message = {
      event_name: payload[:event_name],
      owner_id: payload[:owner].id,
      owner_type: owner_type,
      actor: serializer.user(payload[:actor]),
    }

    Hydro::PublishRetrier.publish(message, schema: "github.security_settings.v1.SecuritySettingsUpdate")
  end
end
