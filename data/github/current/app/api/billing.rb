# typed: true
# frozen_string_literal: true

class Api::Billing < Api::App
  MAX_NUMBER_OF_RESOURCES = 50.freeze
  include SecretScanning::Features::FeatureFlagHelper

  # Get Advanced Security billing information for organizations
  get "/organizations/:organization_id/settings/billing/advanced-security", operation_id: "billing/get-github-advanced-security-billing-org" do
    org = find_org!

    if org.business&.feature_enabled?(:saml_scope_private_resources_to_org)
      resource = Platform::InternalResource.new(resource: org)
    else
      resource = org
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
        deliver_raw(serialize_actions_usage(billable_owner: org.business, owner: org))
      else
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

      deliver_raw(serialize_actions_usage(billable_owner: enterprise))
    end

    def serialize_actions_usage(billable_owner:, owner: nil)
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

    # Get Packages billing information for users
    get "/user/:user_id/settings/billing/packages", operation_id: "billing/get-github-packages-billing-user" do
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

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
        deliver_raw(serialize_packages_usage(billable_owner: org.business, owner: org))
      else
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

      deliver_raw(serialize_packages_usage(billable_owner: enterprise))
    end

    def serialize_packages_usage(billable_owner:, owner: nil)
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

    # Get shared storage billing information for shared users
    get "/user/:user_id/settings/billing/shared-storage", operation_id: "billing/get-shared-storage-billing-user" do
      user = find_user!
      control_access :read_user_plan,
        resource: user,
        allow_integrations: false,
        allow_user_via_granular_actor: true

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
        deliver_raw(serialize_shared_storage_usage(billable_owner: org.business, owner: org))
      else
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

      deliver_raw(serialize_shared_storage_usage(billable_owner: enterprise))
    end

    def serialize_shared_storage_usage(billable_owner:, owner: nil)
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

      # get time period params from the URL. All fields are optional and if year
      # is omitted we default to the current year. If other fields are ommitted we use
      # the first day, first month or first hour as they will still be used to build time structs
      year = params[:year].nil? ? Time.now.utc.year : params[:year].to_i
      month = params[:month].nil? ? 1 : params[:month].to_i
      day = params[:day].nil? ? 1 : params[:day].to_i
      hour = params[:hour].nil? ? 0 : params[:hour].to_i

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

      # get time period params from the URL. All fields are optional and if year
      # is omitted we default to the current year. If other fields are ommitted we use
      # the first day, first month or first hour as they will still be used to build time structs
      year = params[:year].nil? ? Time.now.utc.year : params[:year].to_i
      month = params[:month].nil? ? 1 : params[:month].to_i
      day = params[:day].nil? ? 1 : params[:day].to_i
      hour = params[:hour].nil? ? 0 : params[:hour].to_i

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

      # get time period params from the URL. All fields are optional and if year
      # is omitted we default to the current year. If other fields are ommitted we use
      # the first day, first month or first hour as they will still be used to build time structs
      begin
        year = params[:year].nil? ? Time.now.utc.year : Integer(params[:year])
        month = params[:month].nil? ? 1 : Integer(params[:month])
        day = params[:day].nil? ? 1 : Integer(params[:day])
        hour = params[:hour].nil? ? 0 : Integer(params[:hour])
      rescue ArgumentError
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/get-github-billing-usage-report-org"])
        deliver_error! 400, message: "Invalid time period parameters."
      end

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

    post "/enterprises/:enterprise_id/settings/billing/cost-centers", operation_id: "billing/create-cost-center" do
      enterprise = find_enterprise!

      if !enterprise.feature_enabled?(:billing_cost_centers_api_updates)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/create-cost-center"])
        deliver_error! 404, message: "Cost center not found"
      end

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
      else
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-cost-center"])
        deliver :cost_center_hash, cost_center_response
      end
    end

    delete "/enterprises/:enterprise_id/settings/billing/cost-centers/:cost_center_id", operation_id: "billing/delete-cost-center" do
      enterprise = find_enterprise!

      if !enterprise.feature_enabled?(:billing_cost_centers_api_updates)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/delete-cost-center"])
        deliver_error! 404, message: "Cost center not found."
      end

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

      # Feature flag check
      unless enterprise.feature_enabled?(:billing_cost_centers_api_updates)
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/update-cost-center"])
        deliver_error! 404, message: "Cost center not found."
      end

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


      # Call the reusable `update_cost_center` method
      response = Billing::Platform::Api::Client.new.update_cost_center(
        key: {
          customer_id: enterprise.customer_id.to_s,
          uuid: params[:cost_center_id]
        },
        target_id: "NO_UPDATE",
        name: name,
        resources_to_add: [],
        resources_to_remove: [],
        update_resources_only: false
      )

      if response.is_a?(Billing::Platform::Api::Error)
        if response.already_exists?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:409", "operation:billing/update-cost-center"])
          deliver_error! 409, message: "A cost center with that name already exists"
        elsif response.http_404?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/update-cost-center"])
          deliver_error! 404, message: "Cost center not found."
        else
          Failbot.report(response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/update-cost-center"])
          deliver_error! 503, message: "Unable to update cost center."
        end
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

    post "/enterprises/:enterprise_id/settings/billing/cost-centers/:cost_center_id/resource", operation_id: "billing/add-resource-to-cost-center" do
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
      user_logins = data["users"] || []
      user_ids = []
      enterprise_members = enterprise_members(enterprise)

      organization_names = data["organizations"] || []
      organization_ids = []
      enterprise_organizations = enterprise.organizations

      repository_names = data["repositories"] || []
      repository_ids = []

      enterprise_repositories = if enterprise.feature_enabled?(:billing_cost_centers_api_optimization)
        repository_names.empty? ? {} : new_enterprise_repositories(enterprise)
      else
        enterprise_repositories(enterprise)
      end

      total_resource_count = user_logins.length + organization_names.length + repository_names.length
      if total_resource_count > MAX_NUMBER_OF_RESOURCES
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/add-resource-to-cost-center"])
        deliver_error! 400, message: "Too many resources. A max of #{MAX_NUMBER_OF_RESOURCES} resources are allowed to be added per request."
      end

      user_logins.each do |login|
        if member_id = enterprise_members[login]
          user_ids << {
            id: member_id.to_s,
            type: BillingPlatform::Base::ResourceType::User,
          }
        else
          deliver_error! 403, message: "User not part of enterprise: '#{login}'"
        end
      end

      is_enterprise_admin = enterprise.admins.include?(user)
      if enterprise.feature_enabled?(:billing_cost_centers_api_updates)
        organization_ids = filter_by_organization_access(user, organization_names, enterprise_organizations, is_enterprise_admin)
        repository_ids = filter_by_repository_access(user, repository_names, enterprise_repositories, is_enterprise_admin)
      end

      entity_ids = user_ids
      if enterprise.feature_enabled?(:billing_cost_centers_api_updates)
        entity_ids = user_ids + organization_ids + repository_ids
      end

      add_resource_cost_center_response = enterprise.add_resources_to_cost_center(params[:cost_center_id], entity_ids)

      if add_resource_cost_center_response.is_a?(Billing::Platform::Api::Error)
        if add_resource_cost_center_response.http_409?
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:409", "operation:billing/add-resource-to-cost-center"])
          deliver_error! 409, message: "A resource you're trying to add is already associated with a cost center."
        else
          Failbot.report(add_resource_cost_center_response)
          GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/add-resource-to-cost-center"])
          deliver_error! 503, message: "Unable to update billing cost center data."
        end
      end

      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/add-resource-to-cost-center"])
      if enterprise.feature_enabled?(:billing_cost_centers_api_updates)
        deliver_raw({ message: "Resources successfully added to the cost center." }, status: 200)
      else
        deliver_raw({ message: "Resources successfully added to the cost center. Resources already on a different cost center were not included." }, status: 200)
      end
    end

    delete "/enterprises/:enterprise_id/settings/billing/cost-centers/:cost_center_id/resource", operation_id: "billing/remove-resource-from-cost-center" do
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
      organization_ids = []
      enterprise_organizations = enterprise.organizations

      repository_names = data["repositories"] || []
      repository_ids = []

      optimization_enabled = enterprise.feature_enabled?(:billing_cost_centers_api_optimization)
      enterprise_repositories = if optimization_enabled
        repository_names.empty? ? {} : new_enterprise_repositories(enterprise)
      else
        enterprise_repositories(enterprise)
      end

      total_resource_count = user_logins.length + organization_names.length + repository_names.length
      if total_resource_count > MAX_NUMBER_OF_RESOURCES
        GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:400", "operation:billing/add-resource-to-cost-center"])
        deliver_error! 400, message: "Too many resources. A max of #{MAX_NUMBER_OF_RESOURCES} resources are allowed to be removed per request."
      end

      if optimization_enabled
        User.where(display_login: user_logins).select(:id, :business_id).each do |user|
          user_ids << {
            id: user.id.to_s,
            type: BillingPlatform::Base::ResourceType::User,
          }
        end
      else
        enterprise_members = enterprise_members(enterprise)

        non_enterprise_users = user_logins.reject { |login| enterprise_members.key?(login) }
        preloaded_users = User.where(display_login: non_enterprise_users).select(:id, :display_login, :business_id).index_by(&:display_login)

        user_logins.each do |login|
          if member_id = enterprise_members[login]
            user_ids << {
              id: member_id.to_s,
              type: BillingPlatform::Base::ResourceType::User,
            }
          else
            user = preloaded_users[login]
            if user
              user_ids << {
                id: user.id.to_s,
                type: BillingPlatform::Base::ResourceType::User,
              }
            end
          end
        end
      end

      is_enterprise_admin = enterprise.admins.include?(user)
      if enterprise.feature_enabled?(:billing_cost_centers_api_updates)
        organization_ids = filter_by_organization_access(user, organization_names, enterprise_organizations, is_enterprise_admin)
        repository_ids = filter_by_repository_access(user, repository_names, enterprise_repositories, is_enterprise_admin)
      end

      entity_ids = user_ids
      if enterprise.feature_enabled?(:billing_cost_centers_api_updates)
        entity_ids = user_ids + organization_ids + repository_ids
      end

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

    def enterprise_members(enterprise)
      members = Hash.new

      enterprise.admins
        .each do |user|
          members[user.display_login] = user.id
        end

      enterprise.filtered_members(current_user, ignore_org_membership_visibility: true)
        .includes(:user)
        .where.not(user_id: nil)
        .each do |member|
          members[member.user&.display_login] = member.user&.id
        end

      enterprise.filtered_outside_collaborators
        .each do |user|
          members[user.display_login] = user.id
        end

      enterprise.pending_admin_invitations
        .where.not(invitee_id: nil)
        .each do |invitation|
          members[invitation.invitee&.display_login] = invitation.invitee&.id
        end

      enterprise.pending_member_invitations
        .where.not(invitee_id: nil)
        .each do |invitation|
          members[invitation.invitee&.display_login] = invitation.invitee&.id
        end

      members.compact
    end

    def new_enterprise_repositories(enterprise)
      {}.tap do |repositories|
        org_ids = enterprise.organizations.pluck(:id)
        Repository.active.preload(:owner).batched_scope(:owner_id, values: org_ids) { |s| s.select(:id, :name, :owner_id, :owner_login) }.each do |repo|
          full_repo_name = "#{repo.owner_display_login}/#{repo.name}"
          repositories[full_repo_name] = repo.id
        end
      end
    end

    def enterprise_repositories(enterprise)
      repositories = Hash.new

      enterprise.organizations.each do |org|
        org.repositories.each do |repo|
          full_repo_name = "#{repo.owner_display_login}/#{repo.name}"
          repositories[full_repo_name] = repo.id
        end
      end

      repositories.compact
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
    organization_ids = []

    organization_names.each do |name|
      organization = enterprise_organizations.find_by(display_login: name)
      if organization
        if is_enterprise_admin || organization.adminable_by?(user)
          organization_ids << {
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

    organization_ids
  end

  def filter_by_repository_access(user, repository_names, available_repositories, is_enterprise_admin)
    return [] if repository_names.empty?

    repository_ids = []

    repository_ids_map = Repository.where(id: available_repositories.values_at(*repository_names)).index_by(&:id)
    repository_names.each do |name|
      repository = repository_ids_map[available_repositories[name]]
      if repository
        if is_enterprise_admin || repository.adminable_by?(user)
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

    repository_ids
  end
end
