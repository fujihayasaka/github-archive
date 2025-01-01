# typed: true
# frozen_string_literal: true

class Api::Billing < Api::App
  MAX_NUMBER_OF_RESOURCES = 50.freeze
  include SecretScanning::Features::FeatureFlagHelper

  # Get Advanced Security billing information for organizations
  get "/organizations/:organization_id/settings/billing/advanced-security", operation_id: "billing/get-github-advanced-security-billing-org" do
    org = find_org!

    if org.business&.feature_flag_enabled?(:saml_scope_private_resources_to_business, default: false)
      resource = org
    else
      resource = Platform::InternalResource.new(resource: org)
    end

    control_access :view_org_settings,
      resource: resource,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    billable_entity = org.advanced_security_license.billable_entity
    sku = advanced_security_requested_sku(billable_entity, params[:advanced_security_product])

    data = Business::AdvancedSecurityCommittersGenerator.generate_json(org, page: pagination[:page], per_page: pagination[:per_page] || DEFAULT_PER_PAGE, sku:)

    deliver_raw(data)
  end

  # Get Advanced Security billing information for enterprises
  get "/enterprises/:enterprise_id/settings/billing/advanced-security", operation_id: "billing/get-github-advanced-security-billing-ghe" do
    enterprise = find_enterprise!
    control_access :manage_business_billing,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    sku = advanced_security_requested_sku(enterprise, params[:advanced_security_product])

    data = Business::AdvancedSecurityCommittersGenerator.generate_json(enterprise, page: pagination[:page], per_page: pagination[:per_page] || DEFAULT_PER_PAGE, sku:)

    deliver_raw(data)
  end

  # the majority of the billing endpoints are not applicable to GHES
  unless GitHub.enterprise?
    # Get Actions billing information for users
    get "/user/:user_id/settings/billing/actions", operation_id: "billing/get-github-actions-billing-user" do
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      if user&.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-github-actions-billing-user"])
        deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-user"
      end

      GitHub.dogstats.increment("meuse.api.status", tags: ["status:200", "operation:billing/get-github-actions-billing-user"])
      deliver_raw(serialize_actions_usage(billable_owner: user))
    end

    # Get Actions billing information for organizations
    get "/organizations/:organization_id/settings/billing/actions", operation_id: "billing/get-github-actions-billing-org" do
      org = find_org!
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      if org.delegate_billing_to_business?
        if org.business&.billed_via_billing_platform?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-github-actions-billing-org"])
          deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-org"
        end

        GitHub.dogstats.increment("meuse.api.status", tags: ["status:200", "operation:billing/get-github-actions-billing-org"])
        deliver_raw(serialize_actions_usage(billable_owner: org.business, owner: org))
      else
        if org&.billed_via_billing_platform?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-github-actions-billing-org"])
          deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-org"
        end

        GitHub.dogstats.increment("meuse.api.status", tags: ["status:200", "operation:billing/get-github-actions-billing-org"])
        deliver_raw(serialize_actions_usage(billable_owner: org))
      end
    end

    # Get Actions billing information for enterprises
    get "/enterprises/:enterprise_id/settings/billing/actions", operation_id: "billing/get-github-actions-billing-ghe" do
      enterprise = find_enterprise!
      control_access :manage_business_billing,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      if enterprise&.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-github-actions-billing-ghe"])
        deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates"
      end

      GitHub.dogstats.increment("meuse.api.status", tags: ["status:200", "operation:billing/get-github-actions-billing-ghe"])
      deliver_raw(serialize_actions_usage(billable_owner: enterprise))
    end

    def serialize_actions_usage(billable_owner:, owner: nil)
      if FeatureFlag.vexi.enabled?(:billing_return_empty_meuse_responses, @billable_owner, default: false)
        {
          total_minutes_used: 0,
          total_paid_minutes_used: 0,
          included_minutes: 0,
          minutes_used_breakdown:
            { "UBUNTU" => 0,
            "MACOS" => 0,
            "WINDOWS" => 0,
            "ubuntu_4_core" => 0,
            "ubuntu_8_core" => 0,
            "ubuntu_16_core" => 0,
            "ubuntu_32_core" => 0,
            "ubuntu_64_core" => 0,
            "windows_4_core" => 0,
            "windows_8_core" => 0,
            "windows_16_core" => 0,
            "windows_32_core" => 0,
            "windows_64_core" => 0,
            "macos_12_core" => 0,
            "total" => 0 } }
      else
        account = owner || billable_owner
        actions_usage = ::Billing::ActionsUsage.product_usage(account)
        if actions_usage.has_error?
          deliver_error! 503,
            message: "Billing data for GitHub Actions is temporarily unavailable."
        end

        private_minutes_used = actions_usage.minutes_used_per_runtime.clone
        private_minutes_used.each { |key, val| private_minutes_used[key] = val.to_i }

        {
          total_minutes_used: actions_usage.total_minutes_used.to_i,
          total_paid_minutes_used: actions_usage.total_paid_minutes_used.to_i,
          included_minutes: actions_usage.included_minutes,
          minutes_used_breakdown: private_minutes_used
        }
      end
    end

    # Get Packages billing information for users
    get "/user/:user_id/settings/billing/packages", operation_id: "billing/get-github-packages-billing-user" do
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      if FeatureFlag.vexi.enabled?(:billing_platform_custom_status, user, default: false) && user&.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-github-packages-billing-user"])
        deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-user"
      end

      GitHub.dogstats.increment("meuse.api.status", tags: ["status:200", "operation:billing/get-github-packages-billing-user"])
      deliver_raw(serialize_packages_usage(billable_owner: user))
    end

    # Get Packages billing information for organizations
    get "/organizations/:organization_id/settings/billing/packages", operation_id: "billing/get-github-packages-billing-org" do
      org = find_org!
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      if org.delegate_billing_to_business?
        if FeatureFlag.vexi.enabled?(:billing_platform_custom_status, org.business, default: false) && org.business&.billed_via_billing_platform?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-github-packages-billing-org"])
          deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-org"
        end

        GitHub.dogstats.increment("meuse.api.status", tags: ["status:200", "operation:billing/get-github-packages-billing-org"])
        deliver_raw(serialize_packages_usage(billable_owner: org.business, owner: org))
      else
        if FeatureFlag.vexi.enabled?(:billing_platform_custom_status, org, default: false) && org&.billed_via_billing_platform?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-github-packages-billing-org"])
          deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-org"
        end

        GitHub.dogstats.increment("meuse.api.status", tags: ["status:200", "operation:billing/get-github-packages-billing-org"])
        deliver_raw(serialize_packages_usage(billable_owner: org))
      end
    end

    # Get Packages billing information for enterprises
    get "/enterprises/:enterprise_id/settings/billing/packages", operation_id: "billing/get-github-packages-billing-ghe" do
      enterprise = find_enterprise!
      control_access :manage_business_billing,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      if FeatureFlag.vexi.enabled?(:billing_platform_custom_status, enterprise, default: false) && enterprise&.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-github-packages-billing-ghe"])
        deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates"
      end

      GitHub.dogstats.increment("meuse.api.status", tags: ["status:200", "operation:billing/get-github-packages-billing-ghe"])
      deliver_raw(serialize_packages_usage(billable_owner: enterprise))
    end

    def serialize_packages_usage(billable_owner:, owner: nil)
      if FeatureFlag.vexi.enabled?(:billing_return_empty_meuse_responses, @billable_owner, default: false)
        { total_gigabytes_bandwidth_used: 0, total_paid_gigabytes_bandwidth_used: 0, included_gigabytes_bandwidth: 0 }
      else
        account = owner || billable_owner
        packages_usage = ::Billing::PackageRegistryUsage.usage_quote(account)
        if packages_usage.has_error?
          deliver_error! 503,
            message: "Billing data for packages is temporarily unavailable."
        end
        {
          total_gigabytes_bandwidth_used: packages_usage.total_gigabytes_used,
          total_paid_gigabytes_bandwidth_used: packages_usage.billable_gigabytes,
          included_gigabytes_bandwidth: packages_usage.plan_included_bandwidth
        }
      end
    end

    # Get shared storage billing information for shared users
    get "/user/:user_id/settings/billing/shared-storage", operation_id: "billing/get-shared-storage-billing-user" do
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      if FeatureFlag.vexi.enabled?(:billing_platform_custom_status, user, default: false) && user&.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-shared-storage-billing-user"])
        deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-user"
      end

      GitHub.dogstats.increment("meuse.api.status", tags: ["status:200", "operation:billing/get-shared-storage-billing-user"])
      deliver_raw(serialize_shared_storage_usage(billable_owner: user))
    end

    # Get shared storage billing information for shared organizations
    get "/organizations/:organization_id/settings/billing/shared-storage", operation_id: "billing/get-shared-storage-billing-org" do
      org = find_org!
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      if org.delegate_billing_to_business?
        if FeatureFlag.vexi.enabled?(:billing_platform_custom_status, org.business, default: false) && org.business&.billed_via_billing_platform?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-shared-storage-billing-org"])
          deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-org"
        end

        GitHub.dogstats.increment("meuse.api.status", tags: ["status:200", "operation:billing/get-shared-storage-billing-org"])
        deliver_raw(serialize_shared_storage_usage(billable_owner: org.business, owner: org))
      else
        if FeatureFlag.vexi.enabled?(:billing_platform_custom_status, org, default: false) && org&.billed_via_billing_platform?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-shared-storage-billing-org"])
          deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-org"
        end

        GitHub.dogstats.increment("meuse.api.status", tags: ["status:200", "operation:billing/get-shared-storage-billing-org"])
        deliver_raw(serialize_shared_storage_usage(billable_owner: org))
      end
    end

    # Get shared storage billing information for shared enterprises
    get "/enterprises/:enterprise_id/settings/billing/shared-storage", operation_id: "billing/get-shared-storage-billing-ghe" do
      enterprise = find_enterprise!
      control_access :manage_business_billing,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      if FeatureFlag.vexi.enabled?(:billing_platform_custom_status, enterprise, default: false) && enterprise&.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-shared-storage-billing-ghe"])
        deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates"
      end

      GitHub.dogstats.increment("meuse.api.status", tags: ["status:200", "operation:billing/get-shared-storage-billing-ghe"])
      deliver_raw(serialize_shared_storage_usage(billable_owner: enterprise))
    end

    def serialize_shared_storage_usage(billable_owner:, owner: nil)
      if FeatureFlag.vexi.enabled?(:billing_return_empty_meuse_responses, @billable_owner, default: false)
        { days_left_in_billing_cycle: 0, estimated_paid_storage_for_month: 0, estimated_storage_for_month: 0 }
      else
        account = owner || billable_owner
        shared_storage_used = ::Billing::SharedStorageUsage.usage_quote(account)
        if shared_storage_used.has_error?
          deliver_error! 503,
            message: "Billing data for shared storage is temporarily unavailable."
        end
        {
          days_left_in_billing_cycle: shared_storage_used.days_left_in_billing_cycle,
          estimated_paid_storage_for_month: (shared_storage_used.estimated_monthly_paid_megabytes / 1024).to_i,
          estimated_storage_for_month: shared_storage_used.estimated_monthly_private_megabytes / 1024,
        }
      end
    end

    get "/user/:user_id/settings/billing/usage", operation_id: "billing/get-github-billing-usage-report-user" do
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      unless user&.customer&.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/get-github-billing-usage-report-user"])
        deliver_error! 403, message: "No access to billing usage data."
      end

      time_params = parse_time_period_params(params)
      year, month, day, hour = time_params[:year], time_params[:month], time_params[:day], time_params[:hour]

      new_query = {
        usage_entity_id: user.customer.id,
        year: year,
        month: month,
        day: day,
        hour: hour,
        billing_period: get_billing_period_from_params(params),
      }
      usage_response = Billing::Platform::Api::Client.new.get_usage_report(**new_query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(usage_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-github-billing-usage-report-user"])
        deliver_error! 503, message: "Unable to get billing usage data."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-github-billing-usage-report-user"])
        deliver :user_usage_report_hash, add_repo_name_to_response(usage_response)
      end
    end

    get "/enterprises/:enterprise_id/settings/billing/usage", operation_id: "billing/get-github-billing-usage-report-ghe" do
      enterprise = find_enterprise!
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      unless enterprise.customer.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/get-github-billing-usage-report-ghe"])
        deliver_error! 403, message: "No access to billing usage data."
      end

      time_params = parse_time_period_params(params)
      year, month, day, hour = time_params[:year], time_params[:month], time_params[:day], time_params[:hour]

      # if a cost center id is passed in, we want to get usage data for that specific cost center, otherwise
      # we query a usage report for the enterprise customer
      usage_entity_id = params[:cost_center_id].nil? ? enterprise.customer_id : params[:cost_center_id]

      # Validate if cost center belongs to the enterprise customer
      unless params[:cost_center_id].nil?
        cost_center_response = Billing::Platform::Api::Client.new.get_cost_center(cost_center_key: {
          customerId: enterprise.customer_id.to_s,
          uuid: params[:cost_center_id]
        })

        if cost_center_response.is_a?(Billing::Platform::Api::Error)
          Failbot.report(cost_center_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-github-billing-usage-report-ghe"])
          deliver_error! 503, message: "Unable to get cost center billing usage data."
        end

        if cost_center_response[:costCenter].nil?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-github-billing-usage-report-ghe"])
          deliver! :usage_report_hash, { reportItems: [] }
        end
      end

      new_query = {
        usage_entity_id: usage_entity_id,
        year: year,
        month: month,
        day: day,
        hour: hour,
        billing_period: get_billing_period_from_params(params),
      }
      usage_response = Billing::Platform::Api::Client.new.get_usage_report(**new_query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(usage_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-github-billing-usage-report-ghe"])
        deliver_error! 503, message: "Unable to get billing usage data."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-github-billing-usage-report-ghe"])
        deliver :usage_report_hash, add_org_and_repo_name_to_response(usage_response)
      end
    end

    # Get billing usage report for organizations
    get "/organizations/:organization_id/settings/billing/usage", operation_id: "billing/get-github-billing-usage-report-org" do
      org = find_org!
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      unless (org.delegate_billing_to_business? && org.business&.customer&.billed_via_billing_platform?) ||
       (!org.delegate_billing_to_business? && org.customer&.billed_via_billing_platform?)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/get-github-billing-usage-report-org"])
        deliver_error! 403, message: "No access to billing usage data."
      end

      time_params = parse_time_period_params(params)
      year, month, day, hour = time_params[:year], time_params[:month], time_params[:day], time_params[:hour]

      usage_entity_id = org.delegate_billing_to_business? ? org.business&.customer_id : org.customer&.id

      new_query = {
        usage_entity_id: usage_entity_id,
        year: year,
        month: month,
        day: day,
        hour: hour,
        billing_period: get_billing_period_from_params(params),
        org_id: org.delegate_billing_to_business? ? org.id : nil,
      }
      usage_response = Billing::Platform::Api::Client.new.get_usage_report(**new_query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(usage_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-github-billing-usage-report-org"])
        deliver_error! 503, message: "Unable to get billing usage data."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-github-billing-usage-report-org"])
        deliver :usage_report_hash, add_org_and_repo_name_to_response(usage_response)
      end
    end

    # Get credits for an organization (currently limited to included usage)
    get "/organizations/:organization_id/settings/billing/credits", operation_id: "billing/get-credits-org" do
      org = find_org!
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      unless org.feature_flag_enabled?(:billing_credits_api, default: false)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/get-credits-org"])
        deliver_error! 404
      end

      # An org that is delegated to a business has no included usage at the org-level, so we return an empty list
      if org.delegate_billing_to_business?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-credits-org"])
        deliver! :credits_hash, { discounts: [] }
      end

      credits_response = Billing::Platform::Api::Client.new.get_all_included_usage_discount_states(
        customer_id: org.customer&.id, year: Time.now.utc.year, month: Time.now.utc.month
      )

      if credits_response.is_a?(Billing::Platform::Api::Error)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-credits-org"])
        deliver_error! 503, message: "Unable to get credits data."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-credits-org"])
        deliver! :credits_hash, credits_response
      end
    end

    # Get credits for a user (currently limited to included usage)
    get "/user/:user_id/settings/billing/credits", operation_id: "billing/get-credits-user" do
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      unless user.feature_flag_enabled?(:billing_credits_api, default: false)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/get-credits-user"])
        deliver_error! 404
      end

      # An EMU user has no included usage at the user-level, so we return an empty list
      if user.is_enterprise_managed?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-credits-user"])
        deliver! :credits_hash, { discounts: [] }
      end

      credits_response = Billing::Platform::Api::Client.new.get_all_included_usage_discount_states(
        customer_id: user.customer&.id, year: Time.now.utc.year, month: Time.now.utc.month
      )

      if credits_response.is_a?(Billing::Platform::Api::Error)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-credits-user"])
        deliver_error! 503, message: "Unable to get credits data."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-credits-user"])
        deliver! :credits_hash, credits_response
      end
    end

    get "/enterprises/:enterprise_id/settings/billing/cost-centers", operation_id: "billing/get-all-cost-centers" do
      enterprise = find_enterprise!
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      # only allow access to cost center data if the customer is billed via billing platform
      unless enterprise.customer.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/get-all-cost-centers"])
        deliver_error! 403, message: "No access to cost center data."
      end

      # API queries should not read from the cache to ensure the most up-to-date data is returned
      all_cost_centers_response = Billing::Platform::Api::Client.new.get_all_cost_centers(customer_id: enterprise.customer_id.to_s, use_cache: false)

      if all_cost_centers_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(all_cost_centers_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-all-cost-centers"])
        deliver_error! 503, message: "Unable to get billing cost center data for all cost centers."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-all-cost-centers"])
        deliver :all_cost_centers_hash, all_cost_centers_response
      end
    end

    post "/enterprises/:enterprise_id/settings/billing/cost-centers", operation_id: "billing/create-cost-center", read_from_replicas: true do
      enterprise = find_enterprise!

      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false


      # only allow access to cost center data if the customer is billed via billing platform
      unless enterprise.customer.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/create-cost-center"])
        deliver_error! 403, message: "No access to cost center data."
      end

      data = receive_with_openapi
      name = data["name"]

      # Validate required parameters
      if name.nil? || name.strip.empty?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-cost-center"])
        deliver_error! 400, message: "A name is required for the cost center."
      end

      if name.length > 255
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-cost-center"])
        deliver_error! 400, message: "Cost center name must be shorter than 256 characters."
      end

      create_params = {
        customer_id: enterprise.customer_id.to_s,
        target_type: enterprise.customer.metered_via_azure? ? BillingPlatform::Api::V1::CostCenterType::AzureSubscription : BillingPlatform::Api::V1::CostCenterType::ZuoraSubscription,
        target_id: "",
        name: name,
        resources: []
      }
      if enterprise.feature_flag_enabled?(:billing_add_cost_center_description, default: false) && data["description"].present?
        create_params[:description] = data["description"]
      end

      begin
        client = Billing::Platform::Api::Client.new
        response = client.create_cost_center(**create_params)

        if response.is_a?(Billing::Platform::Api::Error)
          Failbot.report(response)

          if response.already_exists?
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:409", "operation:billing/create-cost-center"])
            deliver_error! 409, message: response.original_error.msg
          elsif response.resource_exhausted?
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-cost-center"])
            deliver_error! 400, message: response.original_error.msg
          else
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/create-cost-center"])
            deliver_error! 500, message: "Unable to create cost center: #{response.message}"
          end

          return
        end

        response = response.with_indifferent_access if response.respond_to?(:with_indifferent_access)

        # Transform response to expected format
        response_data = if response["costCenter"]
          response
        else
          {
            "costCenter" => {
              "costCenterKey" => {
                "uuid" => response["id"]
              },
              "name" => response["name"],
              "resources" => response["resources"] || []
            }
          }
        end

        GitHub.instrument "billing.cost_center_create", {
          actor: current_user,
          customer_id: enterprise.customer_id.to_s,
          business: enterprise,
          uuid: params[:cost_center_id],
          name: response["name"],
          status: "success",
          source: "api"
        }

        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/create-cost-center"])
        deliver! :cost_center_hash, response_data, status: 200
      rescue StandardError => e
        Failbot.report(e)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/create-cost-center"])
        deliver_error! 500, message: "Internal Server Error: #{e.message}"
      end
    end

    get "/enterprises/:enterprise_id/settings/billing/cost-centers/:cost_center_id", operation_id: "billing/get-cost-center" do
      enterprise = find_enterprise!
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      # only allow access to cost center data if the customer is billed via billing platform
      unless enterprise.customer.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/get-cost-center"])
        deliver_error! 403, message: "No access to cost center data."
      end

      cost_center_response = Billing::Platform::Api::Client.new.get_cost_center(
        cost_center_key: {
          customerId: enterprise.customer_id.to_s,
          uuid: params[:cost_center_id]
        }
      )

      if cost_center_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(cost_center_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-cost-center"])
        deliver_error! 503, message: "Unable to get billing cost center data."
      elsif cost_center_response[:costCenter].nil?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/get-cost-center"])
        deliver_error! 404, message: "Cost center with Uuid: #{params[:cost_center_id]} for #{enterprise.name} not found."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-cost-center"])
        deliver :cost_center_hash, cost_center_response
      end
    end

    delete "/enterprises/:enterprise_id/settings/billing/cost-centers/:cost_center_id", operation_id: "billing/delete-cost-center" do
      enterprise = find_enterprise!

      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      # Check if the customer is billed via billing platform
      unless enterprise.customer.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/delete-cost-center"])
        deliver_error! 403, message: "No access to cost center data."
      end

      # Try to archive the cost center
      archive_response = Billing::Platform::Api::Client.new.archive_cost_center(
        cost_center_key: {
          customerId: enterprise.customer_id.to_s,
          uuid: params[:cost_center_id]
        }
      )

      if archive_response.is_a?(Billing::Platform::Api::Error)
        if archive_response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/delete-cost-center"])
          deliver_error! 404, message: "Cost center not found."
        else
          Failbot.report(archive_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/delete-cost-center"])
          deliver_error! 503, message: "Unable to delete cost center."
        end
      end

      GitHub.instrument "billing.cost_center_delete", {
        actor: current_user,
        customer_id: enterprise.customer_id.to_s,
        business: enterprise,
        uuid: params[:cost_center_id],
        status: "success",
        source: "api"
      }

      formatted_response = {
        message: "Cost center successfully deleted.",
        id: archive_response[:costCenter][:costCenterKey][:uuid],
        name: archive_response[:costCenter][:name],
        costCenterState: archive_response[:costCenter][:costCenterState]
      }

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/delete-cost-center"])
      deliver_raw(formatted_response, status: 200)
    end

    # Update a cost center name
    patch "/enterprises/:enterprise_id/settings/billing/cost-centers/:cost_center_id", operation_id: "billing/update-cost-center" do
      enterprise = find_enterprise!

      # Access control
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      # Ensure the enterprise is billed via the billing platform
      unless enterprise.customer.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/update-cost-center"])
        deliver_error! 403, message: "No access to cost center data."
      end

      # Receive and validate data
      data = receive_with_openapi
      name = data["name"]

      if name.nil? || name.empty?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/update-cost-center"])
        deliver_error! 400, message: "Cost center name is required."
      end

      if name.length > 255
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/update-cost-center"])
        deliver_error! 400, message: "Cost center name must be shorter than 256 characters."
      end

      update_params = {
        key: {
          customer_id: enterprise.customer_id.to_s,
          uuid: params[:cost_center_id]
        },
        target_id: "NO_UPDATE",
        name: name,
        resources_to_add: [],
        resources_to_remove: [],
        update_resources_only: false,
      }

      if enterprise.feature_flag_enabled?(:billing_add_cost_center_description, default: false) && data["description"].present?
        update_params[:description] = data["description"]
      end
      response = Billing::Platform::Api::Client.new.update_cost_center(**update_params)

      if response.is_a?(Billing::Platform::Api::Error)
        if response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/update-cost-center"])
          deliver_error! 404, message: "Cost center with Uuid: #{params[:cost_center_id]} for #{enterprise.name} not found."
        elsif response.inactive_cost_center?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/update-cost-center"])
          deliver_error! 400, message: "Cannot update an inactive cost center"
        elsif response.already_exists?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:409", "operation:billing/update-cost-center"])
          deliver_error! 409, message: "A cost center with that name already exists"
        else
          GitHub.logger.error("billing.cost_center_update.unhandled_error",
            http_status: response.http_status,
            message: response.message,
            original: response.original_error.inspect,
            cost_center_id: params[:cost_center_id],
            has_description: update_params.key?(:description),
          )
          Failbot.report(response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/update-cost-center"])
          deliver_error! 503, message: "Unable to update cost center."
        end
      elsif response[:costCenter].nil?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/update-cost-center"])
        deliver_error! 404, message: "Cost center with Uuid: #{params[:cost_center_id]} for #{enterprise.name} not found."
      end

      GitHub.instrument "billing.cost_center_update", {
        actor: current_user,
        customer_id: enterprise.customer_id.to_s,
        business: enterprise,
        uuid: params[:cost_center_id],
        name: name,
        status: "success",
        source: "api"
      }

      # Success response
      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/update-cost-center"])
      deliver :cost_center_hash, response
    end

    post "/enterprises/:enterprise_id/settings/billing/cost-centers/:cost_center_id/resource", operation_id: "billing/add-resource-to-cost-center", read_from_replicas: true do
      enterprise = find_enterprise!
      user = current_user

      control_access :view_business_billing,
       resource: enterprise,
       allow_integrations: false,
       allow_user_via_granular_actor: false

      # only allow access to cost center data if the customer is billed via billing platform
      unless enterprise.customer.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/add-resource-to-cost-center"])
        deliver_error! 403, message: "No access to cost center data."
      end

      data = receive_with_openapi
      user_logins = data["users"]&.map(&:downcase) || []
      user_ids = []

      organization_names = data["organizations"] || []
      enterprise_organizations = enterprise.organizations

      repository_names = data["repositories"]&.map(&:downcase) || []

      total_resource_count = user_logins.length + organization_names.length + repository_names.length
      if total_resource_count > MAX_NUMBER_OF_RESOURCES
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/add-resource-to-cost-center"])
        deliver_error! 400, message: "Too many resources. A max of #{MAX_NUMBER_OF_RESOURCES} resources are allowed to be added per request."
      end

      GitHub.logger.info("add-resource-to-cost-center metrics",
        "gh.user.id": user.id,
        "gh.business.id": enterprise.id,
        "gh.billing.cost_center_id": params[:cost_center_id],
        "gh.billing.cost_center.user_count": user_logins.length,
        "gh.billing.cost_center.org_count": organization_names.length,
        "gh.billing.cost_center.repo_count": repository_names.length,
      )

      enterprise_repositories = repository_names.empty? ? {} : enterprise_repositories(enterprise)

      matched_enterprise_members, user_id_to_name = enterprise_members(enterprise, user_logins)

      not_matched_logins = user_logins - matched_enterprise_members.keys
      if not_matched_logins.any?
        deliver_error! 403, message: "These users are not part of enterprise: '#{not_matched_logins.join("', '")}'"
      end

      user_logins.each do |display_login|
        if member_id = matched_enterprise_members[display_login]
          user_ids << {
            id: member_id.to_s,
            type: BillingPlatform::Base::ResourceType::User,
          }
        end
      end

      is_enterprise_admin = enterprise.admins.include?(user)
      organization_ids, organization_id_to_name = filter_by_organization_access(user, organization_names, enterprise_organizations, is_enterprise_admin)
      repository_ids, repository_id_to_name = filter_by_repository_access(user, repository_names, enterprise_repositories, is_enterprise_admin)

      entity_ids = user_ids + organization_ids + repository_ids

      add_resource_cost_center_response = enterprise.add_resources_to_cost_center(params[:cost_center_id], entity_ids)

      if add_resource_cost_center_response.is_a?(Billing::Platform::Api::Error)
        if add_resource_cost_center_response.http_409?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:409", "operation:billing/add-resource-to-cost-center"])
          deliver_error! 409, message: "A resource you're trying to add is already associated with a cost center."
        elsif add_resource_cost_center_response.http_4xx?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:#{add_resource_cost_center_response.http_status}", "operation:billing/add-resource-to-cost-center"])
          deliver_error! add_resource_cost_center_response.http_status, message: add_resource_cost_center_response.message
        else
          Failbot.report(add_resource_cost_center_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/add-resource-to-cost-center"])
          deliver_error! 503, message: "Unable to update billing cost center data."
        end
      end

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/add-resource-to-cost-center"])
      # Treat a missing key or nil value the same as an empty collection.
      reassigned_resources = add_resource_cost_center_response[:reassignedResources] || []
      resources = []
      reassigned_resources.each do |resource|
        case resource[:resource][:type].to_s
        when "User"
          user_login = user_id_to_name[resource[:resource][:id].to_i]
          next if user_login.nil?
          resources << { resource_type: "User", name: user_login, previous_cost_center: resource[:previousCostCenterName] }
        when "Organization", "Org"
          org_name = organization_id_to_name[resource[:resource][:id].to_i]
          next if org_name.nil?
          resources << { resource_type: "Organization", name: org_name, previous_cost_center: resource[:previousCostCenterName] }
        when "Repository", "Repo"
          repo_name = repository_id_to_name[resource[:resource][:id].to_i]
          next if repo_name.nil?
          resources << { resource_type: "Repository", name: repo_name, previous_cost_center: resource[:previousCostCenterName] }
        end
      end
      deliver_raw({ message: "Resources successfully added to the cost center.", reassigned_resources: resources }, status: 200)
    end

    delete "/enterprises/:enterprise_id/settings/billing/cost-centers/:cost_center_id/resource", operation_id: "billing/remove-resource-from-cost-center", read_from_replicas: true do
      enterprise = find_enterprise!
      user = current_user
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      # only allow access to cost center data if the customer is billed via billing platform
      unless enterprise.customer.billed_via_billing_platform?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/remove-resource-from-cost-center"])
        deliver_error! 403, message: "No access to cost center data."
      end

      data = receive_with_openapi
      user_logins = data["users"] || []
      user_ids = []

      organization_names = data["organizations"] || []
      enterprise_organizations = enterprise.organizations

      repository_names = data["repositories"]&.map(&:downcase) || []

      enterprise_repositories = repository_names.empty? ? {} : enterprise_repositories(enterprise)

      total_resource_count = user_logins.length + organization_names.length + repository_names.length
      if total_resource_count > MAX_NUMBER_OF_RESOURCES
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/remove-resource-from-cost-center"])
        deliver_error! 400, message: "Too many resources. A max of #{MAX_NUMBER_OF_RESOURCES} resources are allowed to be removed per request."
      end

      GitHub.logger.info("remove-resource-from-cost-center metrics",
        "gh.user.id": user.id,
        "gh.business.id": enterprise.id,
        "gh.billing.cost_center_id": params[:cost_center_id],
        "gh.billing.cost_center.user_count": user_logins.length,
        "gh.billing.cost_center.org_count": organization_names.length,
        "gh.billing.cost_center.repo_count": repository_names.length,
      )

      User.where(display_login: user_logins).select(:id, :business_id).each do |user|
        user_ids << {
          id: user.id.to_s,
          type: BillingPlatform::Base::ResourceType::User,
        }
      end

      is_enterprise_admin = enterprise.admins.include?(user)
      organization_ids, _organization_id_to_name = filter_by_organization_access(user, organization_names, enterprise_organizations, is_enterprise_admin)
      repository_ids, _repository_id_to_name = filter_by_repository_access(user, repository_names, enterprise_repositories, is_enterprise_admin)

      entity_ids = user_ids + organization_ids + repository_ids

      if !entity_ids.any?
        deliver_error! 400, message: "No resources to remove"
      end

      remove_resource_cost_center_response = enterprise.remove_resources_from_cost_center(params[:cost_center_id], entity_ids)
      if remove_resource_cost_center_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(remove_resource_cost_center_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/remove-resource-from-cost-center"])
        deliver_error! 503, message: "Unable to update billing cost center data."
      end

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/remove-resource-from-cost-center"])
      success_message = "Resources successfully removed from the cost center."

      deliver_raw({ message: success_message }, status: 200)
    end

    delete "/enterprises/:enterprise_id/settings/billing/budgets/:budget_id", operation_id: "billing/delete-budget", read_from_replicas: true do
      enterprise = find_enterprise!
      user = current_user
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      unless enterprise.feature_flag_enabled?(:billing_budget_api, default: false)
        deliver_error! 404, message: "Not Found"
      end

      customer_id = enterprise.customer_id.to_s
      response = Billing::Platform::Api::Client.new.delete_budget(customer_id: customer_id, uuid: params[:budget_id])

      if response.is_a?(Billing::Platform::Api::Error)
        if response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/delete-budget"])
          deliver_error! 404, message: "Budget with ID #{params[:budget_id]} not found."
        else
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/delete-budget"])
          deliver_error! 500, message: "Unable to delete budget."
        end
        return
      end

      GitHub.logger.info("billing.budget.delete",
        "gh.user.id": user.id,
        "gh.business.id": enterprise.id,
        "gh.billing.customer_id": customer_id,
        "gh.billing.budget_uuid": params[:budget_id],
        "gh.billing.pricing_target_id": response[:pricingTargetId] || "",
        "gh.billing.budget_api_enabled": true,
      )

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/delete-budget"])
      deliver_raw({
        message: "Budget successfully deleted.",
        id: params[:budget_id]
      }, status: 200)
    end

    get "/enterprises/:enterprise_id/settings/billing/premium_request/usage", operation_id: "billing/get-github-billing-premium-request-usage-report-ghe", read_from_replicas: true do
      operation = "billing/get-github-billing-premium-request-usage-report-ghe"
      enterprise = find_enterprise!
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      unless FeatureFlag.vexi.enabled?(:billing_premium_request_usage_api, enterprise, default: false)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:#{operation}"])
        deliver_error! 403, message: "No access to premium request usage."
      end

      if params[:user] && params[:organization]
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
        deliver_error! 400, message: "Cannot filter by both user and organization. Please specify only one."
      end

      if enterprise.is_copilot_standalone? && params[:organization]
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
        deliver_error! 400, message: "Copilot Standalone enterprises cannot filter by organization."
      end

      cost_center = validate_and_query_param("cost_center_id", entity: enterprise, operation: operation)
      organization = validate_and_query_param("organization", operation: operation)
      user = validate_and_query_param("user", operation: operation)

      time_params = parse_time_period_params(params)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]

      query = {
        customer_id: enterprise.customer_id,
        year: year,
        month: month,
        day: day,
        billing_period: get_billing_period_from_params(params),
        org_id: organization&.id,
        user_id: user&.id,
        model: format_query_param(params[:model]),
        product: format_query_param(params[:product]),
        cost_center_id: format_query_param(params[:cost_center_id])
      }
      usage_response = Billing::Platform::Api::Client.new.get_copilot_usage_report(**query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(usage_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:#{operation}"])
        deliver_error! 503, message: "Unable to get billing usage data."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:#{operation}"])
        deliver :premium_request_usage_report_hash, {
          entity: enterprise,
          reportItems: usage_response[:reportItems],
          costCenter: cost_center,
          user: user,
          organization: organization,
          query: query
        }
      end
    end

    get "/organizations/:organization_id/settings/billing/premium_request/usage", operation_id: "billing/get-github-billing-premium-request-usage-report-org", read_from_replicas: true do
      operation = "billing/get-github-billing-premium-request-usage-report-org"
      org = find_org!
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      unless FeatureFlag.vexi.enabled?(:billing_premium_request_usage_api, org, default: false)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:#{operation}"])
        deliver_error! 403, message: "No access to premium request usage."
      end

      if org.delegate_billing_to_business? && params[:user]
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:#{operation}"])
        deliver_error! 403, message: "Organization admins for enterprise owned organizations cannot filter usage by user"
      end

      user = validate_and_query_param("user", operation: operation)

      time_params = parse_time_period_params(params)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]

      customer_id = org.delegate_billing_to_business? ? org.business&.customer_id : org.customer&.id

      query = {
        customer_id: customer_id,
        year: year,
        month: month,
        day: day,
        # Specify the org ID if the organization delegates billing to a parent business so we can filter that customer's usage by this org
        org_id: org.delegate_billing_to_business? ? org.id : nil,
        billing_period: get_billing_period_from_params(params),
        user_id: user&.id,
        model: format_query_param(params[:model]),
        product: format_query_param(params[:product]),
      }
      usage_response = Billing::Platform::Api::Client.new.get_copilot_usage_report(**query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(usage_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:#{operation}"])
        deliver_error! 503, message: "Unable to get billing usage data."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:#{operation}"])
        deliver :premium_request_usage_report_hash, {
          entity: org,
          reportItems: usage_response[:reportItems],
          user: user,
          query: query
        }
      end
    end

    get "/user/:user_id/settings/billing/premium_request/usage", operation_id: "billing/get-github-billing-premium-request-usage-report-user", read_from_replicas: true do
      operation = "billing/get-github-billing-premium-request-usage-report-user"
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      unless FeatureFlag.vexi.enabled?(:billing_premium_request_usage_api, user, default: false)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:#{operation}"])
        deliver_error! 403, message: "No access to premium request usage."
      end

      time_params = parse_time_period_params(params)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]

      if user.customer.nil?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
        deliver_error! 400, message: "Unable to get billing usage data."
      end

      query = {
        customer_id: user.customer.id,
        year: year,
        month: month,
        day: day,
        billing_period: get_billing_period_from_params(params),
        model: format_query_param(params[:model]),
        product: format_query_param(params[:product]),
      }
      usage_response = Billing::Platform::Api::Client.new.get_copilot_usage_report(**query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(usage_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:#{operation}"])
        deliver_error! 503, message: "Unable to get billing usage data."
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:#{operation}"])
        deliver :premium_request_usage_report_hash, {
          entity: user,
          reportItems: usage_response[:reportItems],
          query: query
        }
      end
    end

    private

    # get time period params from the URL. All fields are optional and if year
    # is omitted we default to the current year. If other fields are omitted we use
    # the first day, first month or first hour as they will still be used to build time structs
    def parse_time_period_params(params)
      {
        year: params[:year].nil? ? Time.now.utc.year : params[:year].to_i,
        month: params[:month].nil? ? 1 : params[:month].to_i,
        day: params[:day].nil? ? 1 : params[:day].to_i,
        hour: params[:hour].nil? ? 0 : params[:hour].to_i
      }
    end

    def format_query_param(param)
      param.is_a?(String) ? param.strip.downcase : param
    end

    def add_repo_name_to_response(usage_response)
      repo_ids = usage_response[:reportItems].map { |item| item[:repoID] }.uniq

      repos = Repository.select(:id, :name).where(id: repo_ids)

      repositories = repos.map do |repo|
        [repo.id, repo]
      end.to_h

      usage_response[:reportItems].each do |item|
        repository = repositories[item[:repoID]]

        item[:repositoryName] = repository&.name || ""
      end
      usage_response
    end

    def add_org_and_repo_name_to_response(usage_response)
      repo_ids = usage_response[:reportItems].map { |item| item[:repoID] }.uniq
      org_ids = usage_response[:reportItems].map { |item| item[:orgID] }.uniq

      repos = Repository.select(:id, :name).where(id: repo_ids)
      orgs = Organization.select(:id, :display_login).where(id: org_ids)

      organizations = orgs.map do |org|
        [org.id, org]
      end.to_h

      repositories = repos.map do |repo|
        [repo.id, repo]
      end.to_h

      usage_response[:reportItems].each do |item|
        repository = repositories[item[:repoID]]
        organization = organizations[item[:orgID]]

        item[:repositoryName] = repository&.name || ""
        item[:organizationName] = organization&.display_login || ""
      end
      usage_response
    end

    # choose billing period based on input params
    # e.g. if just year and month is present, we want to choose a monthly billing period
    def get_billing_period_from_params(params)
      billing_period = BillingPlatform::Base::BillingPeriod::Yearly

      if !params[:year].nil? && params[:month].nil? && params[:day].nil? && params[:hour].nil?
        billing_period = BillingPlatform::Base::BillingPeriod::Yearly
      elsif !params[:month].nil? && params[:day].nil? && params[:hour].nil?
        billing_period = BillingPlatform::Base::BillingPeriod::Monthly
      elsif !params[:day].nil? && params[:hour].nil?
        billing_period = BillingPlatform::Base::BillingPeriod::Daily
      elsif !params[:hour].nil?
        billing_period = BillingPlatform::Base::BillingPeriod::Hourly
      end

      billing_period
    end

    def enterprise_members(enterprise, user_logins)
      members = Hash.new
      users = User.with_logins(user_logins)
        .pluck(:id, :display_login)
        .map { |id, display_login| [id, display_login.downcase] }
        .to_h

      enterprise.admins
        .where(id: users.keys)
        .pluck(:id, :display_login, :business_id)
        .each do |id, display_login, _|
          members[display_login.downcase] = id
        end

      if FeatureFlag.vexi.enabled?(:include_unaffiliated_enterprise_members, current_user, default: false)
        enterprise.filtered_members(current_user, include_unaffiliated: true)
          .where(user_id: users.keys)
          .each do |member|
            members[users[member.user_id]] = member.user_id if users[member.user_id]
          end
      else
        enterprise.filtered_members(current_user, ignore_org_membership_visibility: true)
          .where(user_id: users.keys)
          .each do |member|
            members[users[member.user_id]] = member.user_id if users[member.user_id]
          end
      end

      enterprise.filtered_outside_collaborators
        .where(display_login: user_logins)
        .pluck(:id, :display_login)
        .each do |id, display_login|
          members[display_login.downcase] = id
        end

      enterprise.pending_admin_invitations
        .where(invitee_id: users.keys)
        .each do |invitation|
          members[users[invitation.invitee_id]] = invitation.invitee_id if users[invitation.invitee_id]
        end

      enterprise.pending_member_invitations
        .where(invitee_id: users.keys)
        .each do |invitation|
          members[users[invitation.invitee_id]] = invitation.invitee_id if users[invitation.invitee_id]
        end

      [members.compact, users]
    end

    def enterprise_repositories(enterprise)
      {}.tap do |repositories|
        org_ids = enterprise.organizations.pluck(:id)
        Repository.active.preload(:owner).batched_scope(:owner_id, values: org_ids) { |s| s.select(:id, :name, :owner_id, :owner_login) }.each do |repo|
          full_repo_name = "#{repo.owner_display_login}/#{repo.name}".downcase
          repositories[full_repo_name] = repo.id
        end
      end
    end

    def validate_and_query_param(param_name, entity: nil, operation: nil)
      param_value = params[param_name.to_sym]
      return nil if param_value.nil?

      case param_name.to_s
      when "cost_center_id"
        validate_and_parse_cost_center(param_value, entity, operation)
      when "organization"
        validate_and_parse_organization(param_value, operation)
      when "user"
        validate_and_parse_user(param_value, operation)
      else
        raise ArgumentError, "Unknown parameter type: #{param_name}"
      end
    end

    def validate_and_parse_cost_center(cost_center_id, entity, operation)
      formatted_id = format_query_param(cost_center_id)
      return nil if formatted_id == "none"

      cost_center_response = Billing::Platform::Api::Client.new.get_cost_center(cost_center_key: {
        customerId: entity.customer_id.to_s,
        uuid: cost_center_id
      })

      if cost_center_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(cost_center_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:#{operation}"])
        deliver_error! 503, message: "Unable to get cost center premium request usage data."
      end

      if cost_center_response[:costCenter].nil?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
        deliver_error! 404, message: "Cost center '#{cost_center_id}' not found."
      end

      cost_center_response[:costCenter]
    end

    def validate_and_parse_organization(organization_param, operation)
      organization = Organization.find_by_login(format_query_param(organization_param))
      unless organization
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
        deliver_error! 404, message: "Organization '#{organization_param}' not found."
      end
      organization
    end

    def validate_and_parse_user(user_param, operation)
      user = User.find_by_login(format_query_param(user_param))
      unless user
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
        deliver_error! 404, message: "User '#{user_param}' not found."
      end
      user
    end
  end

  sig { params(billable_entity: T.any(Organization, Business), product_parameter: T.nilable(String)).returns(GitHub::Turboghas::SKU) }
  def advanced_security_requested_sku(billable_entity, product_parameter)
    sku = GitHub::Turboghas::SKU::Bundled

    if billable_entity.advanced_security_purchased?
      if product_parameter.blank? && !billable_entity.advanced_security_products_bundled?
        # If you've puchased unbundled Advanced Security you must provide a product parameter.
        deliver_error!(422, message: "You must specify 'advanced_security_product' in this request.")
      elsif product_parameter.present? && billable_entity.advanced_security_products_bundled?
        # If you've puchased bundled Advanced Security you cannot provide a product parameter.
        deliver_error!(422, message: "The 'advanced_security_product' cannot be provided when using bundled Advanced Security.")
      end
    end
    # If you've not purchased Advanced Security, `advanced_security_product` is optional.

    if product_parameter.present?
      # If the product parameter is specified, it must be valid.
      sku = GitHub::Turboghas::SKU.from_param(product_parameter)
      if sku == GitHub::Turboghas::SKU::Bundled
        deliver_error!(422, message: "You must specify a valid 'advanced_security_product' in this request.")
      end
    end

    sku
  end

  def filter_by_organization_access(user, organization_names, enterprise_organizations, is_enterprise_admin)
    organizations = []
    organization_id_to_name = {}

    organization_names.each do |name|
      organization = enterprise_organizations.find_by(display_login: name)
      if organization
        if is_enterprise_admin || organization.adminable_by?(user)
          organization_id_to_name[organization.id] = name
          organizations << {
            id: organization.id.to_s,
            type: BillingPlatform::Base::ResourceType::Org,
          }
        else
          deliver_error! 403, message: "User not an admin of organization: '#{name}'"
        end
      else
        deliver_error! 403, message: "Organization not part of enterprise: '#{name}'"
      end
    end

    [organizations, organization_id_to_name]
  end

  def filter_by_repository_access(user, repository_names, available_repositories, is_enterprise_admin)
    return [], {} if repository_names.empty?

    repository_ids = []
    repository_id_to_name = {}

    repository_ids_map = Repository.where(id: available_repositories.values_at(*repository_names)).index_by(&:id)
    repository_names.each do |name|
      repository = repository_ids_map[available_repositories[name]]
      if repository
        if is_enterprise_admin || repository.adminable_by?(user)
          repository_id_to_name[repository.id] = name
          repository_ids << {
            id: repository.id.to_s,
            type: BillingPlatform::Base::ResourceType::Repo,
          }
        else
          deliver_error! 403, message: "User not an admin of repository: '#{name}'"
        end
      else
        deliver_error! 403, message: "Repository not part of enterprise: '#{name}'"
      end
    end

    [repository_ids, repository_id_to_name]
  end
end
