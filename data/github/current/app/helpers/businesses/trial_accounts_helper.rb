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
      { display_name: "Europe", stamp_name: "prod_sdc_01", param_selector: "eu" },
      { display_name: "Europe", stamp_name: "prod_weu_01", param_selector: "weu" },
      { display_name: "Australia", stamp_name: "prod_ae_01", param_selector: "au" },
      { display_name: "United States", stamp_name: "prod_cus_01", param_selector: "us" },
      { display_name: "Japan", stamp_name: "prod_jpw_01", param_selector: "jp" },
    ].freeze

    PRIMARY_EMAIL_COOLDOWN_PERIOD = 72.hours

    def forbidden_due_to_recently_changed_primary_email?(user)
      recently_changed_primary_email?(user) &&
      !exempt_from_primary_email_cooldown_period?(user)
    end

    def recently_changed_primary_email?(user)
      return false if user.recently_created?(PRIMARY_EMAIL_COOLDOWN_PERIOD.ago)
      user.email_roles.primary.where("updated_at > ?", PRIMARY_EMAIL_COOLDOWN_PERIOD.ago).exists?
    end

    def exempt_from_primary_email_cooldown_period?(user)
      Users::Kv.store.exists(primary_email_cooldown_period_exemption_kv_key(user)).value!
    end

    def set_exemption_from_primary_email_cooldown_period(user)
      Users::Kv.store.set(
        primary_email_cooldown_period_exemption_kv_key(user),
        "true",
        expires: 1.week.from_now
      )
    end

    def clear_exemption_from_primary_email_cooldown_period(user)
      Users::Kv.store.del(primary_email_cooldown_period_exemption_kv_key(user))
    end

    def primary_email_cooldown_period_exemption_kv_key(user)
      "user.#{user.id}.exempt_from_business_trial_primary_email_cooldown_period"
    end

    def show_captcha?(session, user = nil)
      Octocaptcha.new(session, page: :enterprise_trial_create, user: user).show_captcha?
    end

    def data_hosting_region_options_for(user)
      # Start with the default "Host without data residency" option
      options = []
      options << { display_name: "Host on GitHub.com without data residency", stamp_name: "" }
      is_employee = user&.employee?

      MULTI_TENANT_DATA_HOSTING_REGIONS.each do |region_hash|
        display_name = T.must(region_hash[:display_name])
        stamp_name = T.must(region_hash[:stamp_name])

        # Check if the feature flag for this stamp is enabled
        if user&.feature_flag_enabled?("proxima_enable_stamp_#{stamp_name}", default: false)
          options << { display_name: display_name, stamp_name: stamp_name }
        elsif is_employee
          # If the user is an employee, add the option with a note
          display_name = "#{display_name} (Restricted)"
          options << { display_name: display_name, stamp_name: stamp_name }
        end
      end

      # Add the Staffship option for employees
      if is_employee
        options << { display_name: "Staffship (Staff only)", stamp_name: "staff_wus2_01" }
      end

      options
    end

    def data_hosting_region_from_param(param)
      return nil if param.blank?
      region = MULTI_TENANT_DATA_HOSTING_REGIONS.find { |r| r[:param_selector] == param.downcase }
      region&.dig(:stamp_name)
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

      humanized_attributes_array = []
      humanized_attributes.each do |k, v|
        humanized_attributes_array << [k, v] if entity.errors.include?(k)
      end
      humanized_attributes_array
    end

    # Public: Converts a trial business account to a self-serve billing account
    # For metered trials: Sets monthly billing and onboards to billing platform
    # For volume self-serve trials: Onboards to billing platform
    #
    # Business is an enterprise trial account
    # Returns nothing
    def convert_to_self_serve_billing(business)
      return unless business.trial?

      if business.metered_ghe?
        GitHub.dogstats.increment("billing_platform.onboard_metered_self_serve_trial")
        business.customer.onboard_to_all_billing_platform_products
        plan_duration = "month"
      else
        GitHub.dogstats.increment("billing_platform.onboard_volume_self_serve_trial")
        business.customer.onboard_to_all_billing_platform_products
      end

      business.enable_self_serve_payments(skip_billing: true, plan_duration: plan_duration || "year")
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
