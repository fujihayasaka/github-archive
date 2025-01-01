# typed: strict
# frozen_string_literal: true

module GH
  module Auth
    module Actor
      extend T::Helpers

      interface!

      include Kernel

      sig { abstract.returns(T.nilable(Integer)) }
      def id; end

      sig { abstract.returns(T.nilable(String)) }
      def display_login; end

      sig { abstract.returns(T.nilable(String)) }
      def ability_type; end
    end
  end
end
