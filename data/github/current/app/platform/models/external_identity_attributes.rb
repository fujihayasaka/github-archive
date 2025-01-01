# typed: true
# frozen_string_literal: true

class Platform::Models::ExternalIdentityAttributes
  attr_reader :identity
  attr_reader :attributes_type

  def initialize(identity, as:)
    @identity = identity
    @attributes_type = as
  end

  def platform_type_name
    case attributes_type
    when :scim
      "ExternalIdentityScimAttributes"
    when :saml
      "ExternalIdentitySamlAttributes"
    else
      raise Platform::Errors::Internal, "Unexpected attributes_type: #{attributes_type.inspect}"
    end
  end
end
