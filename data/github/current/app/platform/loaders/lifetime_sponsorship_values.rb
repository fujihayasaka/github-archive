# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class LifetimeSponsorshipValues < Platform::Loader
      extend T::Sig

      sig do
        params(
          sponsorable_id: Integer,
          viewer: T.nilable(T.any(User, Bot))
        ).returns(Promise[T.nilable(T::Hash[Integer, Billing::Money])])
      end
      def self.load(sponsorable_id, viewer: nil)
        self.for(viewer: viewer).load(sponsorable_id)
      end

      sig { params(viewer: T.nilable(T.any(User, Bot))).void }
      def initialize(viewer:)
        @viewer = viewer
      end

      sig { params(sponsorable_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Hash[Integer, Billing::Money]]) }
      def fetch(sponsorable_ids)
        Sponsors::LifetimeSponsorshipValuesLoader.call(sponsorable_ids: sponsorable_ids, viewer: @viewer)
      end
    end
  end
end
