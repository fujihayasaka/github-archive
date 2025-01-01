# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class BannerDismissalsByUser < Platform::Loader
      extend T::Sig

      sig do
        params(
          banner_id: T.nilable(Integer),
          user_id: T.nilable(Integer)
        ).returns(Promise[T::Array[EnterpriseBannerDismissal]])
      end
      def self.load(banner_id, user_id)
        self.for(banner_id).load(user_id)
      end

      sig do
        params(
          banner_id: T.nilable(Integer),
          user_ids: T::Array[T.nilable(Integer)]
        ).returns(Promise[T::Array[EnterpriseBannerDismissal]])
      end
      def self.load_all(banner_id, user_ids)
        loader = self.for(banner_id)
        Promise.all(user_ids.map { |id| loader.load(id) })
      end

      sig { params(banner_id: T.nilable(Integer)).void }
      def initialize(banner_id)
        @banner_id = banner_id
      end

      sig do
        params(
          ids: T::Array[T.nilable(Integer)]
        ).returns(T::Hash[Integer, T::Array[EnterpriseBannerDismissal]])
      end
      def fetch(ids)
        EnterpriseBannerDismissal.where(
          enterprise_banner_id: @banner_id,
          user_id: ids
        ).index_by(&:user_id)
      end
    end
  end
end
