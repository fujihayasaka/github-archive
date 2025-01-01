# typed: false
# frozen_string_literal: true

module Api::App::OIDCTemplateHelper
  class InvalidTemplateError < StandardError; end

  CLAIM_KEYS_SIZE_LIMIT = 512
  # Supported list of claims can be found here https://token.actions.githubusercontent.com/.well-known/openid-configuration
  SUPPORTED_CLAIM_KEYS = %w(actor actor_id aud base_ref context environment environment_node_id event_name head_ref iss job_workflow_ref job_workflow_sha ref ref_type repo repository repository_id repository_owner repository_owner_id repository_visibility runner_environment run_attempt run_id run_number workflow workflow_ref workflow_sha)

  def validate_and_veto_sub_customization_template(claim_keys:)
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
      if !(claim_keys - SUPPORTED_CLAIM_KEYS).empty?
        raise InvalidTemplateError.new "The template has one or more unsupported claim keys."
      end
    end
  end
end
