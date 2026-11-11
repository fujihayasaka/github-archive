# typed: strict
# frozen_string_literal: true

module GH
  module Interfaces
    module DefaultBranch
      extend T::Helpers
      interface!

      sig { abstract.returns(String) }
      def default_branch; end
    end
  end
end
