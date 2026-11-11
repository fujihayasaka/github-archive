# typed: strict
# frozen_string_literal: true

module GH
  module Interfaces
    module SpokesAPI
      extend T::Helpers
      interface!

      sig { abstract.returns(::SpokesAPI::Client) }
      def spokes_api; end
    end
  end
end
