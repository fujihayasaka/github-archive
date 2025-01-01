# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    module Iap
      class GoogleLookupsController < StafftoolsController

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

        sig { void }
        def new
          render "stafftools/billing/iap/google_lookups/new", locals: { purchase_token:, json_details: nil }
        end

        sig { void }
        def create
          if purchase_token.blank?
            flash.now[:error] = "Please provide a purchase token."
            render "stafftools/billing/iap/google_lookups/new", locals: { purchase_token:, json_details: nil }
            return
          end
          begin
            json_details = fetch_from_google!
          rescue => ex # rubocop:disable Lint/GenericRescue
            # Ensure we still report the error to Failbot even if we are still going to surface
            # it to the user and return a 200.
            Failbot.report(ex)

            # Catch and output whatever happened during the network request to and response from Google,
            # even if it is something completely unknown.
            json_details = ex.message
          end

          render "stafftools/billing/iap/google_lookups/new", locals: { purchase_token:, json_details: }
        end

        private

        sig { returns(String) }
        def fetch_from_google!
          subscription_purchase = play_store_service.get_subscription_purchase_v2(purchase_token: purchase_token)

          summary_and_response = {
            subscription_purchase_summary: Mobile::Google::SubscriptionPurchaseSummary.from_subscription_purchase_v2(subscription_purchase, purchase_token),
            subscription_purchase:
          }

          JSON.pretty_generate(summary_and_response.as_json)
        end

        sig { void }
        def ensure_iap_is_enabled
          render_404 unless GitHub.iap_enabled?
        end

        sig { returns(Mobile::Google::PlayStoreService) }
        def play_store_service
          Mobile::Google::PlayStoreService.from_config
        end

        sig { returns(String) }
        def purchase_token
          params[:purchase_token].to_s
        end
      end
    end
  end
end
