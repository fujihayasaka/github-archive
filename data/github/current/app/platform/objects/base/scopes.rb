# typed: true
# frozen_string_literal: true
module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module Scopes
        # @return [nil, Array<String>] The list of required scopes, if any are required.
        def minimum_accepted_scopes(scopes = nil)
          if scopes
            @minimum_accepted_scopes = scopes
          end
          @minimum_accepted_scopes
        end

        # @return [Boolean] if true, this mutation doesn't require any OAuth scopes
        def scopeless_tokens_as_minimum?
          !!@scopeless_tokens_as_minimum
        end

        # Use this in a definition to set the value to true
        # @see {.scopeless_tokens_as_minimum?} to read the value
        def scopeless_tokens_as_minimum
          @scopeless_tokens_as_minimum = true
        end
      end
    end
  end
end
