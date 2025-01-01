# typed: true
# frozen_string_literal: true

module Billing
  class EnterpriseCloudTrialMarketingNotificationJob < BillingJob
    retry_on_dirty_exit

    queue_as :billing

    def perform(data, target: :eloqua)
      if target == :marketing_forms
        MarketingFormsJob.perform_now(data)
      else
        EloquaJob.perform_now(data)
      end
    end

    class EloquaJob < ApplicationJob
      retry_on_dirty_exit
      retry_on_recoverable_exceptions attempts: 5
      retry_on Faraday::Error, wait: :polynomially_longer, attempts: 5
      retry_on Eloqua::RestApiClient::BaseURlError, wait: :polynomially_longer, attempts: 5

      queue_as :billing

      CONTACT_FORM_ID = 88
      CONTACT_FORM_MAPPINGS = {
        business_name: "927",
        business_id: "956",
        business_slug: "957",
        full_name: "926",
        email: "928",
        user_id: "936",
        employees_size: "964",
        industry: "963",
        other_industry: "962",
        trial_start: "940",
        trial_expiration: "941",
        user_agent: "948",
        remote_ip_address: "949",
        utm_medium: "937",
        utm_source: "938",
        utm_campaign: "951",
        submission_type: "939", # delete once jobs have drained
        event_type: "939",
        state: "944",
        city: "945",
        country: "946",
        postal_code: "947",
        marketing_email_opt_in: "955",
        agreed_to_terms: "932",
        trial_id: "943",
        billing_email: "980",
        total_billable_seats: "959",
        advanced_security_private_repos: "1155",
        static_tools: "1156",
        languages: "1157",
        github_username: "1158",
        plan_type: "1159"
      }.freeze

      def perform(data)
        Eloqua::RestApiClient.submit_form_data(
          form_id: CONTACT_FORM_ID,
          raw_data: data.symbolize_keys,
          mappings: CONTACT_FORM_MAPPINGS,
        )
      end
    end

    class MarketingFormsJob < ApplicationJob
      retry_on_dirty_exit
      retry_on_recoverable_exceptions attempts: 5
      retry_on Faraday::Error, wait: :polynomially_longer, attempts: 5

      # the original eloqua job is queued as :billing
      queue_as :billing

      def perform(data)
        MarketingForms::RestApiClient.submit_form_data(
          form_name: "enterprise-cloud-trial-new",
          raw_data: data.symbolize_keys,
        )
      end
    end
  end
end
