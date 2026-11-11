# typed: true
# frozen_string_literal: true

module Api::Serializer::OIDCCustomPropertyInclusionSerializer
  # Serializer for a single OIDC custom property inclusion
  def oidc_custom_property_inclusion_hash(inclusion, options = {})
    return nil unless inclusion

    {
      custom_property_name: inclusion.custom_property_name,
      inclusion_source: inclusion.source_type,
    }
  end
end
