# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::AzureEmissionsController < Stafftools::Businesses::BillingController
  extend T::Sig

  include ReactHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing, only: [:index]

  def self.react_bundle_name
    "billing-app"
  end

  def index
    respond_to do |format|
      format.json do
        if params[:day] == "3"
          render json: {
            azureEmissions: []
          }, status: 200
        else
          render json: {
            azureEmissions: [
              {
                id: 1,
                azurePartitionKey: "940d8147-9fab-428d-81c6-276dba19ca1b",
                sku: "actions_linux",
                quantity: 100.23,
                emissionState: "pending",
                emissionDate: "2023-03-22",
              },
              {
                id: 2,
                azurePartitionKey: "4bddf92a-bb04-4675-826b-caf4772d2083",
                sku: "actions_macos",
                quantity: 50.3,
                emissionState: "pending",
                emissionDate: "2023-03-22",
              }
            ]
          }, status: 200
        end
      end

      format.html do
        payload = {
          slug: this_business.slug,
        }

        render_react_app payload: payload, page_data: { selected_link: :business_billing_vnext_azure_emissions }, title: "Azure Emissions", ssr: true
      end
    end
  end
end
