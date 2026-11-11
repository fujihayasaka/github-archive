# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Model
      include Kernel
      include Copilot::PolicyInterface
      include Copilot::Policies::Concerns::Mutable

      extend T::Helpers

      interface!

      sig { abstract.returns(T.nilable(Copilot::Types::Models::Publisher)) }
      def publisher; end

      sig { abstract.returns(T.nilable(Copilot::Types::Models::Category)) }
      def category; end

      sig { abstract.params(user: Copilot::User, entity: Copilot::Types::CopilotEntity).returns(Copilot::Types::Models::Serialized) }
      def serialize(user, entity); end
    end
  end
end
