# typed: false
# frozen_string_literal: true

module Api::App::OIDCTemplateHelper
  class InvalidTemplateError < StandardError; end

  CLAIM_KEYS_SIZE_LIMIT = 512
  REPO_PROPERTY_CLAIM_PREFIX = "repo_property_"
  # Supported list of claims can be found here https://token.actions.githubusercontent.com/.well-known/openid-configuration
  SUPPORTED_CLAIM_KEYS = %w(actor actor_id aud base_ref check_run_id context environment environment_node_id event_name head_ref iss job_workflow_ref job_workflow_sha ref ref_type repo repository repository_id repository_owner repository_owner_id repository_visibility runner_environment run_attempt run_id run_number workflow workflow_ref workflow_sha)

  def construct_configuration_from_inputs(claim_keys:, use_default:, repo:)
    configuration = {
      RepositoryActionsOIDCConfig::KEY_CUSTOM_SUB_CLAIM_DISABLED => use_default,
      RepositoryActionsOIDCConfig::KEY_CUSTOM_SUB_CLAIM_TEMPLATE => []
    }

    if !use_default.present? && claim_keys.present?
      validate_and_veto_sub_customization_template(claim_keys: claim_keys, org: repo.organization, enterprise: repo.organization&.business)
      claim_keys = format_claim_keys_for_template(claim_keys)
      configuration.update include_claim_keys: claim_keys.to_json
    end

    configuration
  end

  # Scrub the comma separated list, e.g. "a, b, " => "a,b"
  def format_claim_keys_for_template(claim_keys)
    claim_keys.collect { |e| e ? e.strip : e }.compact.reject(&:empty?)
  end

  def validate_and_veto_sub_customization_template(claim_keys:, org: nil, enterprise: nil)
    # Template data validation phase 1
    begin
      if !claim_keys.kind_of?(Array)
        raise InvalidTemplateError.new "Expected a string array of claim keys, got #{claim_keys.class}"
      elsif !claim_keys.present?
        raise InvalidTemplateError.new "Expected a string array of claim keys, got an empty array"
      end
    end

    begin
      unique_claims = claim_keys.uniq { |e| e.downcase }
      if unique_claims.length != claim_keys.length
        raise InvalidTemplateError.new "The template has one or more duplicate claim keys"
      end
    end

    begin
      if claim_keys.to_json.length > CLAIM_KEYS_SIZE_LIMIT
        raise InvalidTemplateError.new "The template is too large, the maximum size is #{CLAIM_KEYS_SIZE_LIMIT} characters"
      end
    end

    # Validate claim_keys against supported claim keys
    begin
      claim_keys = claim_keys.collect { |e| e ? e.strip : e }

      if org&.feature_flag_enabled?(:actions_oidc_custom_repo_properties, default: false) ||
         enterprise&.feature_flag_enabled?(:actions_oidc_custom_repo_properties, default: false)
        # Separate repo_property claims from standard claims
        repo_property_claims = claim_keys.select { |key| key&.start_with?(REPO_PROPERTY_CLAIM_PREFIX) }
        standard_claims = claim_keys - repo_property_claims

        # Validate standard claims against supported claim keys
        if !(standard_claims - SUPPORTED_CLAIM_KEYS).empty?
          raise InvalidTemplateError.new "The template has one or more unsupported claim keys."
        end

        # Validate repo_property claims are opted-in for OIDC inclusion
        validate_repo_property_claims(repo_property_claims, org: org, enterprise: enterprise)
      else
        # Original behavior - all claims must be in SUPPORTED_CLAIM_KEYS
        if !(claim_keys - SUPPORTED_CLAIM_KEYS).empty?
          raise InvalidTemplateError.new "The template has one or more unsupported claim keys."
        end
      end
    end
  end

  private

  def validate_repo_property_claims(repo_property_claims, org:, enterprise:)
    return if repo_property_claims.empty?

    if org.nil?
      raise InvalidTemplateError.new "Repository property claims require an organization context for validation."
    end

    # Get opted-in property names for this org/enterprise
    opted_in_inclusions = OIDCCustomPropertyInclusion.repo_property_inclusions_for_organization_and_enterprise(
      org.id,
      enterprise&.id
    )
    opted_in_property_names = opted_in_inclusions.pluck(:custom_property_name).to_set

    # Extract property names from claim keys (remove the prefix)
    requested_property_names = repo_property_claims.map { |claim| claim.delete_prefix(REPO_PROPERTY_CLAIM_PREFIX) }

    # Check if all requested properties are opted-in
    not_opted_in = requested_property_names.reject { |prop_name| opted_in_property_names.include?(prop_name) }

    if not_opted_in.any?
      raise InvalidTemplateError.new "The following repository properties are not opted-in for OIDC token inclusion: #{not_opted_in.join(', ')}"
    end
  end
end
