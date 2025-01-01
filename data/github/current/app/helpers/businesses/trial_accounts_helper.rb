# typed: true
# frozen_string_literal: true

module Businesses
  module TrialAccountsHelper
    INDUSTRY_OPTIONS = [
      ["Select an option", ""],
      "Agriculture & Mining",
      "Business Services",
      "Computers & Electronics",
      "Consumer Services",
      "Education",
      "Energy & Utilities",
      "Financial Services",
      "Food & Beverage",
      "Government",
      "Healthcare",
      "Manufacturing",
      "Media & Entertainment",
      "Not For Profit",
      "Real Estate & Construction",
      "Retail",
      "Software & Internet",
      "Telecommunications",
      "Transportation & Storage",
      "Travel, Recreation, and Leisure",
      "Wholesale & Distribution",
      ["Other", { classes: "js-enterprise-trial-industry" }],
    ]

    EMPLOYEE_SIZE = [
      ["Select an option", ""],
      "0-50",
      "51-1,000",
      "1,001-3,000",
      "3,001-5,000",
      "5,000+"
    ]

    MULTI_TENANT_DATA_HOSTING_REGIONS = [
      ["Select an option", ""],
      ["European Union", "prod_weu_01"],
      ["Australia", "prod_ae_01"],
      ["Sweden", "prod_sdc_01"]
    ]

    def show_captcha?(session, user = nil)
      Octocaptcha.new(session, page: :enterprise_trial_create, user: user).show_captcha?
    end

    def humanized_dfd_trial_fields_with_errors(entity)
      fields = [
        :data_hosting_region,
        :name,
        :slug,
        :shortcode,
        :subdomain,
        :industry,
        :employees_size,
        :number_of_seats,
        :country_code,
        :emu_idp,
        :billing_full_name,
        :admin_name,
        :billing_email,
        :admin_work_email,
        :trial_terms
      ]
      humanized_attributes = if entity.is_a?(MultiTenantProvisioningRequest)
        MultiTenantProvisioningRequest::HUMANIZED_ATTRIBUTES
      else
        Business::DFD_HUMANIZED_ATTRIBUTES
      end

      entity.errors.attribute_names.select { |attr| fields.include?(attr) }.sort_by { |attr| fields.index(attr) }
        .map { |attr| humanized_attributes[attr] }.join(", ")
    end

    # Public: Sends a welcome email to the creator of a non-EMU business or first owner of an EMU
    # business that meets the following criteria:
    #
    # 1. Business account is an enterprise trial account which may or may not be expired
    #
    # Returns nothing.
    def welcome_enterprise_trial_account(user_to_email, business)
      return if !business.trial? || business.trial_expired?

      BusinessMailer.welcome_enterprise_trial_account(user_to_email, business).deliver_later
    end

    # Public: Sends a 7 day reminder email to the creator a non-EMU business or first owner of an
    # EMU business that meets the following criteria:
    #
    # 1. Business account is an enterprise trial account which may or may not be expired
    #
    # Returns nothing.

    def trial_period_ending_for_enterprise_trial_account(user_to_email, business)
      return if !business.trial? || business.trial_expired?

      delivery_date = (business.trial_expires_at - 7.days).to_datetime
      BusinessMailer.trial_period_ending_for_enterprise_trial_account(user_to_email, business).deliver_later(
        wait_until: delivery_date
      )
    end
  end
end
