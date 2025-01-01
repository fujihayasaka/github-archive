# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroSalesforceAccountChangeJob < HydroMessageJob

  queue_as :hydro_salesforce_account_change
  retry_on_dirty_exit

  # Public: process a Hydro message
  sig { void }
  def perform
    case message[:change_type]
    when :CREATE, :UPDATE
      account = Billing::SalesforceAccount.find_or_initialize_by(salesforce_id: message[:account_id])
      business = Business.find_by(id: message[:business_id])

      with_write do
        account.update!(
          business: business,
          business_segment: message[:business_segment],
          territory_name: message[:territory_name],
          msft_ean: message[:msft_ean],
          msft_pcn: message[:msft_pcn],
          msft_tpid: message[:msft_tpid],
          ms_sales_tpid_best_match: message[:ms_sales_tpid_best_match],
          microsoft_partnerone_id_text: message[:microsoft_partnerone_id_text],
          trade_screen_status: message[:trade_screen_status],
          account_owner_handle: message[:account_owner_handle]&.truncate(40),
        )
      end
    when :DELETE
      with_write do
        Billing::SalesforceAccount.destroy_by(salesforce_id: message[:account_id])
      end
    end
  end
end
