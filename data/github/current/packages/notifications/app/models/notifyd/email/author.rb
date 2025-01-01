# typed: true
# frozen_string_literal: true

module Notifyd
  module Email
    # NOTE: This is essentially the same as Mobile::Author.
    #   For the moment we duplicate the code until we find a better place for common components
    #   between mobile and email renderers
    module Author
      extend T::Helpers
      abstract!

      sig { abstract.returns(String) }
      def profile_name; end

      sig { overridable.returns(T.nilable(User)) }
      def user
        nil
      end
    end
  end
end
