# typed: true
# frozen_string_literal: true

class Issue::Adapter::GitCommitCertificateAttributesAdapter < Issue::Adapter::Base
  attr_reader :common_name, :email_address, :organization, :organization_unit

  def initialize(context, attributes:)
    super(context)

    @common_name = attributes["CN"]
    @email_address = attributes["emailAddress"]
    @organization = attributes["O"]
    @organization_unit = attributes["OU"]
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
