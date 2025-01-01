# typed: true
# frozen_string_literal: true

module SettingsCollection
  # An ActiveModel-compatible class containing arbitrary user settings backed
  # by a JSON column.
  class CollectionModel
    include ActiveModel::Model
    include ActiveModel::Attributes
    include ActiveModel::Serializers::JSON

    # This makes for concise printing for `puts`, etc
    def inspect
      "#<#{self.class.name} #{attributes}>"
    end

    # Define equality for better dirty tracking
    def ==(other)
      return super unless other.instance_of?(self.class)

      attributes == other.attributes
    end

    # Updates the given attribute value and runs validations, returning
    # the #ActiveModel::Errors object.
    # Raises ArgumentError if the attribute is not defined
    def validate_update(attr:, value:)
      raise ArgumentError, "attr must be an attribute of #{self.class.name}" unless self.class.has_attribute?(attr)
      public_send("#{attr}=", value)
      validate
      errors
    end

    def self.from_json(value)
      case value
      when String
        new.from_json(value)
      when Hash, nil
        new(value)
      end
    end

    def self.is_default_value?(key, value)
      value == default_value(key)
    end

    # This uses the _default_attributes method, which is populated as part of the `attribute`
    # [class macro call](https://github.com/rails/rails/blob/83217025a171593547d1268651b446d3533e2019/activemodel/lib/active_model/attributes.rb#L19)
    # If that makes us queasy we can write our own class macro that wraps `attribute`, and store the default value
    # in a location we control
    def self.default_value(key)
      default = _default_attributes[key.to_s]
      if default.is_a?(ActiveModel::Attribute::UserProvidedDefault)
        default.value_before_type_cast
      else
        nil
      end
    end

    # Check if the given attribute has been defined
    def self.has_attribute?(attr)
      attribute_names.include?(attr.to_s)
    end
  end
end
