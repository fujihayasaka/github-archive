# typed: true
# frozen_string_literal: true

# Formats API errors into a consistent response format.
# This module helps standardize error handling across different validation types:
# - Parameter validation (missing/invalid parameters)
# - Business logic validation (state-based rules)
# - Model validation (ActiveRecord validations)
#
# The module also handles mapping between internal model field names and API parameter names.
#
# Usage:
#   1. Include this module in your API class
#   2. Define field mappings if model fields differ from API parameters
#   3. Use the error formatting helpers:
#      - validate_params_present: Check required parameters
#      - api_domain_error: Add custom business/application-level logic errors
#      - format_model_errors: Format ActiveRecord validation errors
#
# Example:
#   For a SAML Provider endpoint that accepts:
#   POST /internal/azure/copilot/emu/enterprises/:enterprise_id/saml
#   {
#     "login_url": "https://example.com",
#     "entra_identifier": "some-id",
#     "certificate": "cert-data"
#   }
#
#   But maps to model fields:
#   Business::SamlProvider
#     - sso_url
#     - issuer
#     - idp_certificate
#
#   Usage in endpoint:
#     FIELD_MAPPINGS = {
#       "Business::SamlProvider" => {
#         "sso_url" => "login_url",
#         "issuer" => "entra_identifier",
#         "idp_certificate" => "certificate"
#       }
#     }.freeze
#
#     post "/internal/azure/.../saml" do
#       all_errors = []
#
#       # 1. Parameter validation
#       param_errors = validate_params_present(body_params, %w[login_url certificate])
#       all_errors.concat(param_errors)
#
#       # 2. Business logic validation
#       if immutable_login_url
#         all_errors << api_domain_error(field: "login_url", message: "Cannot change login_url when external identities exist")
#       end
#
#       # 3. Model validation
#       unless provider.save
#         all_errors.concat(format_model_errors(provider, FIELD_MAPPINGS))
#       end
#
#       # Return all errors at once
#       if all_errors.any?
#         deliver_error! 400, { errors: all_errors }
#       end
#     end
#
module Api::App::ErrorFormatting
  extend ActiveSupport::Concern

  def validate_params_present(params, required_fields)
    required_fields.filter_map do |field|
      if params[field].blank?
        api_domain_error(field: field, message: "is required")
      end
    end
  end

  def api_domain_error(field: nil, message:)
    error = {}
    error[:field] = field unless field.nil?
    error[:message] = message
    error
  end

  def format_model_errors(model, field_mappings = {})
    model.errors.group_by(&:attribute).flat_map do |attribute, model_errors|
      model_errors.map do |error|
        api_domain_error(field: map_field_name(model, attribute, field_mappings), message: error.message)
      end
    end
  end

  private

  def map_field_name(model, field, field_mappings)
    mapping = field_mappings.dig(model.class.name, field.to_s)
    mapping || field.to_s
  end
end
