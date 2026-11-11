# typed: true
# frozen_string_literal: true

class Api::OrganizationOIDCCustomSubClaimTemplateApi < Api::App
  include OIDCTemplateHelper

  # Gets the configured custom sub template for an organization. Returns template or nil when there is no template
  get "/organizations/:organization_id/actions/oidc/customization/sub", operation_id: "oidc/get-oidc-custom-sub-template-for-org" do
    org = find_org!

    control_access :read_org_oidc_sub_template,
      forbid: true,
      allow_integrations: true,
      resource: org,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    claim_keys = OrganizationOIDCSubClaimTemplate.get_template_for_org(org.id)
    if !claim_keys.present?
      deliver_error! 404, message: "No Actions OIDC custom sub claim template found for the organization #{org.display_login}"
    elsif org.feature_flag_enabled?(:actions_oidc_immutable_subject_claim, default: false)
      deliver :org_oidc_subject_claim_template_serializer_hash, {
        template: claim_keys.template,
        use_immutable_subject: claim_keys.use_immutable_subject
      }
    else
      deliver :org_oidc_custom_sub_template_serializer_hash, claim_keys.template
    end
  rescue ActiveRecord::ActiveRecordError => e
    deliver_error! 400, message: e
  end

  # Sets or updates the custom sub template
  put "/organizations/:organization_id/actions/oidc/customization/sub", operation_id: "oidc/update-oidc-custom-sub-template-for-org" do
    org = find_org!

    control_access :write_org_oidc_sub_template,
      forbid: true,
      allow_integrations: true,
      resource: org,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi

    # saving template
    if org.feature_flag_enabled?(:actions_oidc_immutable_subject_claim, default: false)
      unless data.key?("include_claim_keys") || data.key?("use_immutable_subject")
        deliver_error! 422, message: "Request body must include at least one of: include_claim_keys, use_immutable_subject"
      end

      claim_keys = data["include_claim_keys"]

      if claim_keys
        # Template data validation. This might throw an exception
        validate_and_veto_sub_customization_template(claim_keys: claim_keys, org: org, enterprise: org.business)

        # The list is valid, scrub the comma separated list, e.g. "a, b, " => "a,b"
        claim_keys = claim_keys.collect { |e| e ? e.strip : e }
        claim_keys = claim_keys.compact.reject(&:empty?)

        OrganizationOIDCSubClaimTemplate.create_or_update_template(org.id, claim_keys.to_json, use_immutable_subject: data["use_immutable_subject"])
      else
        # Only updating use_immutable_subject, preserve existing claim keys
        existing = OrganizationOIDCSubClaimTemplate.get_template_for_org(org.id)
        existing_template = existing&.template || [].to_json
        OrganizationOIDCSubClaimTemplate.create_or_update_template(org.id, existing_template, use_immutable_subject: data["use_immutable_subject"])
      end
    else
      claim_keys = data["include_claim_keys"]

      unless claim_keys
        deliver_error! 422, message: "Required parameter missing: include_claim_keys"
      end

      # Template data validation. This might throw an exception
      validate_and_veto_sub_customization_template(claim_keys: claim_keys, org: org, enterprise: org.business)

      # The list is valid, scrubb the comma separated list, e.g. "a, b, " => "a,b"
      claim_keys = claim_keys.collect { |e| e ? e.strip : e }
      claim_keys = claim_keys.compact.reject(&:empty?)

      OrganizationOIDCSubClaimTemplate.create_or_update_template(org.id, claim_keys.to_json)
    end
    deliver_empty status: 201
  rescue ActiveRecord::ActiveRecordError => e
    deliver_error! 400, message: e
  rescue OIDCTemplateHelper::InvalidTemplateError => e
    deliver_error! 400, message: e
  end
end
