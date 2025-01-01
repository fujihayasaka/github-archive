# typed: false
# frozen_string_literal: true

module Platform
  module UserErrors
    # A mixin for `GraphQL::Schema::Mutation` which will run
    # `UserError::VerifyPath` before returning a result.
    #
    # It can be configured to raise errors or not by setting
    # `MyMutation.raise_on_invalid_path = true|false`.
    #
    # Prepend this module to get the resolve wrapping behavior.
    # @see Mutations::Base.error_fields for how this is added to our mutations
    module VerifyPathAfterResolve
      # Wrap the mutation's resolve method with error path checking.
      def resolve(**args)
        result = super
        Promise.resolve(result).then do |result_hash|
          # If the result has `user_errors` in it, make sure that
          # their `path` entries correspond to real inputs:
          UserErrors::VerifyPath.verify_user_errors_and_scrub_invalid(
            result_hash,
            self.class,
            context,
          )
          result_hash
        end
      end
    end
  end
end
