# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::TriggerAzureEmissionsController < Stafftools::Businesses::BillingController
  extend T::Sig

  include Billing::Platform::Api::Utils
  include Businesses::AzureSubscriptions

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:show, :trigger_emission]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render("stafftools/businesses/billing/trigger_azure_emission/show")
  end

  def trigger_emission # rubocop:todo GitHub/UseRestfulActions
    if params[:emission_date].present?
      year, month, day = params[:emission_date].split("-").map { |s| s.to_i }
      customer_id = this_business.customer.id
      response = ::Billing::Platform::Api::Client.new.admin_trigger_azure_emission(customer_id: customer_id.to_s, year: year, month: month, day: day)

      if response.is_a?(::Billing::Platform::Api::Error)
        flash[:error] = "Error : #{response}"
      else
        flash[:notice] = "Dispatched azure emission for #{params[:emission_date]}"
      end
    end
    redirect_to(action: :show)
  end
end
