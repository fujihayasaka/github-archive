# typed: strict
# frozen_string_literal: true

class RepoPropertiesConfig
  include CustomPropertiesCore::ICustomPropertiesConfig

  sig { override.returns(ValueModelImpl) }
  def value_class
    CustomPropertyValue
  end

  sig { override.returns(DefinitionModelImpl) }
  def definition_class
    CustomPropertyDefinition
  end

  sig { override.params(source: CustomPropertiesCore::IPropertySource).returns(CustomPropertiesCore::PropertyLimits) }
  def limits(source)
    if extended_limits_enabled(source)
      CustomPropertiesCore::PropertyLimits.new(
        max_property_value_length: 200,
        max_allowed_values_count: 1_500
      )
    else
      super(source)
    end
  end

  sig { override.params(source: CustomPropertiesCore::IPropertySource).returns(T.nilable(T::Hash[T.any(String, Symbol), String])) }
  def additional_tracking_tags(source)
    { extended_limits: "#{extended_limits_enabled(source)}" }
  end

  sig { params(source: CustomPropertiesCore::IPropertySource).returns(T::Boolean) }
  def extended_limits_enabled(source)
    if source.is_a?(Organization) && source.business.present?
      FeatureFlag.vexi.enabled?(:repo_custom_properties_extended_limits, source.business, default: false)
    else
      FeatureFlag.vexi.enabled?(:repo_custom_properties_extended_limits, source, default: false)
    end
  end
end
