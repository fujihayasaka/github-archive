# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::AzureEmissionsController < Stafftools::Businesses::BillingController
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
        azure_emissions = fetch_azure_emissions(params[:product], params[:year], params[:month], params[:day])
        if azure_emissions.is_a?(::Billing::Platform::Api::Error)
          return render json: { error: "An error happened when retrieving azure emissions" }, status: 500
        end

        payload = {
          is_stafftools_route: true,
          slug: this_business.slug,
          azureEmissions: azure_emissions,
        }

        return render json: { payload: payload }, status: 200
      end

      format.html do
        products = all_products
        if products.empty?
          flash[:error] = "An error happened when retrieving products"
        else
          products = products.map { |p| { friendlyName: p[:friendlyProductName], productName: p[:name] } }
        end

        payload = {
          is_stafftools_route: true,
          slug: this_business.slug,
          products: products,
        }

        return render_react_app payload: payload, page_data: { selected_link: :business_billing_vnext_azure_emissions }, title: "Azure Emissions"
      end
    end
  end

  private

  sig do
    params(
      selected_product: String,
      year: String,
      month: String,
      day: String,
    )
    .returns(T.any(T::Array[T::Hash[Symbol, T.untyped]], ::Billing::Platform::Api::Error))
  end
  def fetch_azure_emissions(selected_product, year, month, day)
    azure_emissions = billing_platform_client.admin_get_azure_emissions(
      customer_id: this_business.customer_id,
      product: selected_product,
      year: year,
      month: month,
      day: day
    )

    if azure_emissions.is_a?(::Billing::Platform::Api::Error)
      azure_emissions
    else
      azure_emissions[:azureEmissions]
    end
  end
end
