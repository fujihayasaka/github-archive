# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::ZuoraEmissionController < Stafftools::Businesses::BillingController
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
        zuora_emissions = fetch_zuora_emissions(params[:year], params[:month], params[:day])
        if zuora_emissions.is_a?(::Billing::Platform::Api::Error)
          return render json: { error: "An error happened when retrieving zuora emissions" }, status: 500
        end

        if zuora_emissions.nil?
          zuora_emissions = []
        end

        payload = {
          is_stafftools_route: true,
          slug: this_business.slug,
          zuoraEmissions: zuora_emissions,
        }

        return render json: { payload: payload }, status: 200
      end

      format.html do
        payload = {
          is_stafftools_route: true,
          slug: this_business.slug,
        }

        return render_react_app payload: payload, page_data: { selected_link: :business_billing_vnext_zuora_emissions }, title: "Zuora Emissions"
      end
    end
  end

  private

  sig do
    params(
      year: String,
      month: String,
      day: String,
    )
    .returns(T.any(T::Array[T::Hash[Symbol, T.untyped]], ::Billing::Platform::Api::Error))
  end
  def fetch_zuora_emissions(year, month, day)
    zuora_emissions = billing_platform_client.get_zuora_emissions(
      customer_id: this_business.customer_id,
      year: year,
      month: month,
      day: day
    )

    if zuora_emissions.is_a?(::Billing::Platform::Api::Error)
      zuora_emissions
    else
      zuora_emissions[:emissions]
    end
  end
end
