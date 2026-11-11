# typed: true
# frozen_string_literal: true

module GitHub
  module Validations
    class UnicodeValidator < ActiveModel::EachValidator
      ERROR_MESSAGE = "contains invalid UTF-8 characters"

      # We shouldn't be overriding this because the docs say so, but `blank?`
      # checks will fail on bad unicode data.  Once we can guarantee that all
      # data that comes in to the system is properly encoded, we should remove
      # this method.  IOW, we shouldn't be doing unicode enforcement in the
      # models, it should happen at the application borders.
      #
      # :nodoc:
      def validate(record)
        attributes.each do |attribute|
          value = record.read_attribute_for_validation(attribute)
          next if value.nil? && options[:allow_nil]
          value = validate_each(record, attribute, value)
          next if value.blank? && options[:allow_blank]
        end
      end

      def validate_each(record, attribute, value)
        return if value.nil?

        if value.is_a?(String)
          value.force_encoding("UTF-8") if value.encoding != ::Encoding::UTF_8
          if !value.valid_encoding?
            value.scrub!
            record.errors.add(attribute, ERROR_MESSAGE)
          end
        end

        value
      end
    end
  end
end
