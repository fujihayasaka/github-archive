# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("business_startups_program.submitted") do |payload|
    application = payload[:application]
    business = payload[:business]
    actor = payload[:actor]

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      business_id: business&.id.to_i,
      business_slug: business&.slug,
      business_startups_program_id: application&.id.to_i,
      applicant: serializer.user(actor),
      partner_id: application&.application_data&.dig("partner_id").to_s,
      submitted_at: application&.submitted_at,
      is_metered: business&.metered_ghe? || false,
      has_payment_method: business&.has_valid_payment_method? || false,
      form_data: {
        partner_id: application&.application_data&.dig("partner_id"),
        industry: application&.application_data&.dig("industry"),
        country: application&.application_data&.dig("country"),
        latest_funding_round: application&.application_data&.dig("latest_funding_round"),
        funding_raised: application&.application_data&.dig("funding_raised"),
      }.to_json,
      status: :SUBMITTED,
    }

    publish(message, schema: "github.enterprise_account.v0.StartupProgramApplication")
  end

  subscribe("business_startups_program.accepted") do |payload|
    application = payload[:application]
    business = payload[:business]
    actor = payload[:actor]

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      business_id: business&.id.to_i,
      business_slug: business&.slug,
      business_startups_program_id: application&.id.to_i,
      applicant: serializer.user(application&.applicant),
      partner_id: application&.application_data&.dig("partner_id").to_s,
      submitted_at: application&.submitted_at,
      accepted_at: application&.accepted_at,
      is_metered: business&.metered_ghe? || false,
      has_payment_method: business&.has_valid_payment_method? || false,
      actor: serializer.user(actor),
      status: :ACCEPTED,
    }

    publish(message, schema: "github.enterprise_account.v0.StartupProgramApplication")
  end

  subscribe("business_startups_program.rejected") do |payload|
    application = payload[:application]
    business = payload[:business]
    actor = payload[:actor]
    rejection_reason_str = payload[:rejection_reason]

    hydro_rejection_reason = case rejection_reason_str
    when "not_metered" then :NOT_METERED
    when "no_payment_method" then :NO_PAYMENT_METHOD
    when "duplicate_payment_method" then :DUPLICATE_APPLICATION
    when "ineligible_enterprise_age" then :INELIGIBLE_ENTERPRISE_AGE
    when "suspected_abuse" then :SUSPECTED_ABUSE
    when "domain_email_mismatch", "stafftools_manual" then :MANUAL_REJECTION
    else :REJECTION_UNKNOWN
    end

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      business_id: business&.id.to_i,
      business_slug: business&.slug,
      business_startups_program_id: application&.id.to_i,
      applicant: serializer.user(application&.applicant),
      partner_id: application&.application_data&.dig("partner_id").to_s,
      submitted_at: application&.submitted_at,
      rejected_at: application&.rejected_at,
      is_metered: business&.metered_ghe? || false,
      has_payment_method: business&.has_valid_payment_method? || false,
      actor: serializer.user(actor),
      rejection_reason: hydro_rejection_reason,
      status: :REJECTED,
    }

    publish(message, schema: "github.enterprise_account.v0.StartupProgramApplication")
  end

  subscribe("business_startups_program.graduated") do |payload|
    application = payload[:application]
    business = payload[:business]
    actor = payload[:actor]

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      business_id: business&.id.to_i,
      business_slug: business&.slug,
      business_startups_program_id: application&.id.to_i,
      applicant: serializer.user(application&.applicant),
      partner_id: application&.application_data&.dig("partner_id").to_s,
      submitted_at: application&.submitted_at,
      actor: serializer.user(actor),
      status: :GRADUATED,
    }

    publish(message, schema: "github.enterprise_account.v0.StartupProgramApplication")
  end
end
