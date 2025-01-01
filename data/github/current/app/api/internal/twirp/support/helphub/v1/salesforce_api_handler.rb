# typed: true
# frozen_string_literal: true

require "monolith-twirp-support-helphub"

module Api::Internal::Twirp::Support
  module HelpHub
    module V1
      # Provides access to Support-relevant data.
      class SalesforceAPIHandler < Api::Internal::Twirp::Handler
        handles_service(MonolithTwirp::Support::HelpHub::V1::SalesforceAPIService)

        allow_access_for :user, :client, allowed_clients: %w(helphub).freeze

        # Public: Implementation of the GetSalesforceAccount Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::GetSalesforceAccountRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a MonolithTwirp::Support::HelpHub::V1::GetSalesforceAccountResponse.
        def get_salesforce_account(req, env)
          return Twirp::Error.invalid_argument("No salesforce_account_id provided", argument: "salesforce_account_id") if req.salesforce_account_id.nil?

          salesforce_account = Billing::SalesforceAccount.find_by(salesforce_id: req.salesforce_account_id)
          if salesforce_account.nil?
            return Twirp::Error.not_found("Salesforce account not found", argument: "salesforce_account_id")
          end


          {
            salesforce_id: salesforce_account.salesforce_id,
            business_segment: salesforce_account.business_segment,
            territory_name: salesforce_account.territory_name,
            msft_ean: salesforce_account.msft_ean,
            msft_pcn: salesforce_account.msft_pcn,
            msft_tpid: salesforce_account.msft_tpid,
            ms_sales_tpid_best_match: salesforce_account.ms_sales_tpid_best_match,
            microsoft_partnerone_id_text: salesforce_account.microsoft_partnerone_id_text,
            trade_screen_status: salesforce_account.trade_screen_status,
            account_owner_handle: salesforce_account.account_owner_handle,
          }
        end
      end
    end
  end
end
