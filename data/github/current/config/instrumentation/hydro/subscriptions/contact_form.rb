# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("contact_form.submit") do |payload|
    contact_request = payload[:contact_request]

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      name: contact_request.name.to_s,
      email: contact_request.email.to_s,
      subject: contact_request.subject.to_s,
      body: contact_request.comments.to_s,
      form_type: contact_request.flavor.to_s.gsub("-", "_").upcase,
      referring_url: contact_request.referring_url.to_s,
      reported_content_url: contact_request.content_url.to_s,
    }

    if contact_request.classifier.present?
      classifier = contact_request.classifier
      possible_classifiers = Platform::Enums::AbuseReportReason.values.keys
      sanitized_classifier = possible_classifiers.include?(classifier) ? classifier : "UNSPECIFIED"
      message[:reported_content_classifier] = sanitized_classifier
    end

    if (content_object = contact_request.content_object)
      message[:reported_content_type] = contact_request.content_type.underscore.upcase
      message[:reported_content_id] = content_object.id
      message[:reported_content] = [
        content_object.try(:title),
        content_object.try(:body),
      ].compact.join("\n")
    end

    message[:reported_user] = serializer.user(payload[:reported_user]) if payload[:reported_user].present?
    message[:reported_integration] = serializer.integration(payload[:reported_integration]) if payload[:reported_integration].present?

    publish(message, schema: "github.v1.ContactFormSubmission", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
