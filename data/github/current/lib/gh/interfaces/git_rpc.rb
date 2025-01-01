# typed: strict
# frozen_string_literal: true

module GH
  module Interfaces
    module GitRPC
      extend T::Helpers
      interface!

      sig { abstract.returns(::GitRPC::Client) }
      def rpc; end
    end
  end
end
