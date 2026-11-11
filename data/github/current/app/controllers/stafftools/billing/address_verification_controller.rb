# typed: strict
# frozen_string_literal: true

class Stafftools::Billing::AddressVerificationController < StafftoolsController
  before_action :ensure_billing_enabled
  layout "stafftools"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Ballast,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:index]

  sig { void }
  def index
    lookup_result = nil
    raw_response = nil

    # Process address verification if params are present
    if address_params_present?
      permitted = address_verification_params
      street = T.cast(permitted[:street], String)
      city = T.cast(permitted[:city], String)
      region = T.cast(permitted[:region], String)
      postal_code = T.cast(permitted[:postal_code], String)
      currency_code = T.cast(permitted[:currency_code] || "USD", String)
      billing_country_code = T.cast(permitted[:billing_country_code] || "US", String)

      if missing_required_fields?(street, city, region, postal_code)
        flash.now[:error] = "All address fields are required"
      else
        begin
          client = Taxamo::Client.new(private_token: GitHub.taxamo_api_private_token)
          lookup_result = client.address_lookup(
            street,
            city,
            region,
            postal_code,
            currency_code: currency_code,
            billing_country_code: billing_country_code
          )
          raw_response = lookup_result.raw_response
        rescue => e
          flash.now[:error] = "Error verifying address: #{e.message}"
        end
      end
    end

    render "stafftools/billing/address_verification/index", locals: {
      lookup_result: lookup_result,
      raw_response: raw_response
    }
  end

  private

  sig { returns(T::Boolean) }
  def address_params_present?
    params[:street].present? || params[:city].present? || params[:region].present? || params[:postal_code].present?
  end

  sig { returns(ActionController::Parameters) }
  def address_verification_params
    params.permit(
      :street,
      :city,
      :region,
      :postal_code,
      :currency_code,
      :billing_country_code,
      :authenticity_token
    )
  end

  sig do
    params(
      street: String,
      city: String,
      region: String,
      postal_code: String
    ).returns(T::Boolean)
  end
  def missing_required_fields?(street, city, region, postal_code)
    [street, city, region, postal_code].any? { |field| field.blank? }
  end
end
