# typed: true
# frozen_string_literal: true

class Api::RepositoryOIDCCustomSubClaimTemplate < Api::App
  include OIDCTemplateHelper

  # Gets the oidc sub claim template configuration configured by repo owner
  get "/repositories/:repository_id/actions/oidc/customization/sub", operation_id: "actions/get-custom-oidc-sub-claim-for-repo" do
    repo = find_repo!
    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    # validate parameters
    receive_with_openapi
    configuration = RepositoryActionsOIDCConfig.get_configurations(repo.id)

    custom_sub_disabled = configuration[RepositoryActionsOIDCConfig::KEY_CUSTOM_SUB_CLAIM_DISABLED]
    include_claim_keys = configuration[RepositoryActionsOIDCConfig::KEY_CUSTOM_SUB_CLAIM_TEMPLATE]

    #if the repository owner has not submitted custom claims and has not disallowed custom sub claims, receives the template, if any, defined by the organisation admin.
    if !include_claim_keys.present? && !custom_sub_disabled.nil? && !custom_sub_disabled
      claim_keys = OrganizationOIDCSubClaimTemplate.get_template_for_org(repo.organization_id)
      include_claim_keys = claim_keys.present? ? claim_keys.template : []
    end

    deliver :repo_oidc_custom_sub_template_serializer_hash, {
      custom_sub_disabled: custom_sub_disabled.nil? || custom_sub_disabled.present?,
      include_claim_keys: include_claim_keys.present? ? include_claim_keys : []
    }

  rescue ActiveRecord::ActiveRecordError => e
    deliver_error! 400, message: e
  end

  # Sets or updates the custom sub template
  put "/repositories/:repository_id/actions/oidc/customization/sub", operation_id: "actions/set-custom-oidc-sub-claim-for-repo" do
    started_at = GitHub::Dogstats.monotonic_time
    repo = find_repo!
    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi
    use_default = data["use_default"]
    claim_keys = data["include_claim_keys"]
    org_name = repo.owner_display_login.downcase

    # Data validation. This might throw an exception
    raise ArgumentError.new("Expected a boolean value for the key 'use_default', got #{use_default.class}") unless !!use_default == use_default

    configuration = {
      RepositoryActionsOIDCConfig::KEY_CUSTOM_SUB_CLAIM_DISABLED => use_default,
      RepositoryActionsOIDCConfig::KEY_CUSTOM_SUB_CLAIM_TEMPLATE => []
    }

    # Template data validation. This might throw an exception
    if !use_default.present? && claim_keys.present?
      validate_and_veto_sub_customization_template(claim_keys: claim_keys)
      claim_keys = claim_keys.collect { |e| e ? e.strip : e }
      claim_keys = claim_keys.compact.reject(&:empty?)
      configuration.update include_claim_keys: claim_keys.to_json
    end

    # saving template
    RepositoryActionsOIDCConfig.update_configurations(repo.id, configuration)


    # Record Metric for OIDC Sub Customization
    if use_default
      GitHub.dogstats.distribution("actions_oidc.subject_claim_opt_config.time", GitHub::Dogstats.duration(started_at), tags: ["opt_type:subject_claim.opt_out", "org:#{org_name}"])
    else
      GitHub.dogstats.distribution("actions_oidc.subject_claim_opt_config.time", GitHub::Dogstats.duration(started_at), tags: ["opt_type:subject_claim.opt_in", "org:#{org_name}"])
    end

    deliver_empty status: 201
  rescue ActiveRecord::ActiveRecordError => e
    deliver_error! 400, message: e
  rescue OIDCTemplateHelper::InvalidTemplateError => e
    deliver_error! 400, message: e
  end

end
