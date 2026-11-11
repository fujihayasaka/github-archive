# typed: true
# frozen_string_literal: true

module Api::Serializer::OIDCSubjectClaimSerializer
  # Serializer for Actions OIDC subject claim customization at org level,
  # including the use_immutable_subject field.
  def org_oidc_subject_claim_template_serializer_hash(data, options = {})
    return nil unless data[:template]
    {
      include_claim_keys: JSON.parse(data[:template]),
      use_immutable_subject: data[:use_immutable_subject] || false
    }
  end

  # Serializer for Actions OIDC subject claim customization at repo level,
  # including the use_immutable_subject field.
  def repo_oidc_subject_claim_template_serializer_hash(params, options = {})
    return nil unless params.present?

    result = {
      use_default: params[:custom_sub_disabled],
      use_immutable_subject: params[:use_immutable_subject] || false
    }
    if params[:include_claim_keys].present?
      result.update include_claim_keys: JSON.parse(params[:include_claim_keys])
    end
    result[:sub_claim_prefix] = params[:sub_claim_prefix] if params.key?(:sub_claim_prefix)
    result
  end
end
