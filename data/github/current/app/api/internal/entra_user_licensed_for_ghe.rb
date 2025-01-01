# typed: true
# frozen_string_literal: true

# This API is called from azure to verify if an entra user has a GHE license for the purpose of giving them
# access to Azure DevOps usage, which is bundled with the GHE license.

class Api::Internal::EntraUserLicensedForGhe < Api::Internal
  include Licensing::Licensify

  def externally_accessible?
    # API should be accessible to Azure
    true
  end

  def require_request_hmac?
    # HMAC keys are stored in "GitHub.api_internal_entra_user_licensed_for_ghe_hmac_keys"
    # which reads "API_INTERNAL_ENTRA_USER_LICENSED_FOR_GHE_HMAC_KEYS" environment variable
    true
  end

  # This is redundant, but will make sure we are OK if the method is removed or renamed in the parent class
  before do
    verify_request_hmac
  end

  def verify_request_hmac
    if !hmac_authenticated_internal_service_request? || GitHub.flipper[:block_entra_user_licensed_for_ghe_requests].enabled?
      headers["X-GLB-Rate-Limit"] = "true"
      headers[GitHub::Middleware::Constants::RETRY_AFTER] = "300"
      deliver_error! 403, message: REQUEST_HMAC_INVALID
    end

    super
  end

  def authenticated_for_private_mode?
    true
  end

  post "/internal/has_ghe_license_by_entra_id", operation_id: :internal do
    @route_owner = "@github/licensing"
    data = JSON.parse(request&.body&.read || "{}")
    entra_object_id = data["entra_object_id"]
    deliver_error! 400, message: "Invalid entra_object_id parameter" unless entra_object_id.present?
    user_ids = ExternalIdentity.where(external_id: entra_object_id).or(ExternalIdentity.where(saml_external_id: entra_object_id)).pluck(:user_id).compact
    business_user_account = BusinessUserAccount.where(user_id: user_ids)

    is_licensed = T.let(false, T::Boolean)
    business_user_account.each do |business_user_account|
      user = business_user_account.user
      next if user.nil?
      global_id = user.to_global_id.to_s
      business = business_user_account.business
      next unless business&.customer_id.present?
      licensify_req = Licensify::Services::V1::GetCustomerLicenseRequest.new(customerId: business.customer_id, licensee: { globalId: global_id }, products: [Licensify::Services::V1::Product::PRODUCT_SDLC])
      licensify_res = licensify_client.get_customer_license(licensify_req)

      next unless licensify_res.error.nil?

      if licensify_res.data.customerLicenses&.any? { |customer_license| customer_license.licenseStatus == :LICENSE_STATUS_ACTIVE }
        is_licensed = true
        break
      end
    end

    result = { licensed: is_licensed }
    deliver_raw result, status: 200
  end
end
