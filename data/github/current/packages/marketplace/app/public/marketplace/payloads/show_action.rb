# typed: strict
# frozen_string_literal: true

module Marketplace
  module Payloads
    class ShowAction
      extend T::Sig
      include GitHub::Memoizer
      include ::Search::RepositoryActionIconHelper
      include UrlHelpers

      sig { returns(RepositoryAction) }
      attr_reader :repository_action

      sig { params(repository_action: RepositoryAction).void }
      def initialize(repository_action:)
        @repository_action = repository_action
      end

      sig do
        returns({
          action: Marketplace::Types::SerializedActionListing,
        })
      end
      def call
        {
          action: Marketplace::Serializers::Action.serialize_model(repository_action)
        }
      end
    end
  end
end
