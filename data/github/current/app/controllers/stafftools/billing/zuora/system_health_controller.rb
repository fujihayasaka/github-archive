# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    module Zuora
      class SystemHealthController < StafftoolsController
        before_action :dotcom_required

        CARD_ACTIONS = [:api_health, :payments, :billing_docs, :tax].freeze

        depends_on_clusters ApplicationRecord::Mysql1,
          ApplicationRecord::Collab,
          ApplicationRecord::Billing,
          ApplicationRecord::Ballast,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Configurations,
          only: [:index] + CARD_ACTIONS

        depends_on_clusters ApplicationRecord::Copilot,
          only: [:index] + CARD_ACTIONS, optional: true

        def index
          render "stafftools/billing/zuora/system_health/index", locals: {
            range: params[:range] || "1h",
            gateway_filter: params[:gateway].presence,
            path_filter: params[:path].presence,
          }
        end

        def api_health # rubocop:todo GitHub/UseRestfulActions
          time_params = build_time_params(params[:range] || "1h")
          path_filter = params[:path].presence
          error = nil

          api_volume = fetch_health_data(
            "/system-health/api-requests/volume-summary",
            time_params.merge(path_filter ? { path: path_filter } : {}),
          )
          api_failures = fetch_health_data(
            "/system-health/api-requests/failures",
            time_params.merge(limit: 50),
          )
        rescue => e
          Failbot.report(e, app: "github-zuora")
          error = error_message(e)
          api_volume ||= []
          api_failures ||= []
        ensure
          render partial: "stafftools/billing/zuora/system_health/api_health", layout: false, locals: {
            api_volume: api_volume || [], api_failures: api_failures || [], error: error,
          }
        end

        def payments # rubocop:todo GitHub/UseRestfulActions
          time_params = build_time_params(params[:range] || "1h")
          gateway_filter = params[:gateway].presence
          error = nil

          payment_volume = fetch_health_data(
            "/system-health/payments/volume-summary",
            time_params.merge(gateway_filter ? { paymentGatewayType: gateway_filter } : {}),
          )
          payment_records = fetch_health_data(
            "/system-health/payments/details",
            time_params.merge(limit: 50),
          )
        rescue => e
          Failbot.report(e, app: "github-zuora")
          error = error_message(e)
          payment_volume ||= []
          payment_records ||= []
        ensure
          render partial: "stafftools/billing/zuora/system_health/payments", layout: false, locals: {
            payment_volume: payment_volume || [], payment_records: payment_records || [], error: error,
          }
        end

        def billing_docs # rubocop:todo GitHub/UseRestfulActions
          time_params = build_time_params(params[:range] || "1h")
          error = nil

          billing_doc_volume = fetch_health_hash(
            "/system-health/billing-documents/volume-summary",
            time_params,
          )
        rescue => e
          Failbot.report(e, app: "github-zuora")
          error = error_message(e)
          billing_doc_volume ||= {}
        ensure
          render partial: "stafftools/billing/zuora/system_health/billing_docs", layout: false, locals: {
            billing_doc_volume: billing_doc_volume || {}, error: error,
          }
        end

        def tax # rubocop:todo GitHub/UseRestfulActions
          time_params = build_time_params(params[:range] || "1h")
          error = nil

          tax_records = fetch_health_data(
            "/system-health/tax/details",
            time_params.merge(limit: 50),
          )
        rescue => e
          Failbot.report(e, app: "github-zuora")
          error = error_message(e)
          tax_records ||= []
        ensure
          render partial: "stafftools/billing/zuora/system_health/tax", layout: false, locals: {
            tax_records: tax_records || [], error: error,
          }
        end

        private

        def build_time_params(range)
          end_time = Time.now.utc
          start_time = case range
          when "30m" then end_time - 30.minutes
          when "1h"  then end_time - 1.hour
          when "6h"  then end_time - 6.hours
          when "24h" then end_time - 24.hours
          when "7d"  then end_time - 7.days
          else end_time - 1.hour
          end

          {
            startTime: start_time.strftime("%Y-%m-%dT%H:%M%z"),
            endTime: end_time.strftime("%Y-%m-%dT%H:%M%z"),
          }
        end

        def zuora_client
          GitHub.zuorest_background_worker_client
        end

        def fetch_health_data(path, params)
          response = zuora_client.oauth_get(path, params: params) # rubocop:disable GitHub/ZuoraRestVerbs

          if response.is_a?(Hash)
            result = response["data"] || response[:data]
            result.is_a?(Array) ? result : []
          elsif response.is_a?(Array)
            response
          else
            []
          end
        end

        def fetch_health_hash(path, params)
          response = zuora_client.oauth_get(path, params: params) # rubocop:disable GitHub/ZuoraRestVerbs
          response.is_a?(Hash) ? response : {}
        end

        def error_message(error)
          if error.is_a?(Zuorest::HttpError)
            "HTTP #{error.status_code}: #{error.data}"
          else
            error.message
          end
        end
      end
    end
  end
end
