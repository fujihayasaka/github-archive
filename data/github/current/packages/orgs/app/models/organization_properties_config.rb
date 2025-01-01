# typed: strict
# frozen_string_literal: true

class OrganizationPropertiesConfig
  include ::CustomPropertiesCore::ICustomPropertiesConfig

  sig { override.returns(ValueModelImpl) }
  def value_class
    OrganizationCustomPropertyValue
  end

  sig { override.returns(DefinitionModelImpl) }
  def definition_class
    OrganizationCustomPropertyDefinition
  end
end
