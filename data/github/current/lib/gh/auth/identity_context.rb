# typed: strict
# frozen_string_literal: true

module GH
  module Auth
    # Objects which implement this interface provide access to the current
    # actor and other identity information about the entity taking action.
    module IdentityContext
      autoload :ValueContext, "gh/auth/identity_context/value_context"

      extend T::Helpers

      abstract!

      # The actor taking the action. Typically this is implemented by
      # the current user, but in some cases it may be a bot or other agent.
      sig { abstract.returns(T.nilable(Actor)) }
      def domain_actor; end

      sig { returns(String) }
      def hash_key
        "#{domain_actor&.id}"
      end
    end
  end
end
