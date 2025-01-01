# typed: strict
# frozen_string_literal: true

module CustomPropertiesHelper
  include Kernel
  include CustomProperties

  extend self
  extend T::Sig

  sig { params(repo: Repository).returns(T.nilable(T::Hash[Symbol, PropertyValue])) }
  def repo_custom_properties_hash(repo)
    return unless repo.owner&.organization?

    properties = {}
    T.let(repo.custom_properties_values, T::Array[IPropertyValue]).each do |property_value|
      next unless property_value.effective_value
      properties[property_value.property_name.to_sym] = property_value.effective_value
    end
    properties
  end
end
