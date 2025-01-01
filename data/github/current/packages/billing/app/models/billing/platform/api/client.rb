# typed: true
# frozen_string_literal: true

require "billing-platform/client"

module Billing
  module Platform
    module Api
      class Client
        extend T::Sig

        BILLING_PLATFORM_SERVICE_NAME = "billing-platform".freeze

        attr_reader :timeout, :client

        def initialize(timeout: nil)
          @timeout = timeout
          @client = platform_client
        end

        ### Subscriptions API
        def get_subscribed_item(usage_entity_id:, subscription_id:, sku:)
          handle_client_response do
            request_params = {
              sku: sku,
              subscriptionId: subscription_id,
              usageEntityId: usage_entity_id,
            }
            @client.get_subscribed_item(**request_params)
          end
        end

        def get_subscribed_items(usage_entity_id:, sku:)
          handle_client_response do
            request_params = {
              sku: sku,
              usageEntityId: usage_entity_id,
            }
            @client.get_subscribed_items(**request_params)
          end
        end

        def get_active_subscribed_items(usage_entity_id:, sku:)
          handle_client_response do
            request_params = {
              sku: sku,
              usageEntityId: usage_entity_id,
            }
            @client.get_active_subscribed_items(**request_params)
          end
        end

        def get_subscribed_items_total(usage_entity_id:, sku:)
          handle_client_response do
            request_params = {
              sku: sku,
              usageEntityId: usage_entity_id,
            }
            @client.get_subscribed_items_total(**request_params)
          end
        end

        def get_subscribed_items_monthly_total(usage_entity_id:, sku:, year:, month:)
          handle_client_response do
            request_params = {
              usageEntityId: usage_entity_id,
              sku: sku,
              year: year,
              month: month
            }
            @client.get_subscribed_items_monthly_total(**request_params)
          end
        end

        def add_license(sku:, subscription_at:, entity_detail:)
          handle_client_response do
            request_params = {
              sku: sku,
              subscriptionAt: subscription_at,
              entityDetail: entity_detail,
            }
            @client.add_license(**request_params)
          end
        end

        def remove_license(sku:, subscription_at:, entity_detail:)
          handle_client_response do
            request_params = {
              sku: sku,
              subscriptionAt: subscription_at,
              entityDetail: entity_detail,
            }
            @client.remove_license(**request_params)
          end
        end

        ### Admin API
        def admin_process_dead_letter_queue(num:, queue_name: "")
          handle_client_response do
            request_params = {
              num: num,
              queueName: queue_name,
            }
            client.admin_process_dead_letter_queue(**request_params)
          end
        end

        def admin_trigger_azure_emission(customer_id: "", year:, month:, day:)
          handle_client_response do
            request_params = {
              customerId: customer_id,
              year: year,
              month: month,
              day: day,
            }
            client.admin_trigger_azure_emission(**request_params)
          end
        end

        def admin_trigger_invoice_generation(customer_id:, month:, year:)
          handle_client_response do
            client.admin_trigger_invoice_generation(customerId: customer_id.to_s, month: month, year: year)
          end
        end

        def admin_trigger_watermark_workflow(year:, month:, day:, hour:, customer_id: "", sku: "")
          handle_client_response do
            request_params = {
              customerId: customer_id,
              sku: sku,
              year: year,
              month: month,
              day: day,
              hour: hour,
            }
            client.admin_trigger_watermark_workflow(**request_params)
          end
        end

        def admin_generate_usage(customer_id: "", sku: "", repo_id: 0, org_id: 0, amount: 0.0, quantity: 0.0)
          handle_client_response do
            request_params = {
              customerId: customer_id,
              sku: sku,
              orgId: org_id,
              repoId: repo_id,
              amount: amount,
              quantity: quantity,
            }
            client.admin_generate_usage(**request_params)
          end
        end

        def admin_trigger_high_watermark_rollover(customer_id: "", sku: "", year:, month:, dry_run: true)
          handle_client_response do
            request_params = {
              customerId: customer_id,
              sku: sku,
              year: year,
              month: month,
              dryRun: dry_run,
            }
            client.admin_trigger_high_watermark_rollover_job(**request_params)
          end
        end

        ### Cost Center API

        def get_all_cost_centers(customer_id:)
          handle_client_response do
            request_params = {
              customerId: customer_id,
            }
            client.get_all_cost_centers(**request_params)
          end
        end

        def get_cost_center(cost_center_key:)
          handle_client_response do
            request_params = {
              costCenterKey: cost_center_key,
            }
            client.get_cost_center(**request_params)
          end
        end

        def find_cost_center_for(entity_detail:)
          handle_client_response do
            request_params = {
              entityDetail: entity_detail,
            }
            client.find_cost_center_for(**request_params)
          end
        end

        def create_cost_center(customer_id:, target_id:, target_type:, name:, resources:)
          handle_client_response do
            request_params = {
              customerId: customer_id,
              targetId: target_id,
              targetType: target_type,
              name:,
              resources:,
            }
            client.create_cost_center(**request_params)
          end
        end

        def update_cost_center(key:, target_id:, name:, resources_to_add:, resources_to_remove:)
          handle_client_response do
            request_params = {
              key: {
                customerId: key[:customer_id],
                uuid: key[:uuid],
              },
              targetId: target_id,
              name:,
              resourcesToAdd: resources_to_add,
              resourcesToRemove: resources_to_remove,
            }
            client.update_cost_center(**request_params)
          end
        end

        def add_resource_to_cost_center(key:, resources:)
          handle_client_response do
            request_params = {
              key: key,
              resources: resources,
            }
            client.add_resource_to_cost_center(**request_params)
          end
        end

        def remove_resource_from_cost_center(key:, resources:)
          handle_client_response do
            request_params = {
              key: key,
              resources: resources,
            }
            client.remove_resource_from_cost_center(**request_params)
          end
        end

        def archive_cost_center(cost_center_key:)
          handle_client_response do
            request_params = {
              costCenterKey: cost_center_key,
            }
            client.archive_cost_center(**request_params)
          end
        end

        # Pricing API

        def get_pricing(sku:)
          handle_client_response do
            request_params = {
              sku: sku,
            }
            client.get_pricing(**request_params)
          end
        end

        def create_or_update_pricing(pricing:)
          handle_client_response do
            request_params = {
              pricing: pricing,
            }
            client.create_or_update_pricing(**request_params)
          end
        end

        def get_all_pricing
          handle_client_response do
            client.get_all_pricing
          end
        end

        def get_pricings_by_product(product_name:)
          handle_client_response do
            request_params = {
              productName: product_name,
            }

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
          handle_client_response do
            client.get_product(product_sku)
          end
        end

        def create_or_update_product(product)
          handle_client_response do
            client.create_or_update_product(product)
          end
        end

        # Usage API

        def get_usage_total(usage_entity_id:, product: "", sku: "", billing_period: nil, year: nil, month: nil, day: nil, hour: nil)
          handle_client_response do
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
            client.get_usage_total(**request_params)
          end
        end

        def get_discount_total(usage_entity_id:, sku:, year:, month:, day:, hour:, billing_period:)
          handle_client_response do
            request_params = {
              usageEntityId: usage_entity_id.to_s,
              sku: sku,
              year: year,
              month: month,
              day: day,
              hour: hour,
              billingPeriod: billing_period,
            }
            client.get_discount_total(**request_params)
          end
        end

        def get_watermark_level(usage_entity_id:, sku:, org_id:, repo_id:)
          handle_client_response do
            request_params = {
              usageEntityId: usage_entity_id.to_s,
              sku: sku,
              orgId: org_id,
              repoId: repo_id,
            }
            client.get_watermark_level(**request_params)
          end
        end

        def get_usage_line_items(usage_entity_id:, product: "", sku: "", billing_period: nil, year: nil, month: nil, day: nil, hour: nil, org_id: nil, repo_id: nil, group_by: nil)
          handle_client_response do
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
            client.get_usage_line_items(**request_params)
          end
        end

        def get_net_usage_line_items(usage_entity_id:, product: "", sku: "", billing_period: nil, year: nil, month: nil, day: nil, hour: nil, org_id: nil, repo_id: nil, group_by: nil)
          handle_client_response do
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
            client.get_net_usage_line_items(**request_params)
          end
        end

        def get_top_org_repo_usage_line_items(usage_entity_id:, cost_center_id: nil, year: nil, month: nil, day: nil, hour: nil, billing_period: nil, group_by: nil, organization_ids: nil)
          handle_client_response do
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
            }
            client.get_top_org_repo_usage_line_items(**request_params)
          end
        end

        def get_usage_report(usage_entity_id:, billing_period: nil, year: nil, month: nil, day: nil, hour: nil, include_cost_center_usage: false)
          handle_client_response do
            request_params = {
              usageEntityId: usage_entity_id.to_s,
              billingPeriod: billing_period,
              year: year,
              month: month,
              day: day,
              hour: hour,
              includeCostCenterUsage: include_cost_center_usage,
            }
            client.get_usage_report(**request_params)
          end
        end

        def queue_usage_report_export(customer_id:, start_date:, end_date:, actor_id:, organization_ids: nil)
          handle_client_response do
            request_params = {
              customerId: customer_id.to_s,
              startDate: start_date,
              endDate: end_date,
              actorId: actor_id,
              organizationIds: organization_ids,
            }
            client.queue_usage_report_export(**request_params)
          end
        end

        def get_discount_line_items(usage_entity_id:, product: "", sku: "", billing_period: nil, year: nil, month: nil, day: nil, hour: nil, org_id: nil, repo_id: nil, group_by: nil)
          handle_client_response do
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
            client.get_discount_line_items(**request_params)
          end
        end

        def get_repo_usage_line_items(usage_entity_id:, billing_period: nil, year: nil, month: nil, day: nil, hour: nil)
          handle_client_response do
            request_params = {
              usageEntityId: usage_entity_id.to_s,
              billingPeriod: billing_period,
              year: year,
              month: month,
              day: day,
              hour: hour
            }
            client.get_repo_usage(**request_params)
          end
        end

        def get_invoice(customer_id:, year:, month:)
          handle_client_response do
            request_params = {
              customerId: customer_id.to_s,
              year: year,
              month: month
            }
            client.get_invoice(**request_params)
          end
        end

        def get_usage_chart_data(usage_entity_id:, product:, sku:, year: nil, month: nil, day: nil, hour: nil, billing_period: nil, org_id: nil, repo_id: nil, group_by: nil, cost_center_id: nil, filtered_orgs: nil, filtered_repos: nil)
          handle_client_response do
            request_params = {
              usageEntityId: usage_entity_id,
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
            client.get_usage_chart_data(**request_params)
          end
        end

        # Invoices API

        def get_invoices(customer_id:)
          handle_client_response do
            client.get_invoices(customerId: customer_id.to_s)
          end
        end

        # Customer API

        def create_or_update_customer(customer:)
          handle_client_response do
            client.create_or_update_customer(customer: customer)
          end
        end

        def create_or_patch_customer(customer:)
          handle_client_response do
            client.create_or_patch_customer(customer: customer)
          end
        end

        def get_customer(customer_id:)
          handle_client_response do
            request_params = {
              customerId: customer_id.to_s,
            }
            client.get_customer(**request_params)
          end
        end

        def get_customers(customer_ids:)
          handle_client_response do
            request_params = {
              customerIds: customer_ids,
            }
            client.get_customers(**request_params)
          end
        end

        def create_or_update_budget(budget:)
          handle_client_response do
            request_params = {
              budget: budget,
            }
            client.create_or_update_budget(**request_params)
          end
        end

        def get_budget(key:)
          handle_client_response do
            request_params = {
              key: key,
            }
            client.get_budget(**request_params)
          end
        end

        def get_budget_by_uuid(customer_id:, uuid:)
          response = handle_client_response do
            request_params = {
              customerId: customer_id.to_s,
              uuid: uuid,
            }
            client.get_budget_by_uuid(**request_params)
          end
          response[:budget] = Billing::Platform::Api::Budget.new(response)
          response
        end

        def get_all_budgets(customer_id:)
          response = handle_client_response do
            request_params = {
              customerId: customer_id.to_s,
            }
            client.get_all_budgets(**request_params)
          end

          # why are we doing this?
          if response.is_a?(Hash) && response[:budgets].is_a?(Array)
            response[:budgets] = response[:budgets].map { |item| Billing::Platform::Api::Budget.new(item) }
          end
          response
        end

        def get_budget_state(key:, year:, month:)
          handle_client_response do
            request_params = {
              key: key,
              year: year,
              month: month,
            }
            client.get_budget_state(**request_params)
          end
        end

        def delete_budget(customer_id:, uuid:)
          handle_client_response do
            request_params = {
              customerId: customer_id,
              uuid: uuid
            }
            client.delete_budget(**request_params)
          end
        end

        def can_proceed_with_usage(usage_key:)
          handle_client_response do
            request_params = {
              usageKey: usage_key,
            }
            client.can_proceed_with_usage(**request_params)
          end
        end

        def create_discount(discount:)
          handle_client_response do
            request_params = {
              discount: discount,
            }
            client.create_discount(**request_params)
          end
        end

        def get_discount(key:)
          handle_client_response do
            request_params = {
              key: key,
            }
            client.get_discount(**request_params)
          end
        end

        def get_all_discounts(customer_id:)
          handle_client_response do
            request_params = {
              customerId: customer_id.to_s,
            }
            client.get_all_discounts(**request_params)
          end
        end

        def get_discount_state(key:, year:, month:)
          handle_client_response do
            request_params = {
              key: key,
              year: year,
              month: month,
            }
            client.get_discount_state(**request_params)
          end
        end

        def get_all_discount_states(customer_id:, year:, month:)
          handle_client_response do
            request_params = {
              customerId: customer_id.to_s,
              year: year,
              month: month,
            }
            client.get_all_discount_states(**request_params)
          end
        end


        private

        def handle_client_response
          response = yield
          if response.error.nil?
            response.data.to_h
          else
            log_error_and_return(error: response.error, method: caller_locations(2, 1)&.first&.base_label)
          end
        rescue => e # rubocop:todo Lint/GenericRescue
          log_error_and_return(error: e, method: caller_locations(2, 1)&.first&.base_label)
        end

        # TODO: Errors should be raised and handled by the top level controller(s)
        def log_error_and_return(error:, method:, request_params: {})
          GitHub.dogstats.increment("billing-platform.client.error", tags: ["method:#{method}", "error:#{error.class.name.underscore.parameterize}"])

          client_error = Billing::Platform::Api::Error.new("Failed to request #{method}.\n\nError:\n #{error}", original_error: error)
          GitHub::Logger.log_exception({ fn: "billing-platform.client.#{method}", original_error: error.to_s }.merge!(request_params), client_error)

          if client_error.http_5xx?
            Failbot.report(client_error, { "http.status_code" => client_error.http_status, "code.function" => method })
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
            conn.use Billing::Api::ShedMiddlewareWrapper
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
