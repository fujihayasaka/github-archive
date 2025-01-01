# typed: true
# frozen_string_literal: true

module GitHub
  module Validations
    class BytesizeValidator < ActiveModel::Validations::LengthValidator

      def validate_each(record, attribute, value)
        value_bytesize = value.respond_to?(:bytesize) ? value.bytesize : value.to_s.bytesize

        CHECKS.each do |key, validity_check|
          next unless check_value = options[key]
          next unless record.changed.include?(attribute.to_s) || record.changed.include?(record.attribute_aliases[attribute.to_s])
          next if value_bytesize.send(validity_check, check_value)

          errors_options = options.except(*RESERVED_OPTIONS)
          errors_options[:count] = check_value

          default_message = message(key, options)
          errors_options[:message] ||= default_message if default_message

          record.errors.add(attribute, errors_options[:message], **errors_options)
        end
      end

      private

      def message(key, options)
        if key == :maximum
          # UTF-8 characters can be up to 4 bytes long
          "is too long (maximum is #{options[:maximum] / 4} characters)"
        else
          MESSAGES[key]
        end
      end

    end
  end
end
