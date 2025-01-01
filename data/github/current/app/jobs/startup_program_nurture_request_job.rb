# typed: true
# frozen_string_literal: true

class StartupProgramNurtureRequestJob < ApplicationJob
  retry_on_dirty_exit

  queue_as :startup_program_nurture_request

  def perform(admin_email:, email:)
    EloquaJob::perform_now(admin_email: admin_email, email: email)
    if GitHub::flipper[:marketing_forms_api_integration].enabled?
      MarketingFormsJob::perform_now(admin_email: admin_email, email: email)
    end
  end

  class EloquaJob < ApplicationJob
    retry_on_dirty_exit
    retry_on_recoverable_exceptions attempts: 20
    retry_on Eloqua::RestApiClient::BaseURlError, wait: :polynomially_longer, attempts: 20
    retry_on Faraday::Error, wait: :polynomially_longer, attempts: 20

    queue_as :startup_program_nurture_request

    NURTURE_FORM_ID = "129"
    NURTURE_FORM_FIELD_MAPPINGS = {
      email: "1693",
      admin_email: "1692",
    }.freeze

    def perform(admin_email:, email:)
      Eloqua::RestApiClient.submit_form_data(
        form_id: NURTURE_FORM_ID,
        raw_data: { admin_email: admin_email, email: email },
        mappings: NURTURE_FORM_FIELD_MAPPINGS,
      )
    end
  end

  class MarketingFormsJob < ApplicationJob
    retry_on_dirty_exit
    retry_on_recoverable_exceptions attempts: 20
    retry_on Faraday::Error, wait: :polynomially_longer, attempts: 20

    queue_as :startup_program_nurture_request

    def perform(admin_email:, email:)
      MarketingForms::RestApiClient.submit_form_data(
        form_name: "startup_program_nurture",
        raw_data: { admin_email: admin_email, email: email },
      )
    end
  end
end
