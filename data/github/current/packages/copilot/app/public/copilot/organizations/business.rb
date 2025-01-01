# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Business
      extend T::Helpers
      extend T::Sig
      include Copilot::Helpers
      include Copilot::Organizations::Signatures

      abstract!

      sig { override.returns(T::Boolean) }
      def ghec?
        copilot_business != nil
      end

      sig { override.returns(T.nilable(Copilot::Business)) }
      def copilot_business
        @copilot_business ||= T.let(
          if business = organization_object.business
            Copilot::Business.new(business)
          end,
          T.nilable(Copilot::Business),
        )
      end
    end
  end
end
