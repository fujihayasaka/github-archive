# typed: true
# frozen_string_literal: true

module SCIM
  # A helper class for representing Scim errors. Used for serializing
  # result responses.
  class ErrorResponse
    # https://tools.ietf.org/html/rfc7644#section-3.12
    SCIM_TYPES = %w(
      invalidFilter
      tooMany
      uniqueness
      mutability
      invalidSyntax
      invalidPath
      noTarget
      invalidValue
      invalidVers
      sensitive
    )

    attr_reader :status, :scim_type, :detail

    def initialize(status:, scim_type: nil, detail: nil)
      @status = status
      @scim_type = scim_type
      @detail = detail

      validate_scim_type if scim_type
    end

    private

    def validate_scim_type
      unless SCIM_TYPES.include?(scim_type)
        raise ArgumentError, "Invalid scim_type specified."
      end

      unless (400...500).include?(status)
        raise ArgumentError, "scim_type may only be specified for 4XX responses."
      end
    end
  end
end
