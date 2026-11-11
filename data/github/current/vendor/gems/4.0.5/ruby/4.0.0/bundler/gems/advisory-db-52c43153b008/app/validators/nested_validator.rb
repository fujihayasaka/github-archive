# frozen_string_literal: true

class NestedValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, values)
    indexed_values =
      case values
      when Array
        values.map.with_index { |value, index| [index, value] }
      when Hash
        values
      else
        { nil => values }
      end

    indexed_values.each do |index, value|
      # Rails 8 changed the way validation_context works in
      # ActiveModel::Validations.  We previously used a custom
      # variable of the same name in the Publisher model, but it has
      # been renamed to publisher_validation_context.  As a result, we
      # need to check for our renamed variable as well as ActiveRecord's
      # variable.
      if record.respond_to?(:publisher_validation_context)
        next unless value.invalid?(record.publisher_validation_context)
      else
        next unless value.invalid?(record.validation_context)
      end

      value.errors.details.each do |name, details|
        details.each do |detail|
          nesting = index ? [index] : []
          nesting += detail[:nesting] || [name.to_s]
          nested_attribute = attribute.to_s
          nesting.each { |e| nested_attribute << "[#{e}]" }

          record.errors.add(
            attribute,
            :invalid_nested_element,
            nesting: nesting,
            nested_attribute: nested_attribute,
            detail: detail,
          )
        end
      end
    end
  end
end
