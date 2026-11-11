# frozen_string_literal: true

class ClassValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    allowed_class = options[:with] || options[:is]
    allowed_classes = allowed_class ? [allowed_class] : options[:in] || []
    allowed_classes << NilClass if options[:allow_nil]
    actual_class = value.class

    return if allowed_classes.include?(actual_class)

    record.errors.add(attribute, :invalid_class, {
      allowed_classes: allowed_classes,
      actual_class: actual_class,
    })
  end
end
