# typed: strict
# frozen_string_literal: true

module OctoCore
  module Api
    module ActiveModelErrorConverter
      extend T::Sig

      ERROR_MAP = T.let(
        {
          "has already been taken" => "already_exists",
          "is invalid" => "invalid",
          "can't be blank" => "missing_field",
        }.freeze,
        T::Hash[String, String]
      )

      sig do
        params(validation_errors: ActiveModel::Errors, resource: T.nilable(T.any(String, Symbol)))
        .returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def self.convert_error(validation_errors, resource = nil)
        errors = []
        resource = resource&.to_s
        resource ||= validation_errors.instance_variable_get(:@base).class.name
        opt = { resource: resource }
        validation_errors.each do |error|
          if error.is_a?(Array)
            key = error[0]
            message = error[1]
          else
            key = error.attribute
            message = error.message
          end

          if code = ERROR_MAP[message]
            errors << opt.merge(code: code, field: key)
          else
            if key.to_s == "base"
              errors << opt.merge(code: :custom, message: message)
            else
              errors << opt.merge(code: :custom, field: key, message: "#{key} #{message}")
            end
          end
        end
        errors
      end
    end
  end
end
