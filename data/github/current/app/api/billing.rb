# typed: true
# frozen_string_literal: true

class Api::Billing < Api::App
  include SecretScanning::Features::FeatureFlagHelper
  include Billing::Platform::Api::Utils
  include Billing::TokenBasedBilling

  # Custom error for invalid alert recipients
  class InvalidAlertRecipientsError < StandardError
    attr_reader :missing_usernames

    def initialize(missing_usernames)
      @missing_usernames = missing_usernames
      super("Invalid alert recipients: #{missing_usernames.join(', ')}")
    end
  end

  # Custom error for invalid budget request parameters
  class InvalidBudgetParametersError < StandardError
  end

  HIGH_WATERMARK_SKUS = %w[
    copilot_for_business
    copilot_standalone
    copilot_enterprise
    ghec_licenses
    ghas_licenses
    ghas_code_security_licenses
    ghas_secret_protection_licenses
  ].freeze

  ORGANIZATION_BUDGET_SCOPES = %w[repository organization multi_user_customer user].freeze
  ENTERPRISE_BUDGET_SCOPES = %w[cost_center repository organization enterprise multi_user_customer multi_user_cost_center user].freeze
  USER_LEVEL_BUDGET_SCOPES = %w[multi_user_cost_center multi_user_customer user].freeze
  BILLING_PLATFORM_USER_LEVEL_BUDGET_SCOPES = %w[MultiUserCustomer MultiUserCostCenter User].freeze # Remove when allowing soft limit user budgets
  VALID_BUDGET_TYPES = %w[ProductPricing SkuPricing BundlePricing].freeze
  VALID_BUNDLE_PRICING_TARGET_IDS = %w[premium_requests ai_credits].freeze # temporary list of bundle pricing target IDs pending when we have proper bundle type list helper - https://github.com/github/gitcoin/issues/24902
  HIDDEN_TBB_PREMIUM_REQUEST_SKUS = %w[coding_agent_premium_request copilot_premium_request spark_premium_request].freeze

  API_FIELD_NAMES = {
    "targetId" => "budget_entity_name",
    "targetType" => "budget_scope",
    "targetAmount" => "budget_amount",
    "pricingTargetType" => "budget_type",
    "pricingTargetId" => "budget_product_sku",
    "alertEnabled" => "budget_alerting.will_alert",
    "alertRecipientUserIds" => "budget_alerting.alert_recipient_user_ids",
  }.freeze

  MAX_NUMBER_OF_RESOURCES = 50

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

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-github-actions-billing-user"])
      deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-user"
    end

    # Get Actions billing information for organizations
    get "/organizations/:organization_id/settings/billing/actions", operation_id: "billing/get-github-actions-billing-org" do
      org = find_org!
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-github-actions-billing-org"])
      deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-org"
    end

    # Get Actions billing information for enterprises
    get "/enterprises/:enterprise_id/settings/billing/actions", operation_id: "billing/get-github-actions-billing-ghe" do
      enterprise = find_enterprise!
      control_access :manage_business_billing,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-github-actions-billing-ghe"])
      deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates"
    end

    def serialize_actions_usage(billable_owner:, owner: nil)
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
    end

    # Get Packages billing information for users
    get "/user/:user_id/settings/billing/packages", operation_id: "billing/get-github-packages-billing-user" do
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-github-packages-billing-user"])
      deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-user"
    end

    # Get Packages billing information for organizations
    get "/organizations/:organization_id/settings/billing/packages", operation_id: "billing/get-github-packages-billing-org" do
      org = find_org!
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-github-packages-billing-org"])
      deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-org"
    end

    # Get Packages billing information for enterprises
    get "/enterprises/:enterprise_id/settings/billing/packages", operation_id: "billing/get-github-packages-billing-ghe" do
      enterprise = find_enterprise!
      control_access :manage_business_billing,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-github-packages-billing-ghe"])
      deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates"
    end

    def serialize_packages_usage(billable_owner:, owner: nil)
      { total_gigabytes_bandwidth_used: 0, total_paid_gigabytes_bandwidth_used: 0, included_gigabytes_bandwidth: 0 }
    end

    # Get shared storage billing information for shared users
    get "/user/:user_id/settings/billing/shared-storage", operation_id: "billing/get-shared-storage-billing-user" do
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-shared-storage-billing-user"])
      deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-user"
    end

    # Get shared storage billing information for shared organizations
    get "/organizations/:organization_id/settings/billing/shared-storage", operation_id: "billing/get-shared-storage-billing-org" do
      org = find_org!
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-shared-storage-billing-org"])
      deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates-org"
    end

    # Get shared storage billing information for shared enterprises
    get "/enterprises/:enterprise_id/settings/billing/shared-storage", operation_id: "billing/get-shared-storage-billing-ghe" do
      enterprise = find_enterprise!
      control_access :manage_business_billing,
        resource: enterprise,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:410", "operation:billing/get-shared-storage-billing-ghe"])
      deliver_error! 410, message: "This endpoint has been moved.", documentation_url: "https://gh.io/billing-api-updates"
    end

    def serialize_shared_storage_usage(billable_owner:, owner: nil)
      { days_left_in_billing_cycle: 0, estimated_paid_storage_for_month: 0, estimated_storage_for_month: 0 }
    end

    get "/user/:user_id/settings/billing/usage", operation_id: "billing/get-github-billing-usage-report-user" do
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      unless user&.customer&.present?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/get-github-billing-usage-report-user"])
        deliver_error! 403, message: "No access to billing usage data."
      end

      validate_no_hourly_param(params, operation: "billing/get-github-billing-usage-report-user")

      time_params = parse_time_period_params(params)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]

      new_query = {
        usage_entity_id: user.customer.id,
        year: year,
        month: month,
        day: day,
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

      validate_no_hourly_param(params, operation: "billing/get-github-billing-usage-report-ghe")

      time_params = parse_time_period_params(params)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]

      # if a cost center id is passed in, we want to get usage data for that specific cost center, otherwise
      # we query a usage report for the enterprise customer
      usage_entity_id = params[:cost_center_id].nil? ? enterprise.customer_id : params[:cost_center_id]

      # Validate if cost center belongs to the enterprise customer
      unless params[:cost_center_id].nil?
        validate_org_owner_cost_center_access!(current_user, enterprise, params[:cost_center_id], "billing/get-github-billing-usage-report-ghe")

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
      control_access :view_org_usage,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      unless org.delegate_billing_to_business? || org.customer&.present?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/get-github-billing-usage-report-org"])
        deliver_error! 403, message: "No access to billing usage data."
      end

      validate_no_hourly_param(params, operation: "billing/get-github-billing-usage-report-org")

      time_params = parse_time_period_params(params)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]

      usage_entity_id = org.delegate_billing_to_business? ? org.business&.customer_id : org.customer&.id

      new_query = {
        usage_entity_id: usage_entity_id,
        year: year,
        month: month,
        day: day,
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

      # API queries should not read from the cache to ensure the most up-to-date data is returned
      client_params = { customer_id: enterprise.customer_id.to_s, use_cache: false }

      if params[:state].present?
        # Translate user-friendly state values to internal API values
        translated_state = case params[:state].downcase
        when "active"
          BillingPlatform::Base::CostCenterState::CostCenterActive
        when "deleted"
          BillingPlatform::Base::CostCenterState::CostCenterArchived
        else
          # If an unrecognized state is provided, return an error
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/get-all-cost-centers"])
          deliver_error! 400, message: "Invalid state parameter. Must be 'active' or 'deleted'."
        end

        client_params[:state] = translated_state
      end
      all_cost_centers_response = Billing::Platform::Api::Client.new.get_all_cost_centers(**client_params)

      if all_cost_centers_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(all_cost_centers_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-all-cost-centers"])
        deliver_error! 503, message: "Unable to get billing cost center data for all cost centers."
      else
        # Limit resources per type to 1000 when feature flag is enabled
        if FeatureFlag.vexi.enabled?(:billing_optimize_cost_centers_query, enterprise, default: false)
          all_cost_centers_response[:costCenters].each do |cost_center|
            if cost_center[:resources]
              # Group resources by type and limit each to 1000
              user_resources, org_resources, repo_resources = [], [], []
              cost_center[:resources].each do |resource|
                case resource[:type].to_s
                when Billing::Platform::Api::Utils::USER_TARGET
                  user_resources << resource if user_resources.size < 1000
                when Billing::Platform::Api::Utils::ORGANIZATION_TARGET
                  org_resources << resource if org_resources.size < 1000
                when Billing::Platform::Api::Utils::REPOSITORY_TARGET
                  repo_resources << resource if repo_resources.size < 1000
                end
              end

              cost_center[:resources] = user_resources + org_resources + repo_resources
            end
          end
        end

        cost_centers = all_cost_centers_response[:costCenters] || []
        filtered_cost_centers = filter_cost_centers_for_org_owner(current_user, enterprise, cost_centers)
        filtered_response = all_cost_centers_response.merge(costCenters: filtered_cost_centers)

        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-all-cost-centers"])
        deliver :all_cost_centers_hash, filtered_response
      end
    end

    post "/enterprises/:enterprise_id/settings/billing/cost-centers", operation_id: "billing/create-cost-center", read_from_replicas: true do
      enterprise = find_enterprise!

      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      validate_not_org_owner_for_cost_center!(current_user, enterprise, "billing/create-cost-center")

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
        resources: [],
      }
      if enterprise.feature_flag_enabled?(:billing_add_cost_center_description, default: false) && data["description"].present?
        create_params[:description] = data["description"]
      end

      if FeatureFlag.vexi.enabled?(:billing_cost_centers_ui_pagination_enabled, enterprise, default: false)
        create_params[:business] = enterprise
      end

      begin
        client = Billing::Platform::Api::Client.new
        response = client.create_cost_center(**create_params)

        if response.is_a?(Billing::Platform::Api::Error)
          if response.already_exists?
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:409", "operation:billing/create-cost-center"])
            deliver_error! 409, message: response.original_error.msg
          elsif response.resource_exhausted?
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-cost-center"])
            deliver_error! 400, message: response.original_error.msg
          else
            Failbot.report(response)
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

    # Get cost center membership for a resource
    get "/enterprises/:enterprise_id/settings/billing/cost-centers/memberships", operation_id: "billing/get-cost-center-membership" do
      enterprise = find_enterprise!

      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      # Check feature flag
      unless enterprise.feature_flag_enabled?(:cost_center_api_improvements, default: false)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/get-cost-center-membership"])
        deliver_error! 404
      end

      # Validate required parameters
      resource_type = params[:resource_type]
      name = params[:name]

      if resource_type.blank? || name.blank?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/get-cost-center-membership"])
        deliver_error! 400, message: "Parameters 'resource_type' and 'name' are required."
      end

      # Validate resource_type
      unless %w[user repository organization].include?(resource_type)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/get-cost-center-membership"])
        deliver_error! 400, message: "Invalid resource_type. Must be one of: user, repository, organization."
      end

      # Resolve the resource identifier to internal ID
      resolved_resource = case resource_type
      when "user"
        user = User.find_by_login(name.downcase)
        if user.nil?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/get-cost-center-membership"])
          deliver_error! 404, message: "User '#{name}' not found."
        end
        { actorId: user.id }
      when "organization"
        org = enterprise.organizations.find_by(login: name.downcase)
        if org.nil?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/get-cost-center-membership"])
          deliver_error! 404, message: "Organization '#{name}' not found in enterprise."
        end
        { ownerId: org.id }
      when "repository"
        # Parse owner/repo format
        owner_name, repo_name = name.downcase.split("/", 2)
        if owner_name.nil? || repo_name.nil?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/get-cost-center-membership"])
          deliver_error! 400, message: "Repository name must be in 'owner/repo' format."
        end

        owner_org = enterprise.organizations.find_by(login: owner_name)
        if owner_org.nil?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/get-cost-center-membership"])
          deliver_error! 404, message: "Repository owner '#{owner_name}' not found in enterprise."
        end

        repo = Repository.where(owner_id: owner_org.id, name: repo_name).first
        if repo.nil?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/get-cost-center-membership"])
          deliver_error! 404, message: "Repository '#{name}' not found."
        end
        { repoId: repo.id }
      end

      # Call find_cost_center_for API
      entity_detail = {
        customerId: enterprise.customer_id.to_s
      }.merge(T.must(resolved_resource))

      cost_center_response = Billing::Platform::Api::Client.new.find_cost_center_for(entity_detail: entity_detail)

      if cost_center_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(cost_center_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/get-cost-center-membership"])
        deliver_error! 503, message: "Unable to get cost center membership data."
      end

      # Build response
      resource_identifier = case resource_type
      when "user"
        { type: "user", identifier: { login: name } }
      when "organization"
        { type: "organization", identifier: { name: name } }
      when "repository"
        owner_name, repo_name = name.split("/", 2)
        { type: "repository", identifier: { owner: owner_name, name: repo_name } }
      end

      memberships = []
      if cost_center_response[:costCenterKey].present?
        cost_center_uuid = cost_center_response[:costCenterKey][:uuid]

        # Fetch cost center details
        cost_center_details = Billing::Platform::Api::Client.new.get_cost_center(
          cost_center_key: {
            customerId: enterprise.customer_id.to_s,
            uuid: cost_center_uuid
          }
        )

        unless cost_center_details.is_a?(Billing::Platform::Api::Error) || cost_center_details[:costCenter].nil?
          memberships << {
            cost_center: {
              id: cost_center_uuid,
              name: cost_center_details[:costCenter][:name]
            }
          }
        end
      end

      response_data = {
        resource: resource_identifier,
        memberships: memberships
      }

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-cost-center-membership"])
      deliver_raw(response_data, status: 200)
    end

    get "/enterprises/:enterprise_id/settings/billing/cost-centers/:cost_center_id", operation_id: "billing/get-cost-center" do
      enterprise = find_enterprise!
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

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
        # Validate org owner access - they can only view cost centers with resources they admin
        cost_center = cost_center_response[:costCenter]
        unless org_owner_has_cost_center_access?(current_user, enterprise, cost_center)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/get-cost-center"])
          deliver_error! 404, message: "Cost center with Uuid: #{params[:cost_center_id]} for #{enterprise.name} not found."
        end

        # Check if pagination optimization is enabled OR if pagination params are provided
        pagination_params_provided = params[:page].present? || params[:per_page].present?
        if enterprise.feature_flag_enabled?(:billing_optimize_cost_centers_query, default: false) || pagination_params_provided
          # Parse pagination parameters
          page = [params[:page]&.to_i || 1, 1].max
          per_page = [params[:per_page]&.to_i || 1000, 1000].min

          # Pass pagination options to serializer
          options = {
            paginate: true,
            page: page,
            per_page: per_page,
            include_pagination_metadata: true
          }

          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-cost-center"])
          deliver :cost_center_hash, cost_center_response, options
        else
          # Legacy behavior without pagination
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-cost-center"])
          deliver :cost_center_hash, cost_center_response
        end
      end
    end

    delete "/enterprises/:enterprise_id/settings/billing/cost-centers/:cost_center_id", operation_id: "billing/delete-cost-center" do
      enterprise = find_enterprise!

      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      validate_org_owner_cost_center_access!(current_user, enterprise, params[:cost_center_id], "billing/delete-cost-center")

      # Try to archive the cost center
      archive_response = Billing::Platform::Api::Client.new.archive_cost_center(
        cost_center_key: {
          customerId: enterprise.customer_id.to_s,
          uuid: params[:cost_center_id]
        },
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

      if FeatureFlag.vexi.enabled?(:billing_cost_centers_ui_pagination_enabled, enterprise, default: false)
        archive_response[:business] = enterprise
      end

      GitHub.instrument "billing.cost_center_delete", {
        actor: current_user,
        customer_id: enterprise.customer_id.to_s,
        business: enterprise,
        uuid: params[:cost_center_id],
        name: archive_response[:costCenter][:name],
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

      validate_org_owner_cost_center_access!(current_user, enterprise, params[:cost_center_id], "billing/update-cost-center")

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

      validate_org_owner_cost_center_access!(current_user, enterprise, params[:cost_center_id], "billing/add-resource-to-cost-center")

      data = receive_with_openapi
      user_logins = data["users"]&.map(&:downcase) || []
      user_ids = []

      organization_names = data["organizations"] || []
      enterprise_organizations = enterprise.organizations

      repository_names = data["repositories"]&.map(&:downcase) || []

      enterprise_team_slugs = data["enterprise_teams"]&.map(&:downcase) || []
      team_ids = []

      if enterprise_team_slugs.any? && !FeatureFlag.vexi.enabled?(:billing_cost_centers_enterprise_teams, enterprise.customer, default: false)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/add-resource-to-cost-center"])
        deliver_error! 404, message: "Enterprise teams are not supported for this enterprise."
      end

      total_resource_count = user_logins.length + organization_names.length + repository_names.length + enterprise_team_slugs.length
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
        "gh.billing.cost_center.team_count": enterprise_team_slugs.length,
      )

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

      team_id_to_slug = {}
      if enterprise_team_slugs.any?
        raw_team_slugs = enterprise_team_slugs.map { |s| BusinessTeam.to_model_slug(s) }
        matched_teams = enterprise.business_teams.where(slug: raw_team_slugs)
        not_matched_slugs = raw_team_slugs - matched_teams.map { |t| BusinessTeam.to_model_slug(t.slug).downcase }
        if not_matched_slugs.any?
          deliver_error! 404, message: "These enterprise teams were not found: '#{not_matched_slugs.join("', '")}'"
        end

        matched_teams.each do |team|
          team_ids << {
            id: team.id.to_s,
            type: BillingPlatform::Base::ResourceType::Team,
          }
          team_id_to_slug[team.id] = team.slug
        end
      end

      is_enterprise_admin = enterprise_admin_or_billing_manager?(user, enterprise)
      organization_ids, organization_id_to_name = filter_by_organization_access(user, organization_names, enterprise_organizations, is_enterprise_admin)

      repository_ids, repository_id_to_name = GitHub.dogstats.distribution_time("billing_platform.api.add_resource_to_cost_center.repo_filtering") do
        start_time = Time.current.utc

        repository_ids, repository_id_to_name = filter_by_repository_access(user, repository_names, enterprise, is_enterprise_admin)

        GitHub.logger.info(
          "billing_platform.api.add_resource_to_cost_center.repo_filtering",
          "gh.duration_ms": (Time.current.utc - start_time) * 1000,
        )

        [repository_ids, repository_id_to_name]
      end

      entity_ids = user_ids + organization_ids + repository_ids + team_ids

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
        when "Team"
          team_slug = team_id_to_slug[resource[:resource][:id].to_i]
          next if team_slug.nil?
          resources << { resource_type: "Team", name: team_slug, previous_cost_center: resource[:previousCostCenterName] }
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

      validate_org_owner_cost_center_access!(current_user, enterprise, params[:cost_center_id], "billing/remove-resource-from-cost-center")

      data = receive_with_openapi
      user_logins = data["users"] || []
      user_ids = []

      organization_names = data["organizations"] || []
      enterprise_organizations = enterprise.organizations

      repository_names = data["repositories"]&.map(&:downcase) || []

      enterprise_team_slugs = data["enterprise_teams"]&.map(&:downcase) || []
      team_ids = []

      if enterprise_team_slugs.any? && !FeatureFlag.vexi.enabled?(:billing_cost_centers_enterprise_teams, enterprise.customer, default: false)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/remove-resource-from-cost-center"])
        deliver_error! 404, message: "Enterprise teams are not supported for this enterprise."
      end

      total_resource_count = user_logins.length + organization_names.length + repository_names.length + enterprise_team_slugs.length
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
        "gh.billing.cost_center.team_count": enterprise_team_slugs.length,
      )

      User.where(display_login: user_logins).select(:id, :business_id).each do |user|
        user_ids << {
          id: user.id.to_s,
          type: BillingPlatform::Base::ResourceType::User,
        }
      end

      if enterprise_team_slugs.any?
        raw_team_slugs = enterprise_team_slugs.map { |s| BusinessTeam.to_model_slug(s) }
        enterprise.business_teams.where(slug: raw_team_slugs).each do |team|
          team_ids << {
            id: team.id.to_s,
            type: BillingPlatform::Base::ResourceType::Team,
          }
        end
      end

      is_enterprise_admin = enterprise_admin_or_billing_manager?(user, enterprise)
      soft_deleted_orgs = enterprise.soft_deleted_organizations
      organization_ids, _organization_id_to_name = filter_by_organization_access(user, organization_names, enterprise_organizations, is_enterprise_admin, soft_deleted_orgs: soft_deleted_orgs)

      repository_ids, _ = filter_by_repository_access(user, repository_names, enterprise, is_enterprise_admin)

      entity_ids = user_ids + organization_ids + repository_ids + team_ids

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

    post "/enterprises/:enterprise_id/settings/billing/budgets", operation_id: "billing/create-budget", read_from_replicas: true do
      enterprise = find_enterprise!
      user = current_user
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      customer_id = enterprise.customer_id.to_s

      begin
        request_data = JSON.parse(request.body.read)
      rescue JSON::ParserError
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
        deliver_error! 400, message: "Invalid JSON in request body."
      end

      # Validate budget_scope if provided
      if request_data["budget_scope"].present?
        budget_scope = request_data["budget_scope"]
        cost_center_user_level_budgets_enabled = enterprise.feature_flag_enabled?(:billing_cost_center_user_level_budgets, default: false)

        unless ENTERPRISE_BUDGET_SCOPES.include?(budget_scope)
          valid_scopes = ENTERPRISE_BUDGET_SCOPES
          if !cost_center_user_level_budgets_enabled
            valid_scopes -= ["multi_user_cost_center"]
          end
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
          deliver_error! 400, message: "Invalid budget_scope '#{request_data["budget_scope"]}'. Must be one of: #{valid_scopes.join(", ")}."
        end

        is_user_level_budget = USER_LEVEL_BUDGET_SCOPES.include?(budget_scope)
        if is_user_level_budget
          # Validate only ai_credit bundles can be created as user level budgets
          if !VALID_BUNDLE_PRICING_TARGET_IDS.include?(request_data["budget_product_sku"])
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
            deliver_error! 400, message: "Invalid budget_product_sku '#{request_data["budget_product_sku"]}'. Must be one of: #{VALID_BUNDLE_PRICING_TARGET_IDS.join(', ')} for #{budget_scope} budget scope."
          end

          # Validate multi_user_cost_center scope is only used if the feature flag is enabled
          if budget_scope == "multi_user_cost_center" && !cost_center_user_level_budgets_enabled
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
            deliver_error! 400, message: "Invalid budget_scope '#{request_data["budget_scope"]}'."
          end

          # Validate prevent_further_usage - for user level budgets, this must be true
          if request_data["prevent_further_usage"] == false
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
            deliver_error! 400, message: "prevent_further_usage must be 'true' for user-scoped budgets."
          end
        end
      end

      # Validate exclude_cost_center_usage is only used with enterprise scope
      if request_data.key?("exclude_cost_center_usage") && request_data["budget_scope"] != "enterprise"
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
        deliver_error! 400, message: "exclude_cost_center_usage can only be used with enterprise-scoped budgets."
      end

      # Validate budget_type is a known pricing type
      if request_data["budget_type"].present? && !VALID_BUDGET_TYPES.include?(request_data["budget_type"])
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
        deliver_error! 400, message: "Invalid budget_type '#{request_data["budget_type"]}'. Must be one of: #{VALID_BUDGET_TYPES.join(', ')}."
      end

      GitHub.logger.info("billing.budget.create_request",
        "gh.user.id": user.id,
        "gh.business.id": enterprise.id,
        "gh.billing.customer.id": customer_id,
        "gh.billing.request_data": request_data.to_json,
        "gh.billing.budget_scope": request_data["budget_scope"],
        "gh.billing.budget_entity_name": request_data["budget_entity_name"]
      )

      # Support for organization-level and repository-level budgets within enterprise context
      target_entity = resolve_target_entity(request_data, enterprise, customer_id, current_user)

      # Validate budget_product_sku against valid products/SKUs for the resolved target entity
      validate_budget_product_sku!(request_data, target_entity || enterprise, "billing/create-budget")

      begin
        raw_budget_request_data = transform_budget_upsert_request_data(request_data, customer_id, nil, target_entity)
      rescue InvalidBudgetParametersError => e
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
        deliver_error! 400, message: e.message
      rescue InvalidAlertRecipientsError => e
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
        deliver_error! 400, message: "Invalid alert recipients: #{e.missing_usernames.join(', ')} do not exist."
      end

      begin
        create_budget_request = Billing::Platform::Api::UpsertBudgetRequest.new(
          raw_upsert_budget_request: raw_budget_request_data,
          current_user: user,
          customer_id: customer_id,
          this_entity: enterprise
        )
      rescue Billing::Platform::Api::UpsertBudgetRequest::InvalidTargetError
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
        deliver_error! 400, message: "Invalid target specified."
      rescue Billing::Platform::Api::UpsertBudgetRequest::InvalidRequestError => e
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
        error_message = "Invalid request parameters."
        if e.message.present? && e.message != e.class.to_s
          error_message += " #{translate_budget_field_names(e.message, request_data)}"
        end
        deliver_error! 400, message: error_message
      rescue Billing::Platform::Api::UpsertBudgetRequest::InvalidAccessError
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/create-budget"])
        deliver_error! 404, message: "Not found."
      end

      # Check if budget already exists
      existing_budget_response = Billing::Platform::Api::Client.new.get_budget(key: create_budget_request.json_key)

      # If response is not an error and has budget data, it means budget already exists
      if !existing_budget_response.is_a?(Billing::Platform::Api::Error) && existing_budget_response[:budget].present?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:409", "operation:billing/create-budget"])
        GitHub.logger.info("billing.budget.duplicate_attempt",
          "gh.user.id": user.id,
          "gh.business.id": enterprise.id,
          "gh.billing.customer.id": customer_id,
          "gh.billing.budget_key": create_budget_request.json_key
        )
        deliver_error! 409, message: "A budget with this scope already exists for the specified entity."
      end

      response = Billing::Platform::Api::Client.new.create_or_update_budget(budget: create_budget_request.to_json, feature_flag_target: enterprise)

      if response.is_a?(Billing::Platform::Api::Error)
        if response.inactive_cost_center?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:412", "operation:billing/create-budget"])
          deliver_error! 412, message: "The specified cost center is not active."
        elsif response.product_not_found?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/create-budget"])
          deliver_error! 404, message: product_not_found_message(target_entity || enterprise, response.original_error.msg)
        elsif response.sku_not_found?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/create-budget"])
          deliver_error! 404, message: sku_not_found_message(target_entity || enterprise, response.original_error.msg)
        elsif response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/create-budget"])
          deliver_error! 404, message: "The specified resource was not found."
        else
          Failbot.report(response, context: { operation: "billing/create-budget", customer_id: customer_id })
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/create-budget"])
          deliver_error! 500, message: "Unable to create budget. #{response.user_message}"
        end
      end

      # Log success with appropriate entity details
      log_data = {
        "gh.user.id": user.id,
        "gh.business.id": enterprise.id,
        "gh.billing.customer.id": customer_id,
        "gh.billing.pricing_target_id": raw_budget_request_data[:pricingTargetId] || "",
        "gh.billing.budget_scope": request_data["budget_scope"],
        "gh.billing.budget_api_enabled": true,
      }

      if target_entity.is_a?(Organization)
        log_data["gh.organization.id"] = target_entity.id
        log_data["gh.organization.display_login"] = target_entity.display_login
      elsif target_entity.is_a?(Repository)
        log_data["gh.repository.id"] = target_entity.id
        log_data["gh.repository.name"] = target_entity.name
      end

      budget_json = user_friendly_budget_schema(response, entity: target_entity, method: :post)

      GitHub.logger.info("billing.budget.created", log_data)

      # Instrument audit log for budget creation
      GitHub.instrument "billing.budget_create", {
        actor: user,
        customer_id: customer_id,
        business: enterprise,
        target_amount: create_budget_request.target_amount,
        target_type: create_budget_request.target_type,
        target_id: create_budget_request.target_id,
        alert_enabled: create_budget_request.alert_enabled?,
        pricing_target_type: create_budget_request.pricing_target_type,
        pricing_target_id: create_budget_request.pricing_target_id,
        budget_limit_type: create_budget_request.budget_limit_type,
        exclude_cost_center_usage: create_budget_request.exclude_cost_center_usage,
        status: "success"
      }

      # Send budget changed notification
      reason_type = reason_type(create_budget_request)
      publish_budget_changed_notification(create_budget_request.pricing_target_id, create_budget_request.pricing_target_type, enterprise, customer_id, reason_type, target_type: create_budget_request.target_type, target_id: create_budget_request.target_id)

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/create-budget"])
      deliver_raw({ message: "Budget successfully created.", budget: budget_json }, status: 200)
    end

    patch "/enterprises/:enterprise_id/settings/billing/budgets/:budget_id", operation_id: "billing/update-budget", read_from_replicas: true do
      enterprise = find_enterprise!
      user = current_user
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      customer_id = enterprise.customer_id.to_s

      begin
        request_data = JSON.parse(request.body.read)
      rescue JSON::ParserError
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/update-budget"])
        deliver_error! 400, message: "Invalid JSON in request body."
      end

      validate_budget_update_restricted_fields(request_data, "billing/update-budget")

      existing_budget_response = Billing::Platform::Api::Client.new.get_budget_by_uuid(customer_id: customer_id, uuid: params[:budget_id])
      if existing_budget_response.is_a?(Billing::Platform::Api::Error)
        if existing_budget_response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/update-budget"])
          deliver_error! 404, message: "Budget with ID #{params[:budget_id]} not found."
        else
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/update-budget"])
          deliver_error! 500, message: "Unable to retrieve budget."
        end
        return
      end

      existing_budget = transform_budget_response(existing_budget_response)

      # exclude_cost_center_usage can only be updated for enterprise-scoped budgets
      if request_data.key?("exclude_cost_center_usage")
        existing_budget_scope = map_target_type_to_scope(existing_budget.target_type)
        if existing_budget_scope != "enterprise"
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/update-budget"])
          deliver_error! 400, message: "exclude_cost_center_usage can only be used with enterprise-scoped budgets."
        end
      end

      # Validate budget_type is a known pricing type
      if request_data["budget_type"].present? && !VALID_BUDGET_TYPES.include?(request_data["budget_type"])
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/update-budget"])
        deliver_error! 400, message: "Invalid budget_type '#{request_data["budget_type"]}'. Must be one of: #{VALID_BUDGET_TYPES.join(', ')}."
      end

      # Validate prevent_further_usage - for user level budgets, this must be true
      is_user_level_budget = USER_LEVEL_BUDGET_SCOPES.include?(map_target_type_to_scope(existing_budget.target_type)) && VALID_BUNDLE_PRICING_TARGET_IDS.include?(existing_budget.pricing_target_id)
      if is_user_level_budget && request_data["prevent_further_usage"] == false
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/update-budget"])
        deliver_error! 400, message: "prevent_further_usage must be 'true' for user-scoped budgets."
      end

      # Validate budget_product_sku against valid products/SKUs
      validate_budget_product_sku!(request_data, enterprise, "billing/update-budget")

      begin
        raw_budget_request_data = transform_budget_upsert_request_data(request_data, customer_id, existing_budget_response, enterprise)
      rescue InvalidBudgetParametersError => e
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/update-budget"])
        deliver_error! 400, message: e.message
      rescue InvalidAlertRecipientsError => e
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/update-budget"])
        deliver_error! 400, message: "Invalid alert recipients: #{e.missing_usernames.join(', ')} do not exist."
      end

      begin
        update_budget_request = Billing::Platform::Api::UpsertBudgetRequest.new(
          raw_upsert_budget_request: raw_budget_request_data,
          current_user: user,
          customer_id: customer_id,
          this_entity: enterprise
        )
      rescue Billing::Platform::Api::UpsertBudgetRequest::InvalidTargetError
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/update-budget"])
        deliver_error! 400, message: "Invalid target specified."
      rescue Billing::Platform::Api::UpsertBudgetRequest::InvalidRequestError => e
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/update-budget"])
        error_message = "Invalid request parameters."
        if e.message.present? && e.message != e.class.to_s
          error_message += " #{translate_budget_field_names(e.message, request_data)}"
        end
        deliver_error! 400, message: error_message
      rescue Billing::Platform::Api::UpsertBudgetRequest::InvalidAccessError
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/update-budget"])
        deliver_error! 404, message: "Not found."
      end

      response = Billing::Platform::Api::Client.new.create_or_update_budget(budget: update_budget_request.to_json, feature_flag_target: enterprise)

      if response.is_a?(Billing::Platform::Api::Error)
        if response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/update-budget"])
          deliver_error! 404, message: "The specified budget was not found."
        else
          Failbot.report(response, context: { operation: "billing/update-budget", customer_id: customer_id })
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/update-budget"])
          deliver_error! 503, message: "Unable to update budget. #{response.user_message}"
        end
      end

      # Log the update
      GitHub.logger.info("billing.budget.update",
        "gh.user.id": user.id,
        "gh.business.id": enterprise.id,
        "gh.billing.customer.id": customer_id,
        "gh.billing.budget_uuid": params[:budget_id],
        "gh.billing.pricing_target_id": update_budget_request.pricing_target_id,
        "gh.billing.pricing_target_type": update_budget_request.pricing_target_type,
        "gh.billing.target_amount": update_budget_request.target_amount,
        "gh.billing.budget_api_enabled": true,
      )

      # Instrument the update
      GitHub.instrument "billing.budget_update", {
        actor: user,
        customer_id: customer_id,
        business: enterprise,
        budget_uuid: params[:budget_id],
        target_amount: update_budget_request.target_amount,
        target_type: update_budget_request.target_type,
        target_id: update_budget_request.target_id,
        alert_enabled: update_budget_request.alert_enabled?,
        pricing_target_type: update_budget_request.pricing_target_type,
        pricing_target_id: update_budget_request.pricing_target_id,
        budget_limit_type: update_budget_request.budget_limit_type,
        exclude_cost_center_usage: update_budget_request.exclude_cost_center_usage,
        status: "success"
      }

      # Send budget changed notification
      reason_type = reason_type(update_budget_request)
      publish_budget_changed_notification(update_budget_request.pricing_target_id, update_budget_request.pricing_target_type, enterprise, customer_id, reason_type, target_type: update_budget_request.target_type, target_id: update_budget_request.target_id)

      GitHub.dogstats.increment("billing.budget_update", tags: ["pricing_target_id:#{update_budget_request.pricing_target_id}", "account_type:business"])
      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/update-budget"])

      budget_json = user_friendly_budget_schema(response, entity: enterprise, method: :patch)

      deliver_raw({
        message: "Budget successfully updated.",
        budget: budget_json,
      }, status: 200)
    end

    get "/enterprises/:enterprise_id/settings/billing/budgets", operation_id: "billing/get-all-budgets", read_from_replicas: true do
      enterprise = find_enterprise!
      user = current_user
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      customer_id = enterprise.customer_id.to_s
      # user param for user level budgets - returns consumed_amount for user
      applicable_user_id = if params[:user].present?
        User.where(login: params[:user]).pick(:id)&.to_s
      end
      budget_target = params[:budgetTarget]&.downcase

      if enterprise.feature_flag_enabled?(:billing_budget_pagination_enabled, default: false)
        max_page_size = 10
        if enterprise.feature_flag_enabled?(:billing_budget_pagination_larger_page_size, default: false)
          max_page_size = 50
        end
        if enterprise.feature_flag_enabled?(:billing_budget_pagination_100_page_size, default: false)
          max_page_size = 100
        end

        page = params[:page]&.to_i
        page_size = [params[:per_page]&.to_i || 10, max_page_size].min
        scope = params[:scope]
        exclude_scope = params[:exclude_scope]
        response = Billing::Platform::Api::Client.new.get_all_budgets(
          customer_id: customer_id,
          page: page,
          page_size: page_size,
          scope: scope,
          exclude_scope: exclude_scope,
          budget_target: budget_target,
          user_id: applicable_user_id,
          use_remote_cache: true,
          feature_flag_target: enterprise
        )
      else
        response = Billing::Platform::Api::Client.new.get_all_budgets(
          customer_id: customer_id,
          user_id: applicable_user_id,
          budget_target: budget_target,
          use_remote_cache: true,
          feature_flag_target: enterprise
        )
      end

      if response.is_a?(Billing::Platform::Api::Error)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/get-all-budgets"])
        deliver_error! 500, message: "Unable to get budgets."
      end

      budgets = response[:budgets] || []

      filtered_budgets = filter_budget_by_role(budgets: budgets, current_user: user, entity: enterprise)

      # Convert budgets to user-friendly format, filtering out any that fail conversion
      budget_list = filtered_budgets.filter_map do |budget|
        begin
          result = user_friendly_budget_schema(budget, entity: enterprise, params: params, method: :get_all)
          result
        rescue StandardError
          nil
        end
      end

      GitHub.logger.info("billing.budgets.get_all",
        "gh.user.id": user.id,
        "gh.business.id": enterprise.id,
        "gh.billing.customer.id": customer_id,
        "gh.billing.budget_count": budget_list.length,
        "gh.billing.budget_api_enabled": true,
      )

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-all-budgets"])

      response_data = { budgets: budget_list }

      if enterprise.feature_flag_enabled?(:billing_user_level_budgets, default: false)
        if params[:user]
          response_data[:user] = params[:user]

          if response.key?(:effective_budget)
            effective_budget_data = transform_budget_response(response[:effective_budget])
            if effective_budget_data.present?
              response_data[:effective_budget] = {
                id: effective_budget_data.uuid,
                budget_amount: effective_budget_data.target_amount.to_i,
                consumed_amount: effective_budget_data.current_amount
              }
            end
          end
        end
      end

      if enterprise.feature_flag_enabled?(:billing_budget_pagination_enabled, default: false)
        if response.is_a?(Hash)
          response_data[:has_next_page] = response[:has_next_page] if response.key?(:has_next_page)
          response_data[:total_count] = response[:total_count] if response.key?(:total_count)
        end
        deliver_raw(response_data, status: 200)
      else
        deliver_raw(response_data, status: 200)
      end
    end

    get "/organizations/:organization_id/settings/billing/budgets", operation_id: "billing/get-all-budgets-org", read_from_replicas: true do
      org = find_org!
      user = current_user
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      if org.customer.nil?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/get-all-budgets-org"])
        deliver_error! 400, message: "Unable to get budgets."
      end

      customer_id = org.customer.id.to_s
      # user param for user level budgets - returns consumed_amount for user
      applicable_user_id = if params[:user].present?
        User.where(login: params[:user]).pick(:id)&.to_s
      end
      # Check if pagination features are enabled
      if org.feature_flag_enabled?(:billing_budget_pagination_enabled, default: false)
        # Extract pagination parameters from query string
        page = params[:page]&.to_i
        page_size = [params[:per_page]&.to_i || 10, 10].min
        scope = params[:scope]
        exclude_scope = params[:exclude_scope]

        response = Billing::Platform::Api::Client.new.get_all_budgets(
          customer_id: customer_id,
          page: page,
          page_size: page_size,
          scope: scope,
          exclude_scope: exclude_scope,
          use_remote_cache: true,
          feature_flag_target: org,
          user_id: applicable_user_id
        )
      else
        response = Billing::Platform::Api::Client.new.get_all_budgets(
          customer_id: customer_id,
          user_id: applicable_user_id,
          use_remote_cache: true,
          feature_flag_target: org
        )
      end

      if response.is_a?(Billing::Platform::Api::Error)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/get-all-budgets-org"])
        deliver_error! 500, message: "Unable to get budgets."
      end

      budgets = response[:budgets] || []

      budget_list = budgets.filter_map do |budget|
        begin
          user_friendly_budget_schema(budget, entity: org, method: :get)
        rescue StandardError
          nil
        end
      end

      GitHub.logger.info("billing.budgets.get_all",
        "gh.user.id": user.id,
        "gh.organization.id": org.id,
        "gh.billing.customer_id": customer_id,
        "gh.billing.budget_count": budget_list.length,
        "gh.billing.budget_api_enabled": true,
      )

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-all-budgets-org"])
      response_data = { budgets: budget_list }

      if params[:user].present? && applicable_user_id.present?
        response_data[:user] = params[:user]

        if response.key?(:effective_budget)
          effective_budget_data = transform_budget_response(response[:effective_budget])
          if effective_budget_data.present?
            response_data[:effective_budget] = {
              id: effective_budget_data.uuid,
              budget_amount: effective_budget_data.target_amount.to_i,
              consumed_amount: effective_budget_data.current_amount
            }
          end
        end
      end

      if org.feature_flag_enabled?(:billing_budget_pagination_enabled, default: false)
        if response.is_a?(Hash)
          response_data[:has_next_page] = response[:has_next_page] if response.key?(:has_next_page)
          response_data[:total_count] = response[:total_count] if response.key?(:total_count)
        end

        deliver_raw(response_data, status: 200)
      else
        deliver_raw(response_data, status: 200)
      end
    end

    get "/organizations/:organization_id/settings/billing/budgets/:budget_id", operation_id: "billing/get-budget-org", read_from_replicas: true do
      org = find_org!
      user = current_user
      control_access :view_org_settings,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      unless org_admin_or_billing_manager?(entity: org, current_user: user)
        deliver_error! 403, message: "Insufficient permissions to view this budget."
      end

      if org.customer.nil?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/get-organization-budget"])
        deliver_error! 400, message: "Unable to get budget."
      end

      customer_id = org.customer.id.to_s

      page = params[:page]&.to_i || 1
      response = Billing::Platform::Api::Client.new.get_budget_by_uuid(customer_id: customer_id, uuid: params[:budget_id], page: page)

      if response.is_a?(Billing::Platform::Api::Error)
        if response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/update-budget"])
          deliver_error! 404, message: "Budget with ID #{params[:budget_id]} not found."
        else
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/update-budget"])
          deliver_error! 500, message: "Unable to retrieve budget."
        end
        return
      end
      budget = response[:budget] || {}

      budget_response = user_friendly_budget_schema(budget, entity: org, method: :patch)

      GitHub.logger.info("billing.budgets.get",
        "gh.user.id": user.id,
        "gh.organization.id": org.id,
        "gh.billing.customer.id": customer_id,
        "gh.billing.budget_api_enabled": true,
      )

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-budget-org"])
      deliver_raw(budget_response, status: 200)
    end

    post "/organizations/:organization_id/settings/billing/budgets", operation_id: "billing/create-organization-budget", read_from_replicas: true do
      org = find_org!
      user = current_user
      control_access :update_org,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      customer_id = org.customer&.id.to_s

      begin
        request_data = JSON.parse(request.body.read)
      rescue JSON::ParserError
        deliver_error! 400, message: "Invalid JSON in request body."
      end

      # Validate organization budget request
      validation_error = validate_organization_budget_request(request_data, org)
      if validation_error
        deliver_error! validation_error[:status], message: validation_error[:message]
      end

      # Validate budget_product_sku against valid products/SKUs
      validate_budget_product_sku!(request_data, org, "billing/create-organization-budget")

      # Validate budget_type is a known pricing type
      if request_data["budget_type"].present? && !VALID_BUDGET_TYPES.include?(request_data["budget_type"])
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-organization-budget"])
        deliver_error! 400, message: "Invalid budget_type '#{request_data["budget_type"]}'. Must be one of: #{VALID_BUDGET_TYPES.join(', ')}."
      end

      begin
        raw_budget_request_data = transform_budget_upsert_request_data(request_data, customer_id, nil, org, use_org_api: true)
      rescue InvalidBudgetParametersError => e
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-organization-budget"])
        deliver_error! 400, message: e.message
      rescue InvalidAlertRecipientsError => e
        deliver_error! 400, message: "Invalid alert recipients: #{e.missing_usernames.join(', ')} do not exist."
      end

      # For repository-scope budgets, we need to convert the repo name to repo ID
      if request_data["budget_scope"] == "repository"
        repo_name = request_data["budget_entity_name"]
        repo = find_repository_by_name(repo_name, org)

        ensure_repo_exists!(repo, repo_name)

        raw_budget_request_data[:targetType] = "Repo"
        raw_budget_request_data[:targetId] = repo.id.to_s
      end

      # Check for duplicate budgets before creating
      duplicate_error = check_duplicate_budget(
        customer_id,
        raw_budget_request_data[:targetType],
        raw_budget_request_data[:targetId],
        raw_budget_request_data[:pricingTargetId],
        raw_budget_request_data[:pricingTargetType]
      )
      if duplicate_error
        deliver_error! duplicate_error[:status], message: duplicate_error[:message]
      end

      begin
        create_budget_request = Billing::Platform::Api::UpsertBudgetRequest.new(
          raw_upsert_budget_request: raw_budget_request_data,
          current_user: user,
          customer_id: customer_id,
          this_entity: org
        )
      rescue Billing::Platform::Api::UpsertBudgetRequest::InvalidTargetError
        deliver_error! 400, message: "Invalid target specified."
      rescue Billing::Platform::Api::UpsertBudgetRequest::InvalidRequestError => e
        error_message = "Invalid request parameters."
        if e.message.present? && e.message != e.class.to_s
          error_message += " #{translate_budget_field_names(e.message, request_data)}"
        end
        deliver_error! 400, message: error_message
      rescue Billing::Platform::Api::UpsertBudgetRequest::InvalidAccessError
        deliver_error! 404, message: "Not found."
      rescue StandardError => e
        deliver_error! 500, message: "Unexpected error: #{e.message}"
      end

      response = Billing::Platform::Api::Client.new.create_or_update_budget(budget: create_budget_request.to_json, feature_flag_target: org)

      if response.is_a?(Billing::Platform::Api::Error)
        if response.product_not_found?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/create-organization-budget"])
          deliver_error! 404, message: product_not_found_message(org, response.original_error.msg)
        elsif response.sku_not_found?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/create-organization-budget"])
          deliver_error! 404, message: sku_not_found_message(org, response.original_error.msg)
        elsif response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/create-organization-budget"])
          deliver_error! 404, message: "The specified resource was not found."
        else
          Failbot.report(response, context: { operation: "billing/create-organization-budget", customer_id: customer_id, org_id: org.id })
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/create-organization-budget"])
          deliver_error! 500, message: "Unable to create budget. #{response.user_message}"
        end
      end

      GitHub.logger.info("billing.budget.create_org",
        "gh.user.id": user.id,
        "gh.organization.id": org.id,
        "gh.billing.customer_id": customer_id,
        "gh.billing.pricing_target_id": raw_budget_request_data[:pricingTargetId] || "",
        "gh.billing.budget_api_enabled": true,
      )

      # Instrument audit log for budget creation
      GitHub.instrument "billing.budget_create", {
        actor: user,
        customer_id: customer_id,
        org: org,
        target_amount: create_budget_request.target_amount,
        target_type: create_budget_request.target_type,
        target_id: create_budget_request.target_id,
        alert_enabled: create_budget_request.alert_enabled?,
        pricing_target_type: create_budget_request.pricing_target_type,
        pricing_target_id: create_budget_request.pricing_target_id,
        budget_limit_type: create_budget_request.budget_limit_type,
        exclude_cost_center_usage: create_budget_request.exclude_cost_center_usage,
        status: "success"
      }

      # Send budget changed notification
      reason_type = reason_type(create_budget_request)
      publish_budget_changed_notification(create_budget_request.pricing_target_id, create_budget_request.pricing_target_type, org, customer_id, reason_type, target_type: create_budget_request.target_type, target_id: create_budget_request.target_id)

      budget_json = user_friendly_budget_schema(response, entity: org, method: :post)
      deliver_raw({ message: "Budget successfully created.", budget: budget_json }, status: 200)
    end

    patch "/organizations/:organization_id/settings/billing/budgets/:budget_id", operation_id: "billing/update-budget-org", read_from_replicas: true do
      org = find_org!
      user = current_user
      control_access :update_org,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      customer_id = org.customer&.id.to_s

      begin
        request_data = JSON.parse(request.body.read)
      rescue JSON::ParserError
        deliver_error! 400, message: "Invalid JSON in request body."
      end

      validate_budget_update_restricted_fields(request_data, "billing/update-budget")

      # exclude_cost_center_usage is only valid for enterprise-scoped budgets
      if request_data.key?("exclude_cost_center_usage")
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/update-budget"])
        deliver_error! 400, message: "exclude_cost_center_usage can only be used with enterprise-scoped budgets."
      end

      existing_budget_response = Billing::Platform::Api::Client.new.get_budget_by_uuid(customer_id: customer_id, uuid: params[:budget_id])
      if existing_budget_response.is_a?(Billing::Platform::Api::Error)
        if existing_budget_response.http_404?
          deliver_error! 404, message: "Budget with ID #{params[:budget_id]} not found."
        else
          deliver_error! 500, message: "Unable to retrieve budget."
        end
        return
      end

      # Validate organization budget request if scope or entity is being changed
      if request_data["budget_scope"].present? || request_data["budget_entity_name"].present?
        validation_error = validate_organization_budget_request(request_data, org)
        if validation_error
          deliver_error! validation_error[:status], message: validation_error[:message]
        end
      end

      # Validate budget_type is a known pricing type
      if request_data["budget_type"].present? && !VALID_BUDGET_TYPES.include?(request_data["budget_type"])
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/update-budget-org"])
        deliver_error! 400, message: "Invalid budget_type '#{request_data["budget_type"]}'. Must be one of: #{VALID_BUDGET_TYPES.join(', ')}."
      end

      validate_budget_product_sku!(request_data, org, "billing/update-budget-org")

      begin
        raw_budget_request_data = transform_budget_upsert_request_data(request_data, customer_id, existing_budget_response, org, use_org_api: true)
      rescue InvalidBudgetParametersError => e
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/update-budget-org"])
        deliver_error! 400, message: e.message
      rescue InvalidAlertRecipientsError => e
        deliver_error! 400, message: "Invalid alert recipients: #{e.missing_usernames.join(', ')} do not exist."
      end

      begin
        update_budget_request = Billing::Platform::Api::UpsertBudgetRequest.new(
          raw_upsert_budget_request: raw_budget_request_data,
          current_user: user,
          customer_id: customer_id,
          this_entity: org
        )
      rescue Billing::Platform::Api::UpsertBudgetRequest::InvalidTargetError
        deliver_error! 400, message: "Invalid target specified."
      rescue Billing::Platform::Api::UpsertBudgetRequest::InvalidRequestError => e
        error_message = "Invalid request parameters."
        if e.message.present? && e.message != e.class.to_s
          error_message += " #{translate_budget_field_names(e.message, request_data)}"
        end
        deliver_error! 400, message: error_message
      rescue Billing::Platform::Api::UpsertBudgetRequest::InvalidAccessError
        deliver_error! 404, message: "Not found."
      rescue StandardError => e
        Failbot.report(e, context: { operation: "billing/update-budget-org", org_id: org.id, user_id: user.id })
        deliver_error! 500, message: "Unable to update budget."
      end

      response = Billing::Platform::Api::Client.new.create_or_update_budget(budget: update_budget_request.to_json, feature_flag_target: org)

      if response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(response, context: { operation: "billing/update-budget-org", customer_id: customer_id, org_id: org.id })
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/update-budget-org"])
        deliver_error! 500, message: "Unable to update budget. #{response.user_message}"
      end

      # Log the update
      GitHub.logger.info("billing.budget.update",
        "gh.user.id": user.id,
        "gh.organization.id": org.id,
        "gh.billing.customer_id": customer_id,
        "gh.billing.budget_uuid": params[:budget_id],
        "gh.billing.pricing_target_id": update_budget_request.pricing_target_id,
        "gh.billing.pricing_target_type": update_budget_request.pricing_target_type,
        "gh.billing.target_amount": update_budget_request.target_amount,
        "gh.billing.budget_api_enabled": true,
      )

      # Instrument the update
      GitHub.instrument "billing.budget_update", {
        actor: user,
        customer_id: customer_id,
        org: org,
        budget_uuid: params[:budget_id],
        target_amount: update_budget_request.target_amount,
        target_type: update_budget_request.target_type,
        target_id: update_budget_request.target_id,
        alert_enabled: update_budget_request.alert_enabled?,
        pricing_target_type: update_budget_request.pricing_target_type,
        pricing_target_id: update_budget_request.pricing_target_id,
        budget_limit_type: update_budget_request.budget_limit_type,
        exclude_cost_center_usage: update_budget_request.exclude_cost_center_usage,
        status: "success"
      }

      # Send budget changed notification
      reason_type = reason_type(update_budget_request)
      publish_budget_changed_notification(update_budget_request.pricing_target_id, update_budget_request.pricing_target_type, org, customer_id, reason_type, target_type: update_budget_request.target_type, target_id: update_budget_request.target_id)

      GitHub.dogstats.increment("billing.budget_update", tags: ["pricing_target_id:#{update_budget_request.pricing_target_id}", "account_type:organization"])

      budget_json = user_friendly_budget_schema(response, entity: org, method: :patch)

      deliver_raw({
        message: "Budget successfully updated.",
        budget: budget_json,
      }, status: 200)
    end

    get "/enterprises/:enterprise_id/settings/billing/budgets/:budget_id", operation_id: "billing/get-budget", read_from_replicas: true do
      enterprise = find_enterprise!
      user = current_user
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      customer_id = enterprise.customer_id.to_s
      response = Billing::Platform::Api::Client.new.get_budget_by_uuid(customer_id: customer_id, uuid: params[:budget_id])

      if response.is_a?(Billing::Platform::Api::Error)
        if response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/get-budget"])
          deliver_error! 404, message: "Budget with ID #{params[:budget_id]} not found in enterprise #{enterprise.name}."
        else
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/get-budget"])
          deliver_error! 500, message: "Unable to get budget."
        end
        return
      end

      # Check user access to this budget
      check_budget_access(response, user, enterprise)

      # Convert Budget object to user-friendly schema format for API response
      budget_json = user_friendly_budget_schema(response, entity: enterprise, method: :get)

      GitHub.logger.info("billing.budget.get",
        "gh.user.id": user.id,
        "gh.business.id": enterprise.id,
        "gh.billing.customer.id": customer_id,
        "gh.billing.budget_uuid": params[:budget_id],
        "gh.billing.budget_api_enabled": true,
      )

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-budget"])
      deliver_raw(budget_json, status: 200)
    end

    delete "/enterprises/:enterprise_id/settings/billing/budgets/:budget_id", operation_id: "billing/delete-budget", read_from_replicas: true do
      enterprise = find_enterprise!
      user = current_user
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      customer_id = enterprise.customer_id.to_s

      # First, fetch the budget to check its target scope for access control
      budget_response = Billing::Platform::Api::Client.new.get_budget_by_uuid(customer_id: customer_id, uuid: params[:budget_id])

      if budget_response.is_a?(Billing::Platform::Api::Error)
        if budget_response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/delete-budget"])
          deliver_error! 404, message: "Budget with ID #{params[:budget_id]} not found in enterprise #{enterprise.name}."
        else
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/delete-budget"])
          deliver_error! 500, message: "Unable to fetch budget data."
        end
        return
      end

      budget = budget_response[:budget]
      if budget.nil?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/delete-budget"])
        deliver_error! 500, message: "Budget does not exist."
      end

      unless can_delete_budget?(user: user, budget: budget, enterprise: enterprise)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:billing/delete-budget"])
        deliver_error! 403, message: "Insufficient permissions to delete this budget."
      end

      response = Billing::Platform::Api::Client.new.delete_budget(customer_id: customer_id, uuid: params[:budget_id], feature_flag_target: enterprise)

      if response.is_a?(Billing::Platform::Api::Error)
        if response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/delete-budget"])
          deliver_error! 404, message: "Budget with ID #{params[:budget_id]} not found in enterprise #{enterprise.name}."
        else
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/delete-budget"])
          deliver_error! 500, message: "Unable to delete budget."
        end
        return
      end

      GitHub.logger.info("billing.budget.delete",
        "gh.user.id": user.id,
        "gh.business.id": enterprise.id,
        "gh.billing.customer.id": customer_id,
        "gh.billing.budget_uuid": params[:budget_id],
        "gh.billing.pricing_target_id": response[:pricingTargetId] || "",
        "gh.billing.budget_api_enabled": true,
      )

      # Instrument audit log for budget deletion
      GitHub.instrument "billing.budget_delete", {
        actor: user,
        customer_id: customer_id,
        business: enterprise,
        uuid: params[:budget_id],
        pricing_target_type: budget.pricing_target_type,
        pricing_target_id: budget.pricing_target_id,
        budget_limit_type: budget.budget_limit_type,
        target_type: budget.target_type,
        target_amount: budget.target_amount,
        alert_enabled: budget.alert_enabled?,
        exclude_cost_center_usage: budget.exclude_cost_center_usage?,
        status: "success"
      }

      # Send budget changed notification
      reason_type = Hydro::Schemas::Billingplatform::V1::Entities::ReasonType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::ReasonType::BUDGET_DELETED)
      publish_budget_changed_notification(budget.pricing_target_id, budget.pricing_target_type, enterprise, customer_id, reason_type, target_type: budget.target_type, target_id: budget.target_id)

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/delete-budget"])
      deliver_raw({
        message: "Budget successfully deleted.",
        id: params[:budget_id]
      }, status: 200)
    end

    delete "/organizations/:organization_id/settings/billing/budgets/:budget_id", operation_id: "billing/delete-budget-org", read_from_replicas: true do
      org = find_org!
      user = current_user
      control_access :update_org,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      # This endpoint cannot handle orgs that delegate billing to enterprise
      if org.delegate_billing_to_business?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/delete-budget-org"])
        deliver_error! 400, message: "Organization is managed by an enterprise. Please use the enterprise API instead."
      end

      customer_id = org.customer&.id&.to_s

      unless customer_id
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/delete-budget-org"])
        deliver_error! 400, message: "Organization does not have a valid customer ID."
      end

      # First, fetch the budget to check its target scope for access control
      budget_response = Billing::Platform::Api::Client.new.get_budget_by_uuid(customer_id: customer_id, uuid: params[:budget_id])

      if budget_response.is_a?(Billing::Platform::Api::Error)
        if budget_response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/delete-budget-org"])
          deliver_error! 404, message: "Budget with ID #{params[:budget_id]} not found for organization #{org.display_login}."
        else
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/delete-budget-org"])
          deliver_error! 500, message: "Unable to fetch budget data."
        end
        return
      end

      budget = budget_response[:budget]
      if budget.nil?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/delete-budget-org"])
        deliver_error! 404, message: "Budget does not exist."
      end

      # Store pricing_target_id from budget before deletion
      pricing_target_id = budget.pricing_target_id

      response = Billing::Platform::Api::Client.new.delete_budget(customer_id: customer_id, uuid: params[:budget_id], feature_flag_target: org)

      if response.is_a?(Billing::Platform::Api::Error)
        if response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/delete-budget-org"])
          deliver_error! 404, message: "Budget with ID #{params[:budget_id]} not found for organization #{org.display_login}."
        else
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/delete-budget-org"])
          deliver_error! 500, message: "Unable to delete budget."
        end
        return
      end

      GitHub.logger.info("billing.budget.delete",
        "gh.user.id": user.id,
        "gh.org.id": org.id,
        "gh.billing.customer_id": customer_id,
        "gh.billing.budget_uuid": params[:budget_id],
        "gh.billing.pricing_target_id": pricing_target_id || "",
        "gh.billing.budget_api_enabled": true,
      )

      # Instrument audit log for budget deletion
      GitHub.instrument "billing.budget_delete", {
        actor: user,
        customer_id: customer_id,
        org: org,
        uuid: params[:budget_id],
        pricing_target_type: budget.pricing_target_type,
        pricing_target_id: budget.pricing_target_id,
        budget_limit_type: budget.budget_limit_type,
        target_type: budget.target_type,
        target_amount: budget.target_amount,
        alert_enabled: budget.alert_enabled?,
        exclude_cost_center_usage: budget.exclude_cost_center_usage?,
        status: "success"
      }

      # Send budget changed notification
      reason_type = Hydro::Schemas::Billingplatform::V1::Entities::ReasonType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::ReasonType::BUDGET_DELETED)
      publish_budget_changed_notification(budget.pricing_target_id, budget.pricing_target_type, org, customer_id, reason_type, target_type: budget.target_type, target_id: budget.target_id)

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/delete-budget-org"])
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

      time_params = parse_time_period_params(params, default_current_year: false)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]
      validate_time_period(year, month, day, operation)

      query = {
        customer_id: enterprise.customer_id,
        year: year,
        month: month,
        day: day,
        billing_period: get_billing_period_from_params(params, default_current_year: false),
        org_id: organization&.id,
        user_id: user&.id,
        model: format_query_param(params[:model]),
        product: format_query_param(params[:product]),
        cost_center_id: format_query_param(params[:cost_center_id])
      }
      usage_response = Billing::Platform::Api::Client.new.get_copilot_usage_report(**query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        if usage_response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
          deliver_error! 404, message: usage_response.original_error.msg
        else
          Failbot.report(usage_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:#{operation}"])
          deliver_error! 503, message: "Unable to get billing usage data."
        end
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
      control_access :view_org_usage,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      if org.delegate_billing_to_business? && params[:user]
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:#{operation}"])
        deliver_error! 403, message: "Organization admins for enterprise owned organizations cannot filter usage by user"
      end

      user = validate_and_query_param("user", operation: operation)

      time_params = parse_time_period_params(params, default_current_year: false)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]
      validate_time_period(year, month, day, operation)

      customer_id = org.delegate_billing_to_business? ? org.business&.customer_id : org.customer&.id

      query = {
        customer_id: customer_id,
        year: year,
        month: month,
        day: day,
        # Specify the org ID if the organization delegates billing to a parent business so we can filter that customer's usage by this org
        org_id: org.delegate_billing_to_business? ? org.id : nil,
        billing_period: get_billing_period_from_params(params, default_current_year: false),
        user_id: user&.id,
        model: format_query_param(params[:model]),
        product: format_query_param(params[:product]),
      }
      usage_response = Billing::Platform::Api::Client.new.get_copilot_usage_report(**query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        if usage_response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
          deliver_error! 404, message: usage_response.original_error.msg
        else
          Failbot.report(usage_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:#{operation}"])
          deliver_error! 503, message: "Unable to get billing usage data."
        end
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

      time_params = parse_time_period_params(params, default_current_year: false)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]
      validate_time_period(year, month, day, operation)

      if user.customer.nil?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
        deliver_error! 400, message: "Unable to get billing usage data."
      end

      query = {
        customer_id: user.customer.id,
        year: year,
        month: month,
        day: day,
        billing_period: get_billing_period_from_params(params, default_current_year: false),
        model: format_query_param(params[:model]),
        product: format_query_param(params[:product]),
      }
      usage_response = Billing::Platform::Api::Client.new.get_copilot_usage_report(**query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        if usage_response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
          deliver_error! 404, message: usage_response.original_error.msg
        else
          Failbot.report(usage_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:#{operation}"])
          deliver_error! 503, message: "Unable to get billing usage data."
        end
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:#{operation}"])
        deliver :premium_request_usage_report_hash, {
          entity: user,
          reportItems: usage_response[:reportItems],
          query: query
        }
      end
    end

    ################################################
    # AI Credits Endpoints
    ################################################

    get "/enterprises/:enterprise_id/settings/billing/ai_credit/usage", operation_id: "billing/get-github-billing-ai-credit-usage-report-ghe", read_from_replicas: true do
      operation = "billing/get-github-billing-ai-credit-usage-report-ghe"
      enterprise = find_enterprise!
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      unless billing_tbb_enabled?(enterprise)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
        deliver_error! 404
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

      time_params = parse_time_period_params(params, default_current_year: false)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]
      validate_time_period(year, month, day, operation)

      query = {
        customer_id: enterprise.customer_id,
        year: year,
        month: month,
        day: day,
        billing_period: get_billing_period_from_params(params, default_current_year: false),
        org_id: organization&.id,
        user_id: user&.id,
        model: format_query_param(params[:model]),
        product: format_query_param(params[:product]),
        cost_center_id: format_query_param(params[:cost_center_id])
      }
      usage_response = Billing::Platform::Api::Client.new.get_ai_credit_usage_report(**query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        if usage_response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
          deliver_error! 404, message: usage_response.original_error.msg
        else
          Failbot.report(usage_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:#{operation}"])
          deliver_error! 503, message: "Unable to get billing usage data."
        end
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

    get "/organizations/:organization_id/settings/billing/ai_credit/usage", operation_id: "billing/get-github-billing-ai-credit-usage-report-org", read_from_replicas: true do
      operation = "billing/get-github-billing-ai-credit-usage-report-org"
      org = find_org!
      control_access :view_org_usage,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      unless billing_tbb_enabled?(org)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
        deliver_error! 404
      end

      if org.delegate_billing_to_business? && params[:user]
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:#{operation}"])
        deliver_error! 403, message: "Organization admins for enterprise owned organizations cannot filter usage by user"
      end

      user = validate_and_query_param("user", operation: operation)

      time_params = parse_time_period_params(params, default_current_year: false)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]
      validate_time_period(year, month, day, operation)

      customer_id = org.delegate_billing_to_business? ? org.business&.customer_id : org.customer&.id

      query = {
        customer_id: customer_id,
        year: year,
        month: month,
        day: day,
        # Specify the org ID if the organization delegates billing to a parent business so we can filter that customer's usage by this org
        org_id: org.delegate_billing_to_business? ? org.id : nil,
        billing_period: get_billing_period_from_params(params, default_current_year: false),
        user_id: user&.id,
        model: format_query_param(params[:model]),
        product: format_query_param(params[:product]),
      }
      usage_response = Billing::Platform::Api::Client.new.get_ai_credit_usage_report(**query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        if usage_response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
          deliver_error! 404, message: usage_response.original_error.msg
        else
          Failbot.report(usage_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:#{operation}"])
          deliver_error! 503, message: "Unable to get billing usage data."
        end
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

    get "/user/:user_id/settings/billing/ai_credit/usage", operation_id: "billing/get-github-billing-ai-credit-usage-report-user", read_from_replicas: true do
      operation = "billing/get-github-billing-ai-credit-usage-report-user"
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      unless Copilot::User.new(user).use_token_based_billing?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
        deliver_error! 404
      end

      time_params = parse_time_period_params(params, default_current_year: false)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]
      validate_time_period(year, month, day, operation)
      if user.customer.nil?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
        deliver_error! 400, message: "Unable to get billing usage data."
      end

      query = {
        customer_id: user.customer.id,
        year: year,
        month: month,
        day: day,
        billing_period: get_billing_period_from_params(params, default_current_year: false),
        model: format_query_param(params[:model]),
        product: format_query_param(params[:product]),
      }
      usage_response = Billing::Platform::Api::Client.new.get_ai_credit_usage_report(**query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        if usage_response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
          deliver_error! 404, message: usage_response.original_error.msg
        else
          Failbot.report(usage_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:#{operation}"])
          deliver_error! 503, message: "Unable to get billing usage data."
        end
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:#{operation}"])
        deliver :premium_request_usage_report_hash, {
          entity: user,
          reportItems: usage_response[:reportItems],
          query: query
        }
      end
    end

    ################################################
    # Usage Summary Endpoints
    ################################################

    get "/enterprises/:enterprise_id/settings/billing/usage/summary", operation_id: "billing/get-github-billing-usage-summary-report-ghe", read_from_replicas: true do
      operation = "billing/get-github-billing-usage-summary-report-ghe"
      enterprise = find_enterprise!
      control_access :view_business_billing,
        resource: enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      customer_id = enterprise.customer_id
      if customer_id.nil?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
        deliver_error! 400, message: "Unable to get billing usage data."
      end

      if params[:cost_center_id].present? && (params[:organization].present? || params[:repository].present?)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
        deliver_error! 400, message: "Cannot filter by cost center combined with organization or repository. Cost center filtering is mutually exclusive with organization and repository filters."
      end

      if params[:repository].present? && params[:organization].present?
        validate_owner_and_repository_match(repository_param: params[:repository], owner_param: params[:organization], operation: operation)
      end

      time_params = parse_time_period_params(params, default_current_year: false)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]
      validate_time_period(year, month, day, operation)

      if enterprise.is_copilot_standalone? && params[:organization].present?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
        deliver_error! 400, message: "Copilot Standalone enterprises cannot filter by organization."
      end

      if params[:cost_center_id].present?
        cost_center = validate_and_query_param("cost_center_id", entity: enterprise, operation: operation, usage_type: "usage summary")
      elsif params[:repository].present?
        organization, repository = validate_and_query_param("repository", entity: enterprise, operation: operation)
      elsif params[:organization].present?
        organization = validate_and_query_param("organization", entity: enterprise, operation: operation)
      end

      product = format_query_param(params[:product])
      sku = format_query_param(params[:sku])

      query = {
        customer_id: customer_id,
        year: year,
        month: month,
        day: day,
        billing_period: get_billing_period_from_params(params, default_current_year: false),
        org_id: organization&.id,
        repo_id: repository&.id,
        product: product,
        sku: sku,
        cost_center_id: format_query_param(params[:cost_center_id])
      }
      usage_response = Billing::Platform::Api::Client.new.get_usage_summary(**query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        if usage_response.product_not_found?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
          message = product_not_found_message(enterprise, usage_response.original_error.msg)
          deliver_error! 404, message: message
        elsif usage_response.sku_not_found?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
          message = sku_not_found_message(enterprise, usage_response.original_error.msg)
          deliver_error! 404, message: message
        else
          Failbot.report(usage_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:#{operation}"])
          deliver_error! 503, message: "Unable to get billing usage data."
        end
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:#{operation}"])
        deliver :usage_summary_report_hash, {
          entity: enterprise,
          usageItems: usage_response[:summaryItems],
          costCenter: cost_center,
          organization: organization,
          repository: repository,
          # return BP formatted friendly product name if product param was provided. If no results, use user-provided value
          product: product.present? ? usage_response[:summaryItems].first&.dig(:product) || params[:product] : nil,
          sku: sku,
          query: query
        }
      end
    end

    get "/organizations/:organization_id/settings/billing/usage/summary", operation_id: "billing/get-github-billing-usage-summary-report-org", read_from_replicas: true do
      operation = "billing/get-github-billing-usage-summary-report-org"
      org = find_org!
      control_access :view_org_usage,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      time_params = parse_time_period_params(params, default_current_year: false)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]
      validate_time_period(year, month, day, operation)

      is_org_delegating_billing = org.delegate_billing_to_business?
      entity = is_org_delegating_billing ? org.business : org
      customer_id = entity.customer&.id
      if customer_id.nil?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
        deliver_error! 400, message: "Unable to get billing usage data."
      end

      if params[:repository].present?
        validate_owner_and_repository_match(repository_param: params[:repository], operation: operation, owner_entity: org)
        _organization, repository = validate_and_query_param("repository", entity: org, operation: operation)
      end

      product = format_query_param(params[:product])
      sku = format_query_param(params[:sku])

      query = {
        customer_id: customer_id,
        year: year,
        month: month,
        day: day,
        billing_period: get_billing_period_from_params(params, default_current_year: false),
        # Specify the org ID if the organization delegates billing to a parent business so we can filter that customer's usage by this org
        org_id: is_org_delegating_billing ? org.id : nil,
        repo_id: repository&.id,
        product: product,
        sku: sku,
      }
      usage_response = Billing::Platform::Api::Client.new.get_usage_summary(**query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        if usage_response.product_not_found?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
          message = product_not_found_message(org, usage_response.original_error.msg)
          deliver_error! 404, message: message
        elsif usage_response.sku_not_found?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
          message = sku_not_found_message(org, usage_response.original_error.msg)
          deliver_error! 404, message: message
        else
          Failbot.report(usage_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:#{operation}"])
          deliver_error! 503, message: "Unable to get billing usage data."
        end
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:#{operation}"])
        deliver :usage_summary_report_hash, {
          entity: org,
          usageItems: usage_response[:summaryItems],
          organization: org,
          repository: repository,
          # return BP formatted friendly product name if product param was provided. If no results, use user-provided value
          product: product.present? ? usage_response[:summaryItems].first&.dig(:product) || params[:product] : nil,
          sku: sku,
          query: query,
        }
      end
    end

    get "/user/:user_id/settings/billing/usage/summary", operation_id: "billing/get-github-billing-usage-summary-report-user", read_from_replicas: true do
      operation = "billing/get-github-billing-usage-summary-report-user"
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      customer_id = user.customer&.id
      if customer_id.nil?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
        deliver_error! 400, message: "Unable to get billing usage data."
      end

      time_params = parse_time_period_params(params, default_current_year: false)
      year, month, day = time_params[:year], time_params[:month], time_params[:day]

      validate_time_period(year, month, day, operation)
      if params[:repository].present?
        validate_owner_and_repository_match(repository_param: params[:repository], operation: operation, owner_entity: user)
        _owner, repository = validate_and_query_param("repository", entity: user, operation: operation)
      end

      product = format_query_param(params[:product])
      sku = format_query_param(params[:sku])

      query = {
        customer_id: customer_id,
        year: year,
        month: month,
        day: day,
        billing_period: get_billing_period_from_params(params, default_current_year: false),
        repo_id: repository&.id,
        product: product,
        sku: sku,
      }
      usage_response = Billing::Platform::Api::Client.new.get_usage_summary(**query)

      if usage_response.is_a?(Billing::Platform::Api::Error)
        if usage_response.product_not_found?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
          message = product_not_found_message(user, usage_response.original_error.msg)
          deliver_error! 404, message: message
        elsif usage_response.sku_not_found?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
          message = sku_not_found_message(user, usage_response.original_error.msg)
          deliver_error! 404, message: message
        else
          Failbot.report(usage_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:#{operation}"])
          deliver_error! 503, message: "Unable to get billing usage data."
        end
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:#{operation}"])
        deliver :usage_summary_report_hash, {
          entity: user,
          usageItems: usage_response[:summaryItems],
          # return BP formatted friendly product name if product param was provided. If no results, use user-provided value
          product: product.present? ? usage_response[:summaryItems].first&.dig(:product) || params[:product] : nil,
          sku: sku,
          repository: repository,
          query: query
        }
      end
    end

    private

    def validate_org_owner_cost_center_access!(user, enterprise, cost_center_id, operation)
      # Skip validation in enterprise/GHES mode as cost centers are not supported
      return if GitHub.enterprise?

      role = enterprise_admin_role(user, enterprise)
      return unless role == "enterprise_org_owner"

      cost_center_response = Billing::Platform::Api::Client.new.get_cost_center(
        cost_center_key: {
          customerId: enterprise.customer_id.to_s,
          uuid: cost_center_id
        }
      )

      if cost_center_response.is_a?(Billing::Platform::Api::Error)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
        deliver_error! 404, message: "Cost center with Uuid: #{cost_center_id} for #{enterprise.name} not found."
      end

      cost_center = cost_center_response[:costCenter]
      unless cost_center && org_owner_has_cost_center_access?(user, enterprise, cost_center)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
        deliver_error! 404, message: "Cost center with Uuid: #{cost_center_id} for #{enterprise.name} not found."
      end
    end

    def filter_cost_centers_for_org_owner(user, enterprise, cost_centers)
      role = enterprise_admin_role(user, enterprise)
      return cost_centers if role == "owner" || role == "billing_manager"
      return [] unless role == "enterprise_org_owner"

      cost_centers.select { |cc| org_owner_has_cost_center_access?(user, enterprise, cc) }
    end

    def validate_not_org_owner_for_cost_center!(user, enterprise, operation)
      # Skip validation in enterprise/GHES mode as cost centers are not supported
      return if GitHub.enterprise?

      role = enterprise_admin_role(user, enterprise)
      return unless role == "enterprise_org_owner"

      # Org owners cannot create cost centers - this is an enterprise-level operation
      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:403", "operation:#{operation}"])
      deliver_error! 403, message: "Organization owners cannot create cost centers. This operation requires enterprise owner or billing manager permissions."
    end

    # Validates that restricted fields are not being updated in budget PATCH requests
    def validate_budget_update_restricted_fields(request_data, operation_name)
      restricted_fields = %w[budget_scope budget_entity_name budget_product_sku budget_type]
      provided_restricted_fields = restricted_fields.select { |field| request_data.key?(field) }

      if provided_restricted_fields.any?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation_name}"])
        deliver_error! 400, message: "The following fields cannot be updated: #{provided_restricted_fields.join(', ')}."
      end
    end

    # Translates internal schema field names in an error message to user-facing API field names
    def translate_budget_field_names(message, request_data = nil)
      field_names = API_FIELD_NAMES.dup

      # For user-scoped budgets, targetId comes from the request's `user` field.
      if request_data&.[]("budget_scope") == "user"
        field_names["targetId"] = "user"
      end

      field_names.each do |schema_key, api_name|
        message = message.gsub(schema_key, api_name)
      end
      message
    end

    # Validates that budget_product_sku is a valid product or SKU before sending to the billing platform.
    # Returns a helpful error with the list of valid options if invalid.
    # If the product/SKU list cannot be fetched (billing platform unavailable), validation is skipped.
    # Only validates when both budget_product_sku and budget_type are present.
    def validate_budget_product_sku!(request_data, entity, operation)
      budget_product_sku = request_data["budget_product_sku"]
      return if budget_product_sku.blank?

      budget_type = request_data["budget_type"]
      return if budget_type.blank?

      begin
        if budget_type == "BundlePricing"
          unless VALID_BUNDLE_PRICING_TARGET_IDS.include?(budget_product_sku)
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
            deliver_error! 404, message: "Bundle '#{budget_product_sku}' not found. Available bundles: #{VALID_BUNDLE_PRICING_TARGET_IDS.join(', ')}."
          end
        elsif budget_type == "SkuPricing"
          entity_enabled_products = products_helper.enabled_products(entity).map { |p| p[:name] }
          valid_skus = products_helper.enabled_skus_for_products(entity, entity_enabled_products).sort
          return if valid_skus.empty?
          tbb_enabled = billing_tbb_enabled?(entity)
          canonical_budget_product_sku = if tbb_enabled && HIDDEN_TBB_PREMIUM_REQUEST_SKUS.include?(budget_product_sku)
            nil
          elsif tbb_enabled
            map_tbb_sku_request(budget_product_sku)
          else
            budget_product_sku
          end

          display_skus = if tbb_enabled
            valid_skus.reject { |sku| HIDDEN_TBB_PREMIUM_REQUEST_SKUS.include?(sku) }.map { |sku| map_tbb_sku_response(sku) }.uniq.sort
          else
            valid_skus
          end

          unless valid_skus.include?(canonical_budget_product_sku)
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
            deliver_error! 404, message: "SKU '#{budget_product_sku}' not found. Available SKUs: #{display_skus.join(', ')}."
          end
        else
          valid_products = products_helper.enabled_products(entity).map { |p| p[:name] }.sort
          return if valid_products.empty?
          unless valid_products.include?(budget_product_sku)
            GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
            deliver_error! 404, message: "Product '#{budget_product_sku}' not found. Available products: #{valid_products.join(', ')}."
          end
        end
      rescue StandardError => e
        Failbot.report(e, context: { operation: operation, budget_product_sku: budget_product_sku })
        GitHub.dogstats.increment("billing_platform.api.validate_product_sku_error", tags: ["error:#{e.class.name}", "operation:#{operation}"])
        nil
      end
    end

    # Helper method to handle product not found errors with available products list
    def product_not_found_message(entity, error_message)
      original_msg = error_message.capitalize
      enabled_products = products_helper.enabled_products(entity).map { |p| p[:name] }.sort
      enabled_products.any? ? "#{original_msg}. Available products: #{enabled_products.join(', ')}" : original_msg
    end

    # Helper method to handle SKU not found errors with available SKUs list
    def sku_not_found_message(entity, error_message)
      entity_enabled_products = products_helper.enabled_products(entity).map { |p| p[:name] }
      enabled_skus = products_helper.enabled_skus_for_products(entity, entity_enabled_products).sort
      enabled_skus.any? ? "#{error_message}. Available SKUs: #{enabled_skus.join(', ')}" : error_message
    end

    def products_helper
      @products_helper ||= Class.new { include Billing::ProductsDependency }.new
    end

    # get time period params from the URL. All fields are optional and if year
    # is omitted we default to the current year. If other fields are omitted we use
    # the first day, first month as they will still be used to build time structs
    def parse_time_period_params(params, default_current_year: true)
      now = Time.now.utc
      default_month = default_current_year ? 1 : now.month

      {

        year: params[:year].nil? ? now.year : params[:year].to_i,
        month: params[:month].nil? ? default_month : params[:month].to_i,
        day: params[:day].nil? ? 1 : params[:day].to_i,
      }
    end

    def format_query_param(param)
      return param unless param.is_a?(String)

      param.strip.downcase
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
    def get_billing_period_from_params(params, default_current_year: true)
      # Only default to monthly when default_current_year is false and no time params are present
      if !default_current_year && params[:year].nil? && params[:month].nil? && params[:day].nil?
        return BillingPlatform::Base::BillingPeriod::Monthly
      end

      billing_period = BillingPlatform::Base::BillingPeriod::Yearly

      if !params[:year].nil? && params[:month].nil? && params[:day].nil?
        billing_period = BillingPlatform::Base::BillingPeriod::Yearly
      elsif !params[:month].nil? && params[:day].nil?
        billing_period = BillingPlatform::Base::BillingPeriod::Monthly
      elsif !params[:day].nil?
        billing_period = BillingPlatform::Base::BillingPeriod::Daily
      end

      billing_period
    end

    def enterprise_members(enterprise, user_logins)
      return [{}, {}] if user_logins.empty?

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

      enterprise.filtered_members(current_user, include_unaffiliated: true)
        .where(user_id: users.keys)
        .each do |member|
          members[users[member.user_id]] = member.user_id if users[member.user_id]
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

    def validate_no_hourly_param(params, operation:)
      if params[:hour].present?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
        deliver_error! 400, message: "Hourly time period filtering is deprecated"
      end
    end

    def validate_and_query_param(param_name, entity: nil, operation: nil, usage_type: "premium request usage")
      param_value = params[param_name.to_sym]
      return nil if param_value.nil?

      case param_name.to_s
      when "cost_center_id"
        validate_and_parse_cost_center(param_value, entity, operation, usage_type)
      when "organization"
        validate_and_parse_organization(param_value, entity, operation)
      when "user"
        validate_and_parse_user(param_value, operation)
      when "repository"
        validate_and_parse_repository(param_value, entity, operation)
      else
        raise ArgumentError, "Unknown parameter type: #{param_name}"
      end
    end

    def validate_and_parse_cost_center(cost_center_id, entity, operation, usage_type)
      formatted_id = format_query_param(cost_center_id)
      return nil if formatted_id == "none"

      cost_center_response = Billing::Platform::Api::Client.new.get_cost_center(cost_center_key: {
        customerId: entity.customer_id.to_s,
        uuid: cost_center_id
      })

      if cost_center_response.is_a?(Billing::Platform::Api::Error)
        Failbot.report(cost_center_response)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:#{operation}"])
        deliver_error! 503, message: "Unable to get cost center #{usage_type} data."
      end

      if cost_center_response[:costCenter].nil?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
        deliver_error! 404, message: "Cost center '#{cost_center_id}' not found."
      end

      cost_center_response[:costCenter]
    end

    def validate_and_parse_organization(organization_param, entity, operation)
      formatted_login = format_query_param(organization_param)
      if entity.is_a?(Business)
        organization = entity.organizations.find_by(login: formatted_login)
      else
        organization = Organization.find_by_login(formatted_login)
      end
      unless organization
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
        deliver_error! 404, message: "Organization '#{organization_param}' not found."
      end
      organization
    end

    def validate_and_parse_repository(repository_param, entity, operation)
      owner_login, repo_name = parse_repository_name(repository_param, operation)

      owner = entity.is_a?(Organization) || entity.is_a?(User) ? entity : entity.organizations.find_by(login: owner_login)
      unless owner
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
        deliver_error! 404, message: "Owner entity '#{owner_login}' not found."
      end

      repository = Repository.find_by(owner_id: owner.id, name: repo_name)
      unless repository
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
        deliver_error! 404, message: "Repository '#{repository_param}' not found."
      end

      [owner, repository]
    end

    def validate_owner_and_repository_match(repository_param:, operation:, owner_param: nil, owner_entity: nil)
      owner_login, _repo_name = parse_repository_name(repository_param, operation)
      owner_entity_login = if owner_entity && (owner_entity.is_a?(User) || owner_entity.is_a?(Organization))
        format_query_param(owner_entity.display_login)
      else
        owner_param ? format_query_param(owner_param) : ""
      end

      unless owner_login == owner_entity_login
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
        deliver_error! 400, message: "Repository owner '#{owner_login}' does not match entity owner '#{owner_entity_login}'. When filtering by both organization and repository, the organization must match the repository owner."
      end
    end

    def parse_repository_name(repository_param, operation)
      parts = repository_param.split("/")
      if parts.length != 2 || parts[0].blank? || parts[1].blank?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
        deliver_error! 400, message: "Repository must be specified in 'owner/repository_name' format."
      end

      parts.map { |part| format_query_param(part) }
    end

    def validate_and_parse_user(user_param, operation)
      user = User.find_by_login(format_query_param(user_param))
      unless user
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:#{operation}"])
        deliver_error! 404, message: "User '#{user_param}' not found."
      end
      user
    end

    def validate_time_period(year, month, day, operation, max_years_ago: 2)
      # will raise ArgumentError if the date is invalid
      validated_date = Date.new(year, month, day)

      requested_date = Time.zone.parse(validated_date.to_s).to_date
      max_allowed_date = Time.current.utc.to_date - max_years_ago.years

      if requested_date < max_allowed_date
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
        deliver_error! 400, message: "Time period cannot be more than #{max_years_ago} years in the past."
      end
    rescue ArgumentError
      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:#{operation}"])
      deliver_error! 400, message: "Invalid date specified."
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

  def filter_by_organization_access(user, organization_names, enterprise_organizations, is_enterprise_admin, soft_deleted_orgs: nil)
    organizations = []
    organization_id_to_name = {}
    active_orgs_map = enterprise_organizations
      .where(display_login: organization_names)
      .index_by { |org| org.display_login.downcase }
    soft_deleted_organizations = if soft_deleted_orgs
      soft_deleted_orgs
        .index_by { |org| org.display_login.downcase }
    else
      {}
    end

    organization_names = organization_names.map { |name| name.downcase }

    organization_names.each do |name|
      active_organization = active_orgs_map[name]
      soft_deleted_org = soft_deleted_organizations[name]

      if active_organization
        if is_enterprise_admin || active_organization.adminable_by?(user)
          organization_id_to_name[active_organization.id] = name
          organizations << {
            id: active_organization.id.to_s,
            type: BillingPlatform::Base::ResourceType::Org,
          }
        else
          deliver_error! 403, message: "User not an admin of organization: '#{name}'"
        end
      elsif soft_deleted_org
        if is_enterprise_admin || soft_deleted_org.adminable_by?(user)
          organization_id_to_name[soft_deleted_org.id] = name
          organizations << {
            id: soft_deleted_org.id.to_s,
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

  def filter_by_repository_access(user, repository_names, enterprise, is_enterprise_admin)
    return [], {} if repository_names.empty?

    repository_ids = []
    repository_id_to_name = {}

    enterprise_org_ids = enterprise.organizations.pluck(:id).to_set

    # Parse repository names into owner/repo pairs
    parsed_repos = repository_names.map do |full_name|
      parts = full_name.downcase.split("/", 2)
      if parts.length == 2
        { full_name: full_name, owner: parts[0], name: parts[1] }
      else
        deliver_error! 400, message: "Invalid repository format: '#{full_name}'.  Expected 'owner/repo'."
      end
    end

    owner_logins = parsed_repos.map { |r| r[:owner] }.uniq

    orgs_by_login = enterprise.organizations
      .where(display_login: owner_logins)
      .index_by { |org| org.display_login.downcase }

    # Build conditions to fetch only the specific repositories we need
    repo_conditions = parsed_repos.filter_map do |parsed|
      org = orgs_by_login[parsed[:owner]]
      next nil unless org
      { owner_id: org.id, name: parsed[:name] }
    end

    return [], {} if repo_conditions.empty?

    # Query only the specific repositories we need
    # Build a query like: (owner_id = X AND name = 'a') OR (owner_id = Y AND name = 'b')
    repos_query = repo_conditions.map do |cond|
      Repository.where(owner_id: cond[:owner_id]).where(name: cond[:name])
    end.reduce(:or)

    repositories_by_full_name = repos_query
      .active
      .preload(:owner)
      .index_by { |repo| "#{repo.owner_display_login}/#{repo.name}".downcase }

    parsed_repos.each do |parsed|
      full_name = parsed[:full_name].downcase
      repository = repositories_by_full_name[full_name]

      if repository.nil?
        # Check if the owner org exists but repo doesn't
        if orgs_by_login[parsed[:owner]]
          deliver_error! 404, message: "Repository not found: '#{parsed[:full_name]}'"
        else
          deliver_error! 403, message: "Repository not part of enterprise: '#{parsed[:full_name]}'"
        end
      end

      unless enterprise_org_ids.include?(repository.owner_id)
        deliver_error! 403, message: "Repository not part of enterprise: '#{parsed[:full_name]}'"
      end

      # Check access
      if is_enterprise_admin || repository.adminable_by?(user)
        repository_id_to_name[repository.id] = parsed[:full_name]
        repository_ids << {
          id: repository.id.to_s,
          type: BillingPlatform::Base::ResourceType::Repo,
        }
      else
        deliver_error! 403, message: "User not an admin of repository: '#{parsed[:full_name]}'"
      end
    end

    [repository_ids, repository_id_to_name]
  end

  # Transform budget data to user-friendly schema format
  def user_friendly_budget_schema(response, entity: nil, params: nil, method: nil)
    budget = transform_budget_response(response)
    # Determine the appropriate budget scope with context awareness
    budget_scope = if budget.target_type == "CustomerResource" && entity.is_a?(Organization)
      # CustomerResource budgets accessed via organization endpoints should be labeled as "organization"
      # to align with UI and API documentation for organization-level budget management
      "organization"
    else
      map_target_type_to_scope(budget.target_type)
    end

    # Determine the appropriate entity name with context awareness
    entity_name = if budget.target_type == "CustomerResource" && entity.is_a?(Organization)
      # For CustomerResource budgets accessed via organization endpoints, use the org's display_login
      # to align with the "organization" scope label
      entity.display_login
    else
      budget.target_name
    end

    tbb_enabled = !entity.is_a?(Repository) && billing_tbb_enabled?(entity)
    if tbb_enabled
      budget_product_sku = map_tbb_sku_response(budget.pricing_target_id)
    else
      budget_product_sku = budget.pricing_target_id
    end

    result = {
      id: budget.uuid,
      budget_type: budget.pricing_target_type,
      budget_product_sku: budget_product_sku,
      budget_scope: budget_scope,
      # todo later: make this not .to_i and update the schema.
      budget_amount: budget.target_amount.to_i,
      prevent_further_usage: budget.budget_limit_type == "PreventFurtherUsage",
      budget_entity_name: entity_name,
      budget_alerting: {
        will_alert: budget.alert_enabled?,
        alert_recipients: budget.alert_recipient_user_logins
      }
    }

    # Only include exclude_cost_center_usage for enterprise-scoped budgets
    if budget_scope == "enterprise"
      result[:exclude_cost_center_usage] = budget.exclude_cost_center_usage?
    end

    # Add consumed_amount for User and MultiUserCustomer budgets
    # Only added for MultiUserCustomer budgets when a user is passed via params
    if budget.target_type == "User" || (budget.target_type == "MultiUserCustomer" || budget.target_type == "MultiUserCostCenter") && params&.dig(:user)
      result[:consumed_amount] = budget.current_amount
    end

    # Add budget thresholds for MultiUserCustomer budgets
    if (budget.target_type == "MultiUserCustomer" || budget.target_type == "MultiUserCostCenter") && !params&.dig(:user) && method == :get
      result[:budget_thresholds] = budget.multi_user_budget_thresholds.transform_values do |threshold_data|
        user_ids = threshold_data["ids"] || []
        User.where(id: user_ids).pluck(:display_login)
      end
      result[:has_next_page] = budget.has_next_page?
    end

    # Add budget threshold summary for MultiUserCustomer budgets on get_all
    if ((budget.target_type == "MultiUserCustomer" || budget.target_type == "MultiUserCostCenter") && !params&.dig(:user)) && method == :get_all
      result[:budget_thresholds] = budget.multi_user_budget_threshold_summary
    end

    if budget.target_type == "User"
      username = User.find_by(id: budget.target_id)&.display_login
      result[:user] = username
    end

    result
  end

  def can_delete_budget?(user:, budget:, enterprise:)
    target_type = budget.target_type
    target_id = budget.target_id

    case target_type
    when "Org", "Organization" # Organization-level budget
      # Enterprise owners/billing managers can always delete
      return true if enterprise_admin_or_billing_manager?(user, enterprise)

      # Organization admins can delete budgets for their own organizations
      organization = enterprise.organizations.find_by(id: target_id)
      return false unless organization
      organization.adminable_by?(user)

    when "Repo", "Repository" # Repository-level budget
      # Enterprise owners/billing managers can always delete
      return true if enterprise_admin_or_billing_manager?(user, enterprise)

      # Repository admins can delete budgets for their own repositories
      repository = Repository.find_by(id: target_id)
      return false unless repository
      return false unless enterprise.organizations.include?(repository.owner)
      repository.adminable_by?(user)

    when "CostCenterResource" # Cost center budget
      # Only enterprise owners/billing managers can delete cost center budgets
      enterprise_admin_or_billing_manager?(user, enterprise)

    else # Enterprise-level or unknown budget type
      # Only enterprise owners/billing managers can delete enterprise-level budgets
      enterprise_admin_or_billing_manager?(user, enterprise)
    end
  end

  def enterprise_admin_or_billing_manager?(user, enterprise)
    enterprise.owner?(user) || enterprise.billing_manager?(user)
  end

  # Check if user has access to the budget based on role filtering
  def check_budget_access(response, user, enterprise)
    # Extract target_type and target_id from response (handle different response formats)
    target_type, target_id = extract_budget_target_info(response)

    # Convert the budget response to the format expected by filter_budget_by_role
    budget_for_filtering = {
      budget: {
        key: {
          targetType: target_type,
          targetId: target_id
        }
      }
    }

    filtered_budgets = filter_budget_by_role(budgets: [budget_for_filtering], current_user: user, entity: enterprise)

    if filtered_budgets.empty?
      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/get-budget"])
      deliver_error! 404, message: "Budget not found or you do not have permission to access this budget."
    end
  rescue StandardError
    GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:500", "operation:billing/get-budget"])
    deliver_error! 500, message: "Internal server error during budget access check."
  end

  # Extract target type and ID from different budget response formats
  def extract_budget_target_info(response)
    if response.respond_to?(:target_type) && response.respond_to?(:target_id)
      # Budget object case
      [response.target_type, response.target_id]
    elsif response.is_a?(Hash) && response[:budget].is_a?(Billing::Platform::Api::Budget)
      # Hash with budget object case
      [response[:budget].target_type, response[:budget].target_id]
    elsif response.is_a?(Hash) && response["budget"]
      # Raw hash case
      [response["budget"]["key"]["targetType"], response["budget"]["key"]["targetId"]]
    else
      raise "Unable to extract budget target information from response"
    end
  end

  def map_target_type_to_scope(target_type)
    case target_type.to_s
    when "CustomerResource"
      "enterprise"
    when "Organization", "Org"
      "organization"
    when "Repository", "Repo"
      "repository"
    when "CostCenterResource"
      "cost_center"
    when "MultiUserCustomer"
      "multi_user_customer"
    when "MultiUserCostCenter"
      "multi_user_cost_center"
    else
      target_type.to_s.downcase
    end
  end

  def map_tbb_sku_request(sku)
    case sku
    when "ai_credits"
      "premium_requests"
    when "spark_ai_credit"
      "spark_ai_unit"
    when "coding_agent_ai_credit"
      "coding_agent_ai_unit"
    when "copilot_ai_credit"
      "copilot_ai_unit"
    when "code_quality_ai_credit"
      "code_quality_ai_unit"
    else
      sku
    end
  end

  def map_tbb_sku_response(sku)
    case sku
    when "premium_requests"
      "ai_credits"
    when "spark_ai_unit"
      "spark_ai_credit"
    when "coding_agent_ai_unit"
      "coding_agent_ai_credit"
    when "copilot_ai_unit"
      "copilot_ai_credit"
    when "code_quality_ai_unit"
      "code_quality_ai_credit"
    else
      sku
    end
  end

  # Validate organization budget request parameters
  # Returns error hash with status and message if validation fails, nil otherwise
  def validate_organization_budget_request(request_data, org)
    budget_scope = request_data["budget_scope"]
    budget_entity_name = request_data["budget_entity_name"]
    valid_scopes = ORGANIZATION_BUDGET_SCOPES

    if USER_LEVEL_BUDGET_SCOPES.include?(budget_scope)
      valid_scopes += USER_LEVEL_BUDGET_SCOPES
    end

    # If budget_scope is provided, validate it
    if budget_scope.present?
      # Validate budget_scope - only repository and organization allowed for org endpoints
      # user and multi_user_customer also allowed
      unless valid_scopes.include?(budget_scope)
        validation_error = { status: 400, message: "Invalid budget_scope '#{budget_scope}'. Must be one of: #{valid_scopes.join(", ")}." }
        GitHub.logger.info("billing.budget.validation_failed",
          organization_id: org.id,
          validation_error: validation_error[:message],
          budget_scope: budget_scope
        )
        return validation_error
      end

      # For repository scope, budget_entity_name is required
      if budget_scope == "repository"
        if budget_entity_name.blank?
          validation_error = { status: 400, message: "budget_entity_name is required for repository scope budgets." }
          GitHub.logger.info("billing.budget.validation_failed",
            organization_id: org.id,
            validation_error: validation_error[:message],
            budget_scope: budget_scope
          )
          return validation_error
        end

        # Validate repository format (must be owner/repo or just repo name for org endpoints)
        unless budget_entity_name.match?(/\A[^\/]+\z/) || budget_entity_name.match?(/\A[^\/]+\/[^\/]+\z/)
          validation_error = { status: 400, message: "Invalid budget_entity_name format. Repository budgets must use 'owner/repo' format or just 'repo' for organization endpoints." }
          GitHub.logger.info("billing.budget.validation_failed",
            organization_id: org.id,
            validation_error: validation_error[:message],
            budget_entity_name: budget_entity_name
          )
          return validation_error
        end

        # Find the repository
        repo = find_repository_by_name(budget_entity_name, org)

        if repo.nil?
          validation_error = { status: 404, message: "Repository '#{budget_entity_name}' not found." }
          GitHub.logger.info("billing.budget.validation_failed",
            organization_id: org.id,
            validation_error: validation_error[:message],
            budget_entity_name: budget_entity_name
          )
          return validation_error
        end

        # Validate repository belongs to the organization
        if repo.owner_id != org.id || repo.owner_type != "Organization"
          validation_error = { status: 403, message: "Repository '#{budget_entity_name}' does not belong to organization '#{org.display_login}'." }
          GitHub.logger.info("billing.budget.validation_failed",
            organization_id: org.id,
            validation_error: validation_error[:message],
            budget_entity_name: budget_entity_name,
            repo_owner_id: repo.owner_id
          )
          return validation_error
        end
      end
    end

    # Validate exclude_cost_center_usage is not present in organization budget requests
    if request_data.key?("exclude_cost_center_usage")
      validation_error = { status: 400, message: "exclude_cost_center_usage is not supported for organization budget requests." }
      GitHub.logger.info("billing.budget.validation_failed",
        organization_id: org.id,
        validation_error: validation_error[:message]
      )
      return validation_error
    end

    nil
  end

  # Check for duplicate budgets by directly querying for the specific budget
  # Returns error hash with status and message if duplicate exists, nil otherwise
  def check_duplicate_budget(customer_id, target_type, target_id, pricing_target_id, pricing_target_type)
    # Construct the budget key for direct lookup
    budget_key = {
      customerId: customer_id.to_s,
      targetType: target_type.to_s,
      targetId: target_id.to_s,
      pricingTargetId: pricing_target_id.to_s,
      pricingTargetType: pricing_target_type.to_s
    }

    # Query for the specific budget directly instead of fetching all budgets
    response = Billing::Platform::Api::Client.new.get_budget(key: budget_key)

    if response.is_a?(Billing::Platform::Api::Error)
      # If it's a 404, the budget doesn't exist (no duplicate)
      return nil if response.http_404?

      # For other errors, log and fail safely to prevent duplicate creation when API is unavailable
      GitHub.logger.error("billing.budget.duplicate_check_failed",
        customer_id: customer_id,
        error_message: response.message,
        http_status: response.http_status
      )
      return { status: 503, message: "Unable to verify budget uniqueness. Please try again later." }
    end

    # If we got a successful response, the budget exists (it's a duplicate)
    if response.is_a?(Hash) && (response[:budget].present? || response["budget"].present?)
      return { status: 409, message: "A budget with the same scope and entity already exists." }
    end

    nil
  end

  def find_repository_by_name(repo_name, org = nil)
    if org && !repo_name.include?("/")
      org.find_repo_by_name(repo_name)
    elsif org && repo_name.include?("/")
      owner_name, repo_only_name = repo_name.split("/", 2)
      if owner_name.downcase == org.display_login.downcase
        org.find_repo_by_name(repo_only_name)
      else
        Repository.with_name_with_owner(repo_name)
      end
    else
      Repository.with_name_with_owner(repo_name)
    end
  end

  # Validate repository exists and deliver error if not
  def ensure_repo_exists!(repo, repo_name)
    unless repo
      deliver_error! 404, message: "Repository '#{repo_name}' not found."
    end
  end

  def map_scope_to_target_type(target_type, use_org_api: false)
    case target_type
    when "enterprise"
      "CustomerResource"
    when "organization"
      # When using organization API endpoints, treat organization budgets as CustomerResource
      # to align with backend expectations. Otherwise, use Org for proper scoping.
      use_org_api ? "CustomerResource" : "Org"
    when "repository"
      "Repo"
    when "cost_center"
      "CostCenterResource"
    when "multi_user_customer"
      "MultiUserCustomer"
    when "multi_user_cost_center"
      "MultiUserCostCenter"
    else
      target_type&.downcase
    end
  end

  def transform_budget_upsert_request_data(raw_input, customer_id, existing_budget = nil, entity = nil, use_org_api: false)
    default_data = transform_budget_response(existing_budget)
    budget_data = raw_input.with_indifferent_access
    # Extract target amount and pricing target id
    target_amount = budget_data.dig(:budget_amount) || (default_data&.target_amount)

    tbb_enabled = !entity.is_a?(Repository) && billing_tbb_enabled?(entity)
    if tbb_enabled
      pricing_target_id = map_tbb_sku_request(budget_data.dig(:budget_product_sku)) || (default_data&.pricing_target_id)
    else
      pricing_target_id = budget_data.dig(:budget_product_sku) || (default_data&.pricing_target_id)
    end

    # Determine the appropriate target_id and target_type based on entity
    if default_data.nil?
      if entity.is_a?(Organization)
        if use_org_api
          target_id = customer_id
          target_type = "CustomerResource"
        else
          target_id = entity.id.to_s
          target_type = "Org"
        end
        case budget_data[:budget_scope]
        when "multi_user_customer"
          target_type = "MultiUserCustomer"
        when "user"
          target_type = "User"
          target_id = resolve_budget_user_target_id(budget_data[:user])
        end
      elsif entity.is_a?(Repository)
        # For repository budgets, use repository ID and Repo target type
        target_id = entity.id.to_s
        target_type = "Repo"
      elsif entity.is_a?(Business)
        target_id = customer_id
        target_type = "CustomerResource"

        case budget_data[:budget_scope]
        when "cost_center"
          target_id = budget_data[:budget_entity_name]
          target_type = "CostCenterResource"
        when "multi_user_customer"
          target_type = "MultiUserCustomer"
        when "multi_user_cost_center"
          target_id = budget_data[:budget_entity_name]
          target_type = "MultiUserCostCenter"
        when "user"
          target_type = "User"
          target_id = resolve_budget_user_target_id(budget_data[:user])
        end
      end
    else
      target_type = default_data&.target_type
    end

    # Transform alert_recipients (usernames) to alertRecipientUserIds (global relay IDs)
    alert_recipient_ids = []
    if budget_data.dig(:budget_alerting, :alert_recipient_user_ids).present?
      # Already have user IDs (from update operations or test data)
      alert_recipient_ids = budget_data.dig(:budget_alerting, :alert_recipient_user_ids)
    elsif budget_data.dig(:budget_alerting)&.key?(:alert_recipients)
      # alert_recipients key is present (even if empty array) - convert usernames to global relay IDs
      usernames = budget_data.dig(:budget_alerting, :alert_recipients)

      if usernames.is_a?(Array) && usernames.any?
        users = User.where(login: usernames)

        # Validate that all usernames were found
        found_logins = users.map(&:display_login)
        missing_logins = usernames - found_logins

        if missing_logins.any?
          raise InvalidAlertRecipientsError, missing_logins
        end

        alert_recipient_ids = users.map(&:global_relay_id)
      else
        alert_recipient_ids = []
      end
    elsif default_data&.alert_recipient_global_user_ids.present?
      alert_recipient_ids = default_data.alert_recipient_global_user_ids
    end

    # For high watermark SKUs, convert budget_amount to license_count
    result = {
      targetType: target_type,
      targetId: target_id || default_data&.target_id,
      pricingTargetType: budget_data.dig(:budget_type) || (default_data&.pricing_target_type),
      pricingTargetId: pricing_target_id,
      budgetLimitType: budget_limit_type(budget_data, default_data),
      alertEnabled: alert_enabled?(budget_data, default_data),
      alertRecipientUserIds: alert_recipient_ids,
      uuid: default_data&.uuid || ""
    }

    # Validate that alert recipients are provided when alerting is enabled
    if result[:alertEnabled] && (alert_recipient_ids.nil? || alert_recipient_ids.empty?)
      raise InvalidBudgetParametersError, "Alert recipients are required when budget alerting is enabled"
    end

    if high_watermark_sku?(pricing_target_id) && target_amount.present?
      result[:licenseCount] = target_amount
    else
      result[:targetAmount] = target_amount
    end

    # Add exclude_cost_center_usage if present
    if budget_data.key?(:exclude_cost_center_usage)
      result[:excludeCostCenterUsage] = budget_data[:exclude_cost_center_usage]
    end

    result
  end

  # Resolve user login to user ID for budget target_id when budget_scope is "user"
  sig { params(user_login: T.nilable(String)).returns(T.nilable(String)) }
  def resolve_budget_user_target_id(user_login)
    return nil if user_login.blank?

    user = User.find_by(login: user_login)
    raise InvalidBudgetParametersError, "User '#{user_login}' not found" if user.nil?

    user.id.to_s
  end

  # Check if the given SKU is a high watermark SKU that requires license count conversion
  sig { params(sku: T.nilable(String)).returns(T::Boolean) }
  def high_watermark_sku?(sku)
    return false if sku.blank?
    HIGH_WATERMARK_SKUS.include?(sku.to_s)
  end

  def budget_limit_type(budget_data, default_data)
    prevent_usage = budget_data.dig(:prevent_further_usage)
    if prevent_usage == true
      "PreventFurtherUsage"
    elsif prevent_usage == false
      "AlertingOnly"
    else
      # If prevent_further_usage is not provided and we don't have default data (creating new budget),
      # we need to raise an error
      if default_data.nil?
        raise InvalidBudgetParametersError, "prevent_further_usage must be provided"
      end
      default_data.budget_limit_type
    end
  end

  def alert_enabled?(budget_data, default_data)
    if budget_data.dig(:budget_alerting, :will_alert) != nil
      budget_data.dig(:budget_alerting, :will_alert)
    else
      default_data&.alert_enabled? || false
    end
  end

  def transform_budget_response(response)
    if response.respond_to?(:as_json) && response.is_a?(Billing::Platform::Api::Budget)
      response
    elsif response.is_a?(Hash) && response[:budget].is_a?(Billing::Platform::Api::Budget)
      response[:budget]
    elsif response.is_a?(Hash) && response["budget"]
      Billing::Platform::Api::Budget.new(response["budget"])
    elsif response.is_a?(Hash)
      Billing::Platform::Api::Budget.new(response)
    else
      response
    end
  end

  def resolve_target_entity(request_data, enterprise, customer_id, user)
    if request_data["budget_scope"] == "organization"
      # Organization budgets require budget_entity_name (organization login name)
      if request_data["budget_entity_name"].blank?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
        deliver_error! 400, message: "budget_entity_name is required for organization budgets. Provide the organization login name."
      end

      # Find the organization within the enterprise
      organization_id = request_data["budget_entity_name"]
      org = enterprise.organizations.find_by(login: organization_id)

      if org.nil?
        GitHub.logger.info("billing.budget.org_not_found",
          "gh.user.id": user.id,
          "gh.business.id": enterprise.id,
          "gh.billing.organization_id_search": organization_id,
          "gh.billing.available_orgs": enterprise.organizations.pluck(:login, :id).to_json
        )
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
        deliver_error! 400, message: "Organization not found in enterprise or access denied."
      end

      org
    elsif request_data["budget_scope"] == "repository"
      # Repository budgets require budget_entity_name in "owner/repo" format
      if request_data["budget_entity_name"].blank?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
        deliver_error! 400, message: "budget_entity_name is required for repository budgets and must be in 'owner/repo' format."
      end

      repo_full_name = request_data["budget_entity_name"]

      unless repo_full_name.include?("/")
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
        deliver_error! 400, message: "Repository name must be in 'owner/repo' format."
      end

      owner_name, repo_name = repo_full_name.split("/", 2)

      # Find the repository owner (organization) within the enterprise
      owner_org = enterprise.organizations.find_by(login: owner_name)

      if owner_org.nil?
        GitHub.logger.info("billing.budget.repo_owner_not_found",
          "gh.user.id": user.id,
          "gh.business.id": enterprise.id,
          "gh.billing.repo_owner_search": owner_name,
          "gh.billing.repo_full_name": repo_full_name
        )
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
        deliver_error! 400, message: "Repository owner '#{owner_name}' not found in enterprise."
      end

      # Find the repository
      repo = Repository.where(owner_id: owner_org.id, name: repo_name).first

      if repo.nil?
        GitHub.logger.info("billing.budget.repo_not_found",
          "gh.user.id": user.id,
          "gh.business.id": enterprise.id,
          "gh.billing.repo_full_name": repo_full_name,
          "gh.billing.owner_org_id": owner_org.id
        )
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
        deliver_error! 400, message: "Repository '#{repo_full_name}' not found."
      end

      repo
    elsif request_data["budget_scope"] == "cost_center" || request_data["budget_scope"] == "multi_user_cost_center"
      # Cost center budgets require budget_entity_name (cost center UUID)
      if request_data["budget_entity_name"].blank?
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/create-budget"])
        deliver_error! 400, message: "budget_entity_name is required for cost_center budgets. Provide the cost center UUID."
      end

      cost_center_id = request_data["budget_entity_name"]

      # Validate the cost center exists and belongs to this enterprise
      cost_center_response = Billing::Platform::Api::Client.new.get_cost_center(
        cost_center_key: {
          customerId: customer_id,
          uuid: cost_center_id
        }
      )

      if cost_center_response.is_a?(Billing::Platform::Api::Error) || cost_center_response[:costCenter].nil?
        GitHub.logger.info("billing.budget.cost_center_not_found",
          "gh.user.id": user.id,
          "gh.business.id": enterprise.id,
          "gh.billing.cost_center_id": cost_center_id,
          "gh.billing.customer.id": customer_id
        )
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/create-budget"])
        deliver_error! 404, message: "The specified cost center or resource was not found."
      end

      enterprise
    else
      enterprise
    end
  end
end
