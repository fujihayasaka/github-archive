# typed: strict
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("microsoft_enterprise_agreement.support_entitlement") do |payload|
    business = payload[:business]

    message = {
      business: serializer.business(business),
      support_plan: payload[:support_plan],
      previous_support_plan: payload[:previous_support_plan],
      tpid: payload[:tpid],
      eans: payload[:eans],
      salesforce_account_id: payload[:salesforce_account_id],
      start_date: payload[:start_date],
      end_date: payload[:end_date],
      customer_name: payload[:customer_name],
      latest_agreement_id: payload[:latest_agreement_id],
      service_offering_id: payload[:service_offering_id],
      agreement_region_id: payload[:agreement_region_id]
    }

    publish(message, schema: "github.v1.MsftEnterpriseAgreementSupportEntitlement")
  end

  subscribe("microsoft_enterprise_agreement.support_disentitlement") do |payload|
    business = payload[:business]

    message = {
      business: serializer.business(business),
      previous_support_plan: payload[:previous_support_plan],
      salesforce_account_id: payload[:salesforce_account_id]
    }

    publish(message, schema: "github.v1.MsftEnterpriseAgreementSupportDisentitlement")
  end
end
