# typed: true
# frozen_string_literal: true

module Api::Serializer::OrganizationOIDCCustomSubTemplateSerializer
  # Template to json serializer for Actions OIDC subject claim customization at org level
  def org_oidc_custom_sub_template_serializer_hash(claim_keys_str, options = {})
    return nil unless claim_keys_str
    {
      include_claim_keys: JSON.parse(claim_keys_str)
    }
  end

  # Template to json serializer for Actions OIDC subject claim customization at repo level
  def repo_oidc_custom_sub_template_serializer_hash(params, options = {})
    return nil unless params.present?

    result = {
      use_default: params[:custom_sub_disabled]
    }
    if params[:include_claim_keys].present?
      result.update include_claim_keys: JSON.parse(params[:include_claim_keys])
    end
    result
  end
end
