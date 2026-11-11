# typed: strict
# frozen_string_literal: true

class MarketingFormsSubmissionJob < ApplicationJob
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  retry_on Faraday::Error, wait: :polynomially_longer, attempts: 10

  queue_as :marketing_forms_submissions

  sig { params(form_name: String, raw_data: T::Hash[Symbol, T.untyped]).void }
  def perform(form_name:, raw_data:)
    MarketingForms::RestApiClient.submit_form_data(form_name:, raw_data:)
  end

  sig { returns(T::Array[String]) }
  def stats_tags
    ["form_name:#{form_name}"]
  end

  private

  sig { returns(String) }
  def form_name
    arguments.first&.fetch(:form_name)
  end
end
