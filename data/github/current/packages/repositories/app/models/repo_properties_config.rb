# typed: strict
# frozen_string_literal: true

class RepoPropertiesConfig
  include ::CustomProperties::ICustomPropertiesConfig

  sig { override.returns(ValueModelImpl) }
  def value_class
    CustomPropertyValue
  end

  sig { override.returns(DefinitionModelImpl) }
  def definition_class
    CustomPropertyDefinition
  end
end
