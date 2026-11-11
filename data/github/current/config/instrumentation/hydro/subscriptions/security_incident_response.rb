# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("security_incident_response.remediation_complete") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      account: serializer.user(payload[:account]),
      account_global_relay_id: payload[:account_id],
      successful_remediations: payload[:successful_remediations],
      failed_remediations: payload[:failed_remediations],
      errors: payload[:errors],
      staffnote: payload[:staffnote],
      email_body_template: payload[:email_body_template],
      incident_response_id: payload[:incident_response_id],
      batch_count: payload[:batch_count],
      batch_index: payload[:batch_index],
      inputs: payload[:inputs],
    }

    publish(message, schema: "github.v1.SecurityIncidentRemediation", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
