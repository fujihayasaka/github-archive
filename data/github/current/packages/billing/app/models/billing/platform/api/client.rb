# typed: true
# frozen_string_literal: true

require "billing-platform/client"

module Billing
  module Platform
    module Api
      class Client

        BILLING_PLATFORM_SERVICE_NAME = "billing-platform".freeze

        attr_reader :timeout, :client

        def initialize(timeout: nil)
          @timeout = timeout
          @client = platform_client
        end

        ### Admin API
        def admin_process_dead_letter_queue(num:, queue_name: "")
          request_params = {
            num: num,
            queueName: queue_name,
          }
          handle_client_response(request_params: request_params) do
            client.admin_process_dead_letter_queue(**request_params)
          end
        end

        def admin_trigger_azure_emission(customer_id: "", year:, month:, day:)
          request_params = {
            customerId: customer_id,
            year: year,
            month: month,
            day: day,
          }
          handle_client_response(request_params: request_params) do
            client.admin_trigger_azure_emission(**request_params)
          end
        end

        def admin_trigger_invoice_generation(customer_id:, month:, year:)
          request_params = {
            customerId: customer_id.to_s,
            month: month,
            year: year,
          }
          handle_client_response(request_params: request_params) do
            client.admin_trigger_invoice_generation(**request_params)
          end
        end

        def admin_trigger_watermark_workflow(year:, month:, day:, hour:, customer_id: "", sku: "")
          request_params = {
            customerId: customer_id,
            sku: sku,
            year: year,
            month: month,
            day: day,
            hour: hour,
          }
          handle_client_response(request_params: request_params) do
            client.admin_trigger_watermark_workflow(**request_params)
          end
        end

        def admin_generate_usage(customer_id: "", sku: "", repo_id: 0, org_id: 0, amount: 0.0, quantity: 0.0)
          request_params = {
            customerId: customer_id,
            sku: sku,
            orgId: org_id,
            repoId: repo_id,
            amount: amount,
            quantity: quantity,
          }
          handle_client_response(request_params: request_params) do
            client.admin_generate_usage(**request_params)
          end
        end

        def admin_get_azure_emissions(customer_id:, year:, month:, day:, product:)
          request_params = {
            customerId: customer_id.to_s,
            year: year.to_i,
            month: month.to_i,
            day: day.to_i,
            product: product,
          }
          handle_client_response(request_params: request_params) do
            client.admin_get_azure_emissions(**request_params)
          end
        end

        ### Cost Center API

        def get_all_cost_centers(customer_id:, use_cache: false)
          request_params = {
            customerId: customer_id,
            useCache: use_cache,
          }
          handle_client_response(request_params: request_params) do
            client.get_all_cost_centers(**request_params)
          end
        end

        def get_cost_center(cost_center_key:)
          request_params = {
            costCenterKey: cost_center_key,
          }
          handle_client_response(request_params: request_params) do
            client.get_cost_center(**request_params)
          end
        end

        def find_cost_center_for(entity_detail:)
          request_params = {
            entityDetail: entity_detail,
          }
          handle_client_response(request_params: request_params) do
            client.find_cost_center_for(**request_params)
          end
        end

        def create_cost_center(customer_id:, target_id:, target_type:, name:, resources:, description: nil)
          request_params = {
            customerId: customer_id,
            targetId: target_id,
            targetType: target_type,
            name:,
            resources:,
          }

          request_params[:description] = description unless description.nil?

          handle_client_response(request_params: request_params) do
            client.create_cost_center(**request_params)
          end
        end

        def update_cost_center(key:, target_id:, name:, resources_to_add:, resources_to_remove:, update_resources_only: false, description: nil)
          request_params = {
            key: {
              customerId: key[:customer_id],
              uuid: key[:uuid],
            },
            targetId: target_id,
            name:,
            resourcesToAdd: resources_to_add,
            resourcesToRemove: resources_to_remove,
            updateResourcesOnly: update_resources_only,
          }

          request_params[:description] = description unless description.nil?

          handle_client_response(request_params: request_params) do
            client.update_cost_center(**request_params)
          end
        end

        # Call the new UpdateCostCenter API instead of the legacy AddResourceTo API
        def add_resource_to_cost_center(key:, resources:)
          update_cost_center(key: key, target_id: "", name: "", resources_to_add: resources, resources_to_remove: [], update_resources_only: true)
        end

        # Call the new UpdateCostCenter API instead of the legacy RemoveResourceFrom API
        def remove_resource_from_cost_center(key:, resources:)
          update_cost_center(key: key, target_id: "", name: "", resources_to_add: [], resources_to_remove: resources, update_resources_only: true)
        end

        def archive_cost_center(cost_center_key:)
          request_params = {
            costCenterKey: cost_center_key,
          }
          handle_client_response(request_params: request_params) do
            client.archive_cost_center(**request_params)
          end
        end

        # Pricing API

        def get_pricing(sku:)
          request_params = {
            sku: sku,
          }
          handle_client_response(request_params: request_params) do
            client.get_pricing(**request_params)
          end
        end

        def create_or_update_pricing(pricing:)
          request_params = {
            pricing: pricing,
          }
          handle_client_response(request_params: request_params) do
            client.create_or_update_pricing(**request_params)
          end
        end

        def get_all_pricing
          handle_client_response do
            client.get_all_pricing
          end
        end

        def get_pricings_by_product(product_name:)
          request_params = {
            productName: product_name,
          }

          handle_client_response(request_params: request_params) do
            client.get_pricings_by_product(**request_params)
          end
        end

        # Product API

        def get_all_products
          handle_client_response do
            client.get_all_products
          end
        end

        def get_product(product_sku)
          handle_client_response(request_params: { product_sku: product_sku }) do
            client.get_product(product_sku)
          end
        end

        def create_or_update_product(product)
          handle_client_response(request_params: { product: product }) do
            client.create_or_update_product(product)
          end
        end

        # Usage API

        def get_usage_total(usage_entity_id:, product: "", sku: "", billing_period: nil, year: nil, month: nil, day: nil, hour: nil)
          request_params = {
            usageEntityId: usage_entity_id.to_s,
            product: product,
            sku: sku,
            billingPeriod: billing_period,
            year: year,
            month: month,
            day: day,
            hour: hour
          }
          handle_client_response(request_params: request_params) do
            client.get_usage_total(**request_params)
          end
        end

        def get_enterprise_usage_totals(customer_id:, year: nil, month: nil, organization_admin_ids: nil)
          request_params = {
            customerId: customer_id.to_s,
            year: year,
            month: month,
            organizationAdminIds: organization_admin_ids
          }
          handle_client_response(request_params: request_params) do
            client.get_enterprise_usage_totals(**request_params)
          end
        end

        def get_watermark_level(usage_entity_id:, sku:, org_id:, repo_id:)
          request_params = {
            usageEntityId: usage_entity_id.to_s,
            sku: sku,
            orgId: org_id,
            repoId: repo_id,
          }
          handle_client_response(request_params: request_params) do
            client.get_watermark_level(**request_params)
          end
        end

        def get_usage_line_items(usage_entity_id:, product: "", sku: "", billing_period: nil, year: nil, month: nil, day: nil, hour: nil, org_id: nil, repo_id: nil, group_by: nil)
          request_params = {
            usageEntityId: usage_entity_id.to_s,
            product: product,
            sku: sku,
            billingPeriod: billing_period,
            year: year,
            month: month,
            day: day,
            hour: hour,
            orgId: org_id,
            repoId: repo_id,
            groupBy: group_by,
          }
          handle_client_response(request_params: request_params) do
            client.get_usage_line_items(**request_params)
          end
        end

        def get_net_usage_line_items(usage_entity_id:, product: "", sku: "", billing_period: nil, year: nil, month: nil, day: nil, hour: nil, org_id: nil, repo_id: nil, group_by: nil, cost_center_id: nil, organization_ids: nil)
          request_params = {
            usageEntityId: usage_entity_id.to_s,
            product: product,
            sku: sku,
            billingPeriod: billing_period,
            year: year,
            month: month,
            day: day,
            hour: hour,
            orgId: org_id,
            repoId: repo_id,
            groupBy: group_by,
            costCenterId: cost_center_id,
            organizationIds: organization_ids,
          }
          handle_client_response(request_params: request_params) do
            client.get_net_usage_line_items(**request_params)
          end
        end

        def get_top_org_repo_usage_line_items(usage_entity_id:, cost_center_id: nil, year: nil, month: nil, day: nil, hour: nil, billing_period: nil, group_by: nil, organization_ids: nil, include_discounts: false)
          request_params = {
            customerId: usage_entity_id.to_i,
            costCenterId: cost_center_id,
            year: year,
            month: month,
            day: day,
            hour: hour,
            billingPeriod: billing_period,
            groupBy: group_by,
            organizationIds: organization_ids,
            includeDiscounts: include_discounts,
          }
          handle_client_response(request_params: request_params) do
            client.get_top_org_repo_usage_line_items(**request_params)
          end
        end

        def get_usage_report(usage_entity_id:, billing_period: nil, year: nil, month: nil, day: nil, hour: nil, org_id: nil)
          request_params = {
            usageEntityId: usage_entity_id.to_s,
            billingPeriod: billing_period,
            year: year,
            month: month,
            day: day,
            hour: hour,
            orgId: org_id,
          }
          handle_client_response(request_params: request_params) do
            client.get_usage_report(**request_params)
          end
        end

        def queue_usage_report_export(customer_id:, start_date:, end_date:, actor_id:, organization_ids: nil, billable_owner_type: nil, billable_owner_id: nil, report_type: nil)
          request_params = {
            customerId: customer_id.to_s,
            startDate: start_date,
            endDate: end_date,
            actorId: actor_id,
            organizationIds: organization_ids,
            billableOwnerId: billable_owner_id,
            billableOwnerType: billable_owner_type,
            reportType: report_type,
          }
          handle_client_response(request_params: request_params) do
            client.queue_usage_report_export(**request_params)
          end
        end

        def get_discount_line_items(usage_entity_id:, product: "", sku: "", billing_period: nil, year: nil, month: nil, day: nil, hour: nil, org_id: nil, repo_id: nil, group_by: nil)
          request_params = {
            usageEntityId: usage_entity_id.to_s,
            product: product,
            sku: sku,
            billingPeriod: billing_period,
            year: year,
            month: month,
            day: day,
            hour: hour,
            orgId: org_id,
            repoId: repo_id,
            groupBy: group_by,
          }
          handle_client_response(request_params: request_params) do
            client.get_discount_line_items(**request_params)
          end
        end

        def get_invoice(customer_id:, year:, month:)
          request_params = {
            customerId: customer_id.to_s,
            year: year,
            month: month
          }
          handle_client_response(request_params: request_params) do
            client.get_invoice(**request_params)
          end
        end

        def get_usage_chart_data(usage_entity_id:, product:, sku:, year: nil, month: nil, day: nil, hour: nil, billing_period: nil, org_id: nil, repo_id: nil, group_by: nil, cost_center_id: nil, filtered_orgs: nil, filtered_repos: nil)
          request_params = {
            usageEntityId: usage_entity_id.to_s,
            product: product,
            sku: sku,
            year: year,
            month: month,
            day: day,
            hour: hour,
            billingPeriod: billing_period,
            orgId: org_id,
            repoId: repo_id,
            groupBy: group_by,
            costCenterId: cost_center_id,
            filteredOrgs: filtered_orgs,
            filteredRepos: filtered_repos
          }
          handle_client_response(request_params: request_params) do
            client.get_usage_chart_data(**request_params)
          end
        end

        # Copilot Usage API

        def get_copilot_usage_chart_data(customer_id:, year: nil, month: nil, billing_period: nil, org_id: nil, user_id: nil, model: nil, group_by: nil, cost_center_id: nil, organization_admin_ids: nil)
          request_params = {
            customerId: customer_id.to_s,
            year: year,
            month: month,
            billingPeriod: billing_period,
            orgId: org_id,
            userId: user_id,
            model: model,
            groupBy: group_by,
            costCenterId: cost_center_id,
            organizationAdminIds: organization_admin_ids,
          }
          handle_client_response(request_params: request_params) do
            client.get_copilot_usage_chart_data(**request_params)
          end
        end

        def get_copilot_usage_table(customer_id:, year: nil, month: nil, billing_period: nil, org_id: nil, user_id: nil, model: nil, group_by: nil, cost_center_id: nil, organization_admin_ids: nil, page: nil, rows_per_page: nil)
          request_params = {
            customerId: customer_id.to_s,
            year: year,
            month: month,
            billingPeriod: billing_period,
            orgId: org_id,
            userId: user_id,
            model: model,
            groupBy: group_by,
            costCenterId: cost_center_id,
            organizationAdminIds: organization_admin_ids,
            page: page,
            rowsPerPage: rows_per_page
          }
          handle_client_response(request_params: request_params) do
            client.get_copilot_usage_table(**request_params)
          end
        end

        def get_copilot_usage_card_data(customer_id:, year: nil, month: nil, billing_period: nil, org_id: nil, user_id: nil, model: nil, cost_center_id: nil, organization_admin_ids: nil)
          request_params = {
            customerId: customer_id.to_s,
            year: year,
            month: month,
            billingPeriod: billing_period,
            orgId: org_id,
            userId: user_id,
            model: model,
            costCenterId: cost_center_id,
            organizationAdminIds: organization_admin_ids,
          }
          handle_client_response(request_params: request_params) do
            client.get_copilot_usage_card_data(**request_params)
          end
        end

        def get_copilot_models
          handle_client_response do
            client.get_copilot_models
          end
        end

        def get_copilot_usage_report(customer_id:, year: nil, month: nil, day: nil, billing_period: nil, org_id: nil, user_id: nil, model: nil, product: nil, cost_center_id: nil)
          request_params = {
            customerId: customer_id.to_s,
            year: year,
            month: month,
            day: day,
            billingPeriod: billing_period,
            orgId: org_id,
            userId: user_id,
            model: model,
            product: product,
            costCenterId: cost_center_id,
          }
          handle_client_response(request_params: request_params) do
            client.get_copilot_usage_report(**request_params)
          end
        end

        # Invoices API

        def get_invoices(customer_id:)
          request_params = {
            customerId: customer_id.to_s,
          }
          handle_client_response(request_params: request_params) do
            client.get_invoices(**request_params)
          end
        end

        # ZuoraEmissions API

        def get_zuora_emissions(customer_id:, year:, month:, day:)
          request_params = {
            customerId: customer_id.to_s,
            year: year.to_i,
            month: month.to_i,
            day: day.to_i,
          }
          handle_client_response(request_params: request_params) do
            client.get_zuora_emissions(**request_params)
          end
        end

        # Customer API

        def create_or_update_customer(customer:)
          request_params = {
            customer: customer,
          }
          handle_client_response(request_params: request_params) do
            client.create_or_update_customer(**request_params)
          end
        end

        def create_or_patch_customer(customer:, previous_customer_id:, new_or_updated_overage_policy: nil)
          request_params = {
            customer: customer,
            previousCustomerId: previous_customer_id,
            newOrUpdatedOveragePolicy: new_or_updated_overage_policy,
          }
          handle_client_response(request_params: request_params) do
            client.create_or_patch_customer(**request_params)
          end
        end

        def get_customer(customer_id:)
          request_params = {
            customerId: customer_id.to_s,
          }
          handle_client_response(request_params: request_params) do
            client.get_customer(**request_params)
          end
        end

        def get_customers(customer_ids:)
          request_params = {
            customerIds: customer_ids,
          }
          handle_client_response(request_params: request_params) do
            client.get_customers(**request_params)
          end
        end

        def get_overage_policy(customer_id:, overage_policy_type:, name:, is_for_business:)
          request_params = {
            customerId: customer_id.to_s,
            overagePolicyType: overage_policy_type,
            name: name,
            isForBusiness: is_for_business,
          }
          handle_client_response(request_params: request_params) do
            client.get_overage_policy(**request_params)
          end
        end

        def create_or_update_budget(budget:)
          request_params = {
            budget: budget,
          }
          handle_client_response(request_params: request_params) do
            client.create_or_update_budget(**request_params)
          end
        end

        def get_budget(key:)
          request_params = {
            key: key,
          }
          handle_client_response(request_params: request_params) do
            client.get_budget(**request_params)
          end
        end

        def get_budget_by_uuid(customer_id:, uuid:)
          request_params = {
            customerId: customer_id.to_s,
            uuid: uuid,
          }

          response = handle_client_response(request_params: request_params) do
            client.get_budget_by_uuid(**request_params)
          end

          if response.is_a?(Hash)
            response[:budget] = Billing::Platform::Api::Budget.new(response)
          end
          response
        end

        def get_all_budgets(customer_id:)
          request_params = {
            customerId: customer_id.to_s,
          }

          response = handle_client_response(request_params: request_params) do
            client.get_all_budgets(**request_params)
          end

          # why are we doing this?
          if response.is_a?(Hash) && response[:budgets].is_a?(Array)
            response[:budgets] = response[:budgets].map { |item| Billing::Platform::Api::Budget.new(item) }
          end
          response
        end

        def get_budget_state(key:, year:, month:)
          request_params = {
            key: key,
            year: year,
            month: month,
          }

          handle_client_response(request_params: request_params) do
            client.get_budget_state(**request_params)
          end
        end

        def delete_budget(customer_id:, uuid:)
          request_params = {
            customerId: customer_id,
            uuid: uuid
          }

          handle_client_response(request_params: request_params) do
            client.delete_budget(**request_params)
          end
        end

        def can_proceed_with_usage(usage_key:, trust_tier: nil)
          request_params = {
            usageKey: usage_key,
            trustTier: trust_tier,
          }

          handle_client_response(request_params: request_params) do
            client.can_proceed_with_usage(**request_params)
          end
        end

        def create_discount(discount:)
          request_params = {
            discount: discount,
          }

          handle_client_response(request_params: request_params) do
            client.create_discount(**request_params)
          end
        end

        def delete_discount(customer_id:, discount_uuid:)
          request_params = {
            key: {
              customerId: customer_id,
              uuid: discount_uuid,
            }
          }
          handle_client_response(request_params: request_params) do
            client.delete_discount(**request_params)
          end
        end

        def get_discount(key:)
          request_params = {
            key: key,
          }

          handle_client_response(request_params: request_params) do
            client.get_discount(**request_params)
          end
        end

        def get_all_discounts(customer_id:)
          request_params = {
            customerId: customer_id.to_s,
          }

          handle_client_response(request_params: request_params) do
            client.get_all_discounts(**request_params)
          end
        end

        def get_discount_state(key:, year:, month:)
          request_params = {
            key: key,
            year: year,
            month: month,
          }

          handle_client_response(request_params: request_params) do
            client.get_discount_state(**request_params)
          end
        end

        def get_all_discount_states(customer_id:, year:, month:)
          request_params = {
            customerId: customer_id.to_s,
            year: year,
            month: month,
          }

          handle_client_response(request_params: request_params) do
            client.get_all_discount_states(**request_params)
          end
        end

        def get_all_included_usage_discount_states(customer_id:, year:, month:)
          request_params = {
            customerId: customer_id.to_s,
            year: year,
            month: month,
          }

          handle_client_response(request_params: request_params) do
            client.get_all_included_usage_discount_states(**request_params)
          end
        end

        def get_alertable_budget_state_info(customer_id:)
          request_params = {
            customerId: customer_id.to_s,
          }

          response = handle_client_response(request_params: request_params) do
            client.get_alertable_budget_state_info(**request_params)
          end

          if response.is_a?(Hash) && response[:budgets].is_a?(Array)
            response[:budgets] = response[:budgets].map { |item| Billing::Platform::Api::Budget.new(item) }
          end
          response
        end


        private

        def handle_client_response(request_params: {})
          # method that called "handle_client_response" is the billing API method
          # look back call stack 1 level above
          api = caller_locations(1, 1)&.first&.base_label

          # external method that called the client API method is the "api caller"
          # look back call stack 2 levels up
          api_caller = caller_locations(2, 1)&.first

          # if the 2 levels up is in current file (eg: "add_resource_to_cost_center" method which calls "update_cost_center" API)
          # the lets look further up the stack as the "api caller"
          api_caller = caller_locations(3, 1)&.first if api_caller&.absolute_path&.include?("billing/platform/api/client.rb")
          caller_method = api_caller&.base_label
          caller_path = "#{api_caller&.absolute_path}:#{api_caller&.lineno}"

          response = yield
          if response.error.nil?
            response.data.to_h
          else
            log_error_and_return(error: response.error, caller_method: caller_method, api: api, path: caller_path, request_params: request_params)
          end
        rescue => e # rubocop:todo Lint/RescueException
          log_error_and_return(error: e, caller_method: caller_method, api: api, path: caller_path, request_params: request_params)
        end

        # TODO: Errors should be raised and handled by the top level controller(s)
        def log_error_and_return(error:, caller_method:, api:, path:, request_params: {})
          GitHub.dogstats.increment("billing-platform.client.error", tags: ["api:#{api}", "caller:#{caller_method}", "method:#{caller_method}", "error:#{error.class.name.underscore.parameterize}"])
          client_error = Billing::Platform::Api::Error.new("Failed to request #{api}. Called from #{caller_method} in #{path}.\n\nError:\n #{error}.", original_error: error)
          GitHub::Logger.log_exception({ fn: "billing-platform.client.#{api}", original_error: error.to_s, client_caller: caller_method, path: path }.merge!(request_params), client_error)

          if client_error.http_5xx?
            Failbot.report(client_error, { "http.status_code" => client_error.http_status, "code.function" => caller_method, "code.caller.path" => path, "api_route" => api, "client_request_params" => request_params, "catalog_service" => "github/metered_billing_data" })
          end
          client_error
        end

        sig { returns(::BillingPlatform::Client) }
        def platform_client
          ::BillingPlatform::Client.new(host: GitHub.billing_platform_host, hmac_key: GitHub.billing_platform_hmac_secret_key) do |conn|
            conn.options.timeout = timeout if !timeout.nil?
            conn.request :retry, retry_options
            conn.use GitHub::FaradayMiddleware::RequestID
            conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: BILLING_PLATFORM_SERVICE_NAME, enable_path_tag: true
          end
        end

        def retry_options
          {
            max: 2,
            interval: 0.050,
            interval_randomness: 0.5,
            backoff_factor: 1.2,
            methods: [:post],
            exceptions: [Faraday::ConnectionFailed],
            retry_block: retry_proc,
          }
        end

        def retry_proc
          proc do |env, _, retries, exception|
            tags = [
              "status:#{env[:status]}",
              "retries:#{retries}",
              "rpc:#{env[:url].request_uri.sub('/twirp/', '')}",
              "error:#{exception.class}",
            ]
            GitHub.dogstats.increment("billing-platform.client.retry", tags: tags)
          end
        end
      end
    end
  end
end
