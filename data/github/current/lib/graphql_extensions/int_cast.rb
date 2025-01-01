# typed: false
# frozen_string_literal: true

# patching GraphQL::Client::Schema::ScalarType#cast to break free of GraphQL's 32 bit limitted Int
# see https://github.com/github/issues/issues/1595
module GraphQLExtensions
  module IntCast
    def cast(value, _errors = nil)
      case value
      when NilClass
        nil
      else
        if type.respond_to?(:coerce_isolated_input)
          coerced_value = type.coerce_isolated_input(value)
          # If we are trying to cast a ruby Integer to and back from a graphql Int
          # Just return the integer and ignore the 32 bit limit
          if type == GraphQL::Types::Int && value.is_a?(Integer) && coerced_value.nil?
            value
          else
            coerced_value
          end
        else
          type.coerce_input(value)
        end
      end
    end
  end
end
