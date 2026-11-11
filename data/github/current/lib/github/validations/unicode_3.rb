# typed: true
# frozen_string_literal: true

module GitHub
  module Validations
    class Unicode3Validator < ActiveModel::EachValidator
      # For now, this is so we can make sure that content doesn't contain any
      # unicode codepoints outside of Unicode 3.0 as (at the time of writing)
      # we are in a pickle with our MySQL encodings.
      #
      # See https://github.com/github/github/issues/1299 for more info.
      #
      # This means we need to ensure no codepoints above 0xffff exist or they
      # will be silently truncated without warning and the record will be
      # saved anyway.
      #
      # This should be setup as an explicit validation on models that include
      # this as follows:
      #
      # validates_unicode_3 :body
      #
      ERROR_MESSAGE = "doesn't accept 4-byte Unicode"

      def validate_each(record, attribute, value)
        if value.is_a?(String) && !GitHub::UTF8.valid_unicode3?(value)
          record.errors.add(attribute, ERROR_MESSAGE)
        end
      end
    end
  end
end
