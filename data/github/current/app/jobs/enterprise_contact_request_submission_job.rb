# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true


class EnterpriseContactRequestSubmissionJob < ApplicationJob
  retry_on_dirty_exit
  retry_on_recoverable_exceptions attempts: 10
  retry_on Faraday::Error, ActiveRecord::RecordNotFound, wait: :polynomially_longer, attempts: 10

  queue_as :enterprise_contact_requests

  def perform(enterprise_contact_request_id)
    enterprise_contact_request = Site::EnterpriseContactRequest.find(enterprise_contact_request_id)
    return if enterprise_contact_request.submitted?

    MarketingForms::RestApiClient.submit_form_data(
      form_name: "enterprise-cloud-trial",
      raw_data: enterprise_contact_request.marketing_forms_data.symbolize_keys,
    )

    with_write { enterprise_contact_request.submitted! }
  end
end
