# typed: true
# frozen_string_literal: true

require "billing-platform/client"

module Billing
  module Platform
    module Api
      class Client
        BILLING_PLATFORM_SERVICE_NAME = "billing-platform".freeze

        # Maximum number of scope values allowed in scopes/exclude_scopes array params.
        # There are fewer than 10 distinct scope enum values in convert_scope_to_enum.
        MAX_SCOPE_ARRAY_SIZE = 10

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

        def admin_get_pooled_entitlement(customer_id:)
          request_params = {
            customerID: customer_id.to_i,
          }
          handle_client_response(request_params: request_params) do
            client.admin_get_pooled_entitlement(**request_params)
          end
        end

        def admin_refresh_pooled_entitlement(customer_id:, copilot_for_business_count: 0, copilot_enterprise_count: 0)
          request_params = {
            customerID: customer_id.to_i,
            copilotForBusinessCount: copilot_for_business_count.to_i,
            copilotEnterpriseCount: copilot_enterprise_count.to_i,
          }
          handle_client_response(request_params: request_params) do
            client.admin_refresh_pooled_entitlement(**request_params)
          end
        end

        def admin_reset_pooled_entitlement_current_amount(customer_id:, current_amount:)
          begin
            amount = current_amount.is_a?(Numeric) ? current_amount.to_f : Float(current_amount)
          rescue TypeError, ArgumentError
            raise ArgumentError, "Current amount must be a valid number"
          end

          raise ArgumentError, "Current amount must be a non-negative finite number" if !amount.finite? || amount.negative?

          request_params = {
            customerID: customer_id.to_i,
            currentAmount: amount,
          }
          handle_client_response(request_params: request_params) do
            client.admin_reset_pooled_entitlement_current_amount(**request_params)
          end
        end

        ### Cost Center API

        def get_all_cost_centers(customer_id:, use_cache: false, state: nil, page: nil, business: nil, filtered_repo_ids: nil, filtered_org_ids: nil, search_name: nil)
          is_org_admin = filtered_org_ids.present?
          use_count_cache = !is_org_admin && !search_name.present? && business.present? && FeatureFlag.vexi.enabled?(:billing_cost_centers_ui_pagination_enabled, business, default: false)
          disable_server_side_pagination_org_admin = is_org_admin && FeatureFlag.vexi.enabled?(:billing_cost_centers_ui_pagination_enabled, business, default: false) && FeatureFlag.vexi.enabled?(:billing_cost_centers_disable_org_admin_pagination, business, default: false)

          request_params = {
            customerId: customer_id,
            useCache: use_cache,
          }
          request_params[:state] = state unless state.nil?
          request_params[:page] = page unless page.nil?
          request_params[:filteredRepoIds] = filtered_repo_ids unless filtered_repo_ids.nil?
          request_params[:filteredOrgIds] = filtered_org_ids unless filtered_org_ids.nil?
          request_params[:searchName] = search_name unless search_name.nil?

          if use_count_cache && state.present?
            cache_client = Billing::Cache::CostCenterCountClient.new(business, customer_id, state.to_s)
            response = T.let(nil, T.untyped)
            total_count = nil

            # First try to get from cache
            total_count = cache_client.fetch(graceful_degradation: false) do
              # Cache miss - make API call with totalCount requested
              request_params[:totalCountCached] = false
              response = handle_client_response(request_params: request_params) do
                client.get_all_cost_centers(**request_params)
              end
              response[:totalCount] if response.is_a?(Hash)
            end

            if response.nil? # We had a cache hit
              # Need to get the non-count data
              request_params[:totalCountCached] = true
              response = handle_client_response(request_params: request_params) do
                client.get_all_cost_centers(**request_params)
              end
            end

            # Ensure response has the count (from cache in hit case, from API in miss case)
            response[:totalCount] = total_count if response.is_a?(Hash)
            response
          else
            # No caching - normal request without any cache consideration
            # In no-cache scenarios (including org-admin requests), totalCount (if present)
            # is returned directly by the backend based on the response data.
            if disable_server_side_pagination_org_admin
              request_params[:totalCountCached] = true # This will signal Billing Platform to not waste resources counting an org admin's viewable cost centers, as client-sided pagination relies on the client to filter cost centers and count them
            end
            handle_client_response(request_params: request_params) do
              client.get_all_cost_centers(**request_params)
            end
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

        def create_cost_center(customer_id:, target_id:, target_type:, name:, resources:, description: nil, business: nil)
          request_params = {
            customerId: customer_id,
            targetId: target_id,
            targetType: target_type,
            name:,
            resources:,
          }

          request_params[:description] = description unless description.nil?

          response = handle_client_response(request_params: request_params) do
            client.create_cost_center(**request_params)
          end

          # Invalidate count cache when creating a cost center (only active)
          if business.present? && FeatureFlag.vexi.enabled?(:billing_cost_centers_ui_pagination_enabled, business, default: false)
            Billing::Cache::CostCenterCountClient.new(business, customer_id, "CostCenterActive").invalidate("create")
          end

          response
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

        def archive_cost_center(cost_center_key:, business: nil)
          request_params = {
            costCenterKey: cost_center_key,
          }
          response = handle_client_response(request_params: request_params) do
            client.archive_cost_center(**request_params)
          end

          # Invalidate count cache when archiving a cost center
          if business.present? && FeatureFlag.vexi.enabled?(:billing_cost_centers_ui_pagination_enabled, business, default: false)
            customer_id = cost_center_key[:customerId]
            Billing::Cache::CostCenterCountClient.new(business, customer_id, "CostCenterActive").invalidate("archive")
            Billing::Cache::CostCenterCountClient.new(business, customer_id, "CostCenterArchived").invalidate("archive")
          end

          response
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

        def get_top_cost_center_line_items(usage_entity_id:, limit: 5, year: nil, month: nil, day: nil, hour: nil, billing_period: nil, include_discounts: false, organization_ids: nil)
          request_params = {
            customerId: usage_entity_id.to_i,
            limit: limit,
            year: year,
            month: month,
            day: day,
            hour: hour,
            billingPeriod: billing_period,
            includeDiscounts: include_discounts,
            organizationIds: organization_ids,
          }
          handle_client_response(request_params: request_params) do
            client.get_top_cost_center_line_items(**request_params)
          end
        end

        def get_usage_report(usage_entity_id:, billing_period: nil, year: nil, month: nil, day: nil, org_id: nil)
          request_params = {
            usageEntityId: usage_entity_id.to_s,
            billingPeriod: billing_period,
            year: year,
            month: month,
            day: day,
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

        # Request a new usage report export (async operation)
        # Returns an export_operation_uuid that can be used to poll for status
        def request_usage_report_export(customer_id:, start_date:, end_date:, actor_id:, organization_ids: nil, report_type: nil, send_email: false)
          request_params = {
            customerId: customer_id.to_s,
            startDate: start_date,
            endDate: end_date,
            actorId: actor_id,
            organizationIds: organization_ids,
            reportType: report_type,
            sendEmail: send_email,
          }
          handle_client_response(request_params: request_params) do
            client.request_usage_report_export(**request_params)
          end
        end

        # Get the status and details of a specific usage report export
        def get_usage_report_export(customer_id:, export_operation_uuid:)
          request_params = {
            customerId: customer_id.to_s,
            exportOperationUuid: export_operation_uuid,
          }
          handle_client_response(request_params: request_params) do
            client.get_usage_report_export(**request_params)
          end
        end

        # List all usage report exports for a customer
        def get_usage_report_exports(customer_id:)
          request_params = {
            customerId: customer_id.to_s,
          }
          handle_client_response(request_params: request_params) do
            client.get_usage_report_exports(**request_params)
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

        def get_usage_summary(customer_id:, year:, month:, day:, billing_period:, org_id: nil, repo_id: nil, cost_center_id: nil, product: nil, sku: nil)
          request_params = {
            customerId: customer_id.to_s,
            year: year,
            month: month,
            day: day,
            billingPeriod: billing_period,
            orgId: org_id,
            repoId: repo_id,
            costCenterId: cost_center_id,
            product: product,
            sku: sku,
          }
          handle_client_response(request_params: request_params) do
            client.get_usage_summary(**request_params)
          end
        end

        # Copilot Usage API

        def get_copilot_usage_chart_data(customer_id:, year: nil, month: nil, billing_period: nil, org_id: nil, user_id: nil, model: nil, group_by: nil, cost_center_id: nil, organization_admin_ids: nil, chart_type: nil, unit_type: nil)
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
            chartType: chart_type,
            unitType: unit_type,
          }
          handle_client_response(request_params: request_params) do
            client.get_copilot_usage_chart_data(**request_params)
          end
        end

        def get_copilot_usage_table(customer_id:, year: nil, month: nil, billing_period: nil, org_id: nil, user_id: nil, model: nil, group_by: nil, cost_center_id: nil, organization_admin_ids: nil, page: nil, rows_per_page: nil, unit_type: nil)
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
            rowsPerPage: rows_per_page,
            unitType: unit_type
          }
          handle_client_response(request_params: request_params) do
            client.get_copilot_usage_table(**request_params)
          end
        end

        def get_copilot_usage_card_data(customer_id:, year: nil, month: nil, billing_period: nil, org_id: nil, user_id: nil, model: nil, cost_center_id: nil, organization_admin_ids: nil, unit_type: nil)
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
            unitType: unit_type
          }
          handle_client_response(request_params: request_params) do
            client.get_copilot_usage_card_data(**request_params)
          end
        end

        def get_copilot_billing_preview(customer_id:, year: nil, month: nil, billing_period: nil)
          request_params = {
            customerId: customer_id.to_s,
            year: year,
            month: month,
            billingPeriod: billing_period,
          }
          handle_client_response(request_params: request_params) do
            client.get_copilot_billing_preview(**request_params)
          end
        end

        def get_copilot_models(customer_id:)
          request_params = {
            modelCustomerId: customer_id.to_s,
          }
          handle_client_response(request_params: request_params) do
            client.get_copilot_models(**request_params)
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

        def get_ai_credit_usage_report(customer_id:, year: nil, month: nil, day: nil, billing_period: nil, org_id: nil, user_id: nil, model: nil, product: nil, cost_center_id: nil)
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
            client.get_ai_credit_usage_report(**request_params)
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

        def get_key_value(customer_id:, key:)
          request_params = {
            customerId: customer_id.to_s,
            key:
          }
          handle_client_response(request_params: request_params) do
            client.get_key_value(**request_params)
          end
        end

        def add_key_value(customer_id:, key:, value:)
          request_params = {
            customerId: customer_id.to_s,
            key: key,
            value: value,
          }
          handle_client_response(request_params: request_params) do
            client.add_key_value(**request_params)
          end
        end

        def create_or_update_budget(budget:, feature_flag_target: nil, skip_cache_invalidation: false)
          request_params = {
            budget: budget,
          }
          response = handle_client_response(request_params: request_params) do
            client.create_or_update_budget(**request_params)
          end

          unless skip_cache_invalidation
            customer_id = budget_customer_id(budget)
            invalidate_budget_count_cache(customer_id, feature_flag_target: feature_flag_target) if customer_id.present?
          end

          response
        end

        def get_budget(key:)
          request_params = {
            key: key,
          }
          handle_client_response(request_params: request_params) do
            client.get_budget(**request_params)
          end
        end

        def get_budget_by_uuid(customer_id:, uuid:, page: nil)
          request_params = {
            customerId: customer_id.to_s,
            uuid: uuid,
          }

          request_params[:page] = page if page
          response = handle_client_response(request_params: request_params) do
            client.get_budget_by_uuid(**request_params)
          end

          return response unless response.is_a?(Hash)

          formatted_response = {}
          formatted_response[:budget] = Billing::Platform::Api::Budget.new(response)

          if response.key?(:hasNextPage)
            formatted_response[:has_next_page] = response[:hasNextPage]
          end

          formatted_response
        end

        def get_multi_user_budget_states(customer_id:, budget_uuid:, page: nil, page_size: nil, sort_order: nil, user_id: nil, threshold_lower_bound: nil, threshold_upper_bound: nil, filtered_orgs: nil)
          request_params = {
            customerId: customer_id.to_s,
            budgetUuid: budget_uuid,
          }

          request_params[:page] = page if page
          request_params[:pageSize] = page_size if page_size
          request_params[:sortOrder] = sort_order if sort_order
          request_params[:userId] = user_id.to_s if user_id
          request_params[:thresholdLowerBound] = threshold_lower_bound if threshold_lower_bound
          request_params[:thresholdUpperBound] = threshold_upper_bound if threshold_upper_bound
          request_params[:filteredOrgs] = filtered_orgs if filtered_orgs.present?

          response = handle_client_response(request_params: request_params) do
            client.get_multi_user_budget_states(**request_params)
          end

          return response unless response.is_a?(Hash)

          formatted_response = {}
          formatted_response[:user_states] = response[:userStates] || []
          formatted_response[:has_next_page] = response[:hasNextPage] || false
          formatted_response[:total_count] = response[:totalCount] || 0

          if response[:budget]
            formatted_response[:budget] = Billing::Platform::Api::Budget.new(response)
          end

          formatted_response
        end

        def get_all_budgets(customer_id:, page: nil, page_size: nil, scope: nil, exclude_scope: nil, scopes: nil, exclude_scopes: nil, filtered_orgs: nil, filtered_repos: nil, user_id: nil, budget_target: nil, use_remote_cache: false, feature_flag_target: nil, include_total_count: true, use_token_based_billing: nil)
          # Coerce to arrays (query params may yield a String for single values) and cap size.
          scopes = Array(scopes).first(MAX_SCOPE_ARRAY_SIZE).presence
          exclude_scopes = Array(exclude_scopes).first(MAX_SCOPE_ARRAY_SIZE).presence

          cache_enabled = FeatureFlag.vexi.enabled?(:billing_budget_count_cache, feature_flag_target, default: false)
          use_count_cache = use_remote_cache && cache_enabled && include_total_count && (page.present? || page_size.present?) && user_id.blank? && budget_target.blank?

          request_params = {
            customerId: customer_id.to_s,
            skip_total_count: T.let(false, T::Boolean),
          }

          request_params[:page] = page if page
          request_params[:page_size] = page_size if page_size
          request_params[:user_id] = user_id if user_id.present?
          request_params[:budget_target] = budget_target if budget_target.present?

          # Override for billing-platform's customer-level TBB flag; caller (dotcom) has the authoritative answer.
          unless use_token_based_billing.nil?
            request_params[:copilot_token_based_billing_enabled] = use_token_based_billing
          end

          # Repeated scope fields take precedence over singular fields
          if scopes.present?
            request_params[:scopes] = scopes.map { |s| convert_scope_to_enum(s) }
          elsif scope.present?
            scope_enum = convert_scope_to_enum(scope)
            request_params[:scope] = scope_enum
          end

          if exclude_scopes.present?
            request_params[:exclude_scopes] = exclude_scopes.map { |s| convert_scope_to_enum(s) }
          elsif exclude_scope.present?
            exclude_scope_enum = convert_scope_to_enum(exclude_scope)
            request_params[:exclude_scope] = exclude_scope_enum
          end

          if filtered_orgs.present?
            request_params[:filtered_orgs] = filtered_orgs
          end

          if filtered_repos.present?
            request_params[:filtered_repos] = filtered_repos
          end

          total_count = nil

          if use_count_cache
            cache_client = Billing::Cache::BudgetCountClient.new(customer_id.to_s, scope, exclude_scope, scopes: scopes, exclude_scopes: exclude_scopes, feature_flag_target: feature_flag_target)
            response = T.let(nil, T.untyped)

            begin
              total_count = cache_client.fetch do
                # Cache miss — make the API call requesting total count
                request_params[:skip_total_count] = false
                response = handle_client_response(request_params: request_params) do
                  client.get_all_budgets(**request_params)
                end
                response[:totalCount].to_i if response.is_a?(Hash) && response.key?(:totalCount) && !response[:totalCount].nil?
              end
            rescue Redis::BaseError => e
              log_fields = {
                exception: e,
                "gh.billing.customer.id": customer_id,
                "gh.billing_platform.budget.scope": scope,
                "gh.billing_platform.budget.exclude_scope": exclude_scope,
              }
              log_fields[:"gh.billing_platform.budget.scopes"] = scopes.join(",") if scopes.present?
              log_fields[:"gh.billing_platform.budget.exclude_scopes"] = exclude_scopes.join(",") if exclude_scopes.present?
              GitHub.logger.warn("Failed to use budget count cache", log_fields)
            end

            if response.nil? # Cache hit, or error before the API call was made
              # Skip total count computation when we already have a cached value
              request_params[:skip_total_count] = !total_count.nil?
              response = handle_client_response(request_params: request_params) do
                client.get_all_budgets(**request_params)
              end
            end
          else
            response = handle_client_response(request_params: request_params) do
              client.get_all_budgets(**request_params)
            end
          end

          return response unless response.is_a?(Hash)

          formatted_response = {
            budgets: response[:budgets].map do |item|
              Billing::Platform::Api::Budget.new(item)
            end
          }

          if response.key?(:hasNextPage)
            formatted_response[:has_next_page] = response[:hasNextPage]
          end

          # Use cached/fetched total_count when available, fall back to API response.
          # Skip total_count when include_total_count is false (e.g., org admin views where
          # the unfiltered count would not reflect the user's authorized budget subset).
          if !total_count.nil?
            formatted_response[:total_count] = total_count
          elsif include_total_count && response.key?(:totalCount) && !response[:totalCount].nil?
            formatted_response[:total_count] = response[:totalCount].to_i
          end

          if response.key?(:effectiveBudget)
            formatted_response[:effective_budget] = response[:effectiveBudget]
          end

          formatted_response
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

        def delete_budget(customer_id:, uuid:, feature_flag_target: nil, skip_cache_invalidation: false)
          request_params = {
            customerId: customer_id,
            uuid: uuid
          }

          response = handle_client_response(request_params: request_params) do
            client.delete_budget(**request_params)
          end

          # Invalidate budget count cache when deleting a budget
          invalidate_budget_count_cache(customer_id, feature_flag_target: feature_flag_target) unless skip_cache_invalidation

          response
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

        def get_spending_info(customer_id:, product:, entity_detail:, trust_tier: nil, year: nil, month: nil)
          if year.nil? ^ month.nil?
            return Billing::Platform::Api::Error.new("year and month must both be provided or both omitted")
          end
          if month && !(1..12).cover?(month.to_i)
            return Billing::Platform::Api::Error.new("month must be 1..12")
          end
          if year && year.to_i <= 0
            return Billing::Platform::Api::Error.new("year must be positive")
          end

          request_params = {
            customerId: customer_id.to_i,
            product: product,
            entityDetail: entity_detail,
            trustTier: trust_tier,
          }
          request_params[:year] = year.to_i if year
          request_params[:month] = month.to_i if month

          handle_client_response(request_params: request_params) do
            client.get_spending_info(**request_params)
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

        def update_discount(customer_id:, discount_uuid:, funding_source: nil, target_amount: nil, end_date: nil, percentage: nil)
          request_params = {
              customerId: customer_id,
              uuid: discount_uuid,
              fundingSource: funding_source,
              targetAmount: target_amount,
              endDate: end_date,
              percentage: percentage
          }
          handle_client_response(request_params: request_params) do
            client.update_discount(**request_params)
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

        def get_alertable_budget_state_info(customer_id:, feature_flag_target: nil)
          request_params = {
            customerId: customer_id.to_s,
          }

          unless FeatureFlag.vexi.enabled?(:billing_alertable_budget_state_cache, feature_flag_target, default: false)
            return request_alertable_budget_state_info(request_params)
          end

          cache_client = Billing::Cache::AlertableBudgetStateClient.new(customer_id.to_s, feature_flag_target: feature_flag_target)
          raw_response = T.let(nil, T.untyped)

          begin
            cached_budgets = cache_client.fetch do
              raw_response = request_alertable_budget_state_info(request_params)
              if raw_response.is_a?(Hash) && raw_response[:budgets].is_a?(Array)
                raw_response[:budgets].map(&:raw_budget_hash)
              else
                # Error or unexpected shape — return nil so the cache skips the
                # write and we surface the real response/error to the caller.
                nil
              end
            end
          rescue Redis::BaseError => e
            GitHub.logger.warn(
              "Failed to use alertable budget state cache",
              exception: e,
              "gh.billing.customer.id": customer_id,
            )
            return raw_response || request_alertable_budget_state_info(request_params)
          end

          if cached_budgets.present?
            { budgets: cached_budgets.map { |item| Billing::Platform::Api::Budget.new(item) } }
          elsif raw_response
            # Live miss whose response was an error or an empty/unexpected shape.
            raw_response
          else
            # Cache hit with no alertable budgets.
            { budgets: [] }
          end
        end

        private

        def request_alertable_budget_state_info(request_params)
          response = handle_client_response(request_params: request_params, api_name: "get_alertable_budget_state_info") do
            client.get_alertable_budget_state_info(**request_params)
          end

          if response.is_a?(Hash) && response[:budgets].is_a?(Array)
            response[:budgets] = response[:budgets].map { |item| Billing::Platform::Api::Budget.new(item) }
          end
          response
        end

        def handle_client_response(request_params: {}, api_name: nil)
          # method that called "handle_client_response" is the billing API method
          # look back call stack 1 level above. Callers that wrap this in a
          # helper (e.g. for caching) can pass `api_name:` to preserve the
          # original API name in telemetry.
          api = api_name || caller_locations(1, 1)&.first&.base_label

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
        rescue => e
          log_error_and_return(error: e, caller_method: caller_method, api: api, path: caller_path, request_params: request_params)
        end

        # TODO: Errors should be raised and handled by the top level controller(s)
        def log_error_and_return(error:, caller_method:, api:, path:, request_params: {})
          GitHub.dogstats.increment("billing_platform.client.error", tags: [
            "api:#{api}",
            "caller:#{caller_method}",
            "error:#{error.class.name.underscore.parameterize}"
          ])
          client_error = Billing::Platform::Api::Error.new("Failed to request #{api}. Called from #{caller_method} in #{path}.\n\nError:\n #{error}.", original_error: error)
          GitHub.logger.error({
            exception: error,
            "code.namespace": self.class.name.to_s,
            "code.function": caller_method,
            "code.caller.path": path,
            "gh.billing.billing_platform.client.api": api,
            "gh.billing.billing_platform.client.request": request_params
          })

          if client_error.http_5xx?
            Failbot.report(client_error, {
              "http.status_code": client_error.http_status,
              "code.function": caller_method,
              "code.caller.path": path,
              "api_route": api,
              "gh.billing.billing_platform.client.api": api,
              "gh.billing.billing_platform.client.request": request_params,
              "catalog_service": "github/metered_billing_data"
            })
          end

          client_error
        end

        sig { returns(::BillingPlatform::Client) }
        def platform_client
          ::BillingPlatform::Client.new(
            host: GitHub.billing_platform_host,
            hmac_key: GitHub.billing_platform_hmac_secret_key,
            timeout: timeout,
          ) do |conn|
            conn.request :retry, retry_options
            conn.use GitHub::FaradayMiddleware::RequestID
            conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: BILLING_PLATFORM_SERVICE_NAME, enable_path_tag: true
          end
        end

        def invalidate_budget_count_cache(customer_id, feature_flag_target: nil)
          return unless FeatureFlag.vexi.enabled?(:billing_budget_count_cache, feature_flag_target, default: false)

          begin
            cache_client = Billing::Cache::BudgetCountClient.for_all_scopes(customer_id.to_s, feature_flag_target: feature_flag_target)
            cache_client.invalidate("budget_mutation")
          rescue Redis::BaseError => e
            GitHub.logger.error("Failed to invalidate budget count cache", {
              exception: e,
              "gh.billing.customer.id": customer_id,
            })
            GitHub.dogstats.increment("billing.budget_count_cache.error", tags: [
              "error:invalidate",
            ])
          end
        end

        def budget_customer_id(budget)
          budget_hash = case budget
          when String
            JSON.parse(budget).with_indifferent_access
          when Hash
            budget.with_indifferent_access
          else
            budget.respond_to?(:to_h) ? budget.to_h.with_indifferent_access : nil
          end
          return unless budget_hash

          key = budget_hash[:key]
          return unless key

          key[:customerId]
        rescue JSON::ParserError => e
          GitHub.logger.error("Failed to parse budget JSON for cache invalidation", {
            exception: e
          })
          GitHub.dogstats.increment("billing.budget_count_cache.error", tags: ["error:parse"])
          nil
        end

        def convert_scope_to_enum(scope_string)
          # Explicitly handle nil values
          return 0 if scope_string.nil?

          case scope_string.to_s.downcase
          when "organization", "org"
            4  # Org enum value
          when "enterprise"
            7  # CustomerResource enum value
          when "cost_center", "cost-center"
            6  # CostCenterResource enum value
          when "customer"
            7  # CustomerResource enum value
          when "user"
            1  # User enum value
          when "team"
            2  # Team enum value
          when "repo", "repository"
            3  # Repo enum value
          when "multi_user_customer"
            8  # MultiUserCustomer enum value
          else
            # Default to 0 (NoTarget) for unknown values
            0
          end
        end

        def retry_options
          {
            max: 2,
            interval: 0.050,
            interval_randomness: 0.5,
            backoff_factor: 1.2,
            methods: [:post],
            exceptions: [Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::RetriableResponse],
            retry_statuses: [502, 503],
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
