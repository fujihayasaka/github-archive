# typed: strict
# frozen_string_literal: true

module OctoCore
  module Auth
    # This is a default implementation of the Actor interface. Generally it will mostly
    # be unused in production, but tests should find it quite helpful.
    class DefaultActor
      extend T::Sig
      extend T::Helpers

      include Actor

      sig { params(id: T.nilable(Integer), display_login: T.nilable(String), ability_type: T.nilable(String)).void }
      def initialize(id:, display_login:, ability_type:)
        @id = id
        @display_login = display_login
        @ability_type = ability_type
      end

      sig { override.returns(T.nilable(Integer)) }
      attr_reader :id

      sig { override.returns(T.nilable(String)) }
      attr_reader :display_login

      sig { override.returns(T.nilable(String)) }
      attr_reader :ability_type
    end
  end
end
