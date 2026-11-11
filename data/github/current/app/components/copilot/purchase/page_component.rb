# typed: strict
# frozen_string_literal: true

module Copilot
  module Purchase
    class PageComponent < Primer::Box
      include Copilot::Purchase::Helpers

      sig { returns(T.any(::Organization, ::Business)) }
      attr_reader :selected_account

      sig { params(selected_account: T.any(::Organization, ::Business), system_arguments: T::Hash[Symbol, T.any(Symbol, Integer)]).void }
      def initialize(selected_account:, **system_arguments)
        super(**system_arguments)
        @selected_account = selected_account
      end
    end
  end
end
