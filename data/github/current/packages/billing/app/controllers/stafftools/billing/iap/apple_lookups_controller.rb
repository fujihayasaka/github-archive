# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    module Iap
      class AppleLookupsController < StafftoolsController
        before_action :ensure_iap_is_enabled

        depends_on_clusters ApplicationRecord::Ballast,
          ApplicationRecord::Billing,
          ApplicationRecord::Collab,
          ApplicationRecord::Configurations,
          ApplicationRecord::Copilot,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Mysql2,
          ApplicationRecord::NotificationsEntries, only: %i[new]

        def new
          render "stafftools/billing/iap/apple_lookups/new", locals: { transaction_id:, json_details: nil }
        end

        def create
          if transaction_id.blank?
            flash.now[:error] = "Please provide a Transaction ID."
            render "stafftools/billing/iap/apple_lookups/new", locals: { transaction_id:, json_details: nil }
            return
          end

          begin
            json_details = fetch_from_apple!
          rescue => ex # rubocop:disable Lint/GenericRescue
            Failbot.report(ex)

            # Catch and output whatever happened during the network request to and response from Apple,
            # even if it is something completely unknown.
            json_details = ex.message
          end

          render "stafftools/billing/iap/apple_lookups/new", locals: { transaction_id:, json_details: }
        end

        private

        # Note: Mobile::Apple::AppStoreService#get_all_subscription_statuses can raise a bunch of different errors
        # depending on the result, network conditions, and JSON (de)serialization issues.
        def fetch_from_apple!
          status_response = service.get_all_subscription_statuses(original_transaction_id: transaction_id)

          summary_and_response = {
            subscription_summary: Mobile::Apple::SubscriptionSummary.from_status_response(status_response),
            status_response:
          }

          JSON.pretty_generate(JSON.parse(summary_and_response.to_json))
        end

        def ensure_iap_is_enabled
          render_404 unless GitHub.iap_enabled?
        end

        def service
          Mobile::Apple::AppStoreService.from_config
        end

        def transaction_id
          params[:transaction_id]
        end
      end
    end
  end
end
