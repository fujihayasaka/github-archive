# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class SponsorshipsAsSponsorable < Platform::Loader
      DEFAULT_ORDER_FIELD = "created_at"
      DEFAULT_ORDER_DIRECTION = "DESC"

      # sponsorable_id - a database ID of a User or Organization to check for sponsorships they are the
      #                  recipient of
      # viewer - the currently authenticated User or integration, if any
      # include_private - whether sponsorships should be included where the sponsor wanted their
      #                   identity kept a secret
      # order_by - a Hash with keys `:field` and `:direction` to order the results by; will be used in SQL directly,
      #            so needs to be a safe value
      # tier - optional SponsorsTier; if given, only sponsorships at this price point will be returned
      # active_only - whether only active sponsorships should be loaded
      sig do
        params(
          sponsorable_id: Integer,
          viewer: T.nilable(T.any(User, Bot)),
          include_private: T::Boolean,
          order_by: T.nilable(T.any(Inputs::SponsorshipOrder, { field: String, direction: String })),
          tier: T.nilable(SponsorsTier),
          active_only: T::Boolean
        ).returns(Promise[T.nilable(T::Array[Sponsorship])])
      end
      def self.load(sponsorable_id, viewer: nil, include_private: false, order_by: nil, tier: nil, active_only: true)
        self.for(viewer, include_private, order_by, tier, active_only).load(sponsorable_id)
      end

      sig do
        params(
          viewer: T.nilable(T.any(User, Bot)),
          include_private: T::Boolean,
          order_by: T.nilable(T.any(Inputs::SponsorshipOrder, { field: String, direction: String })),
          tier: T.nilable(SponsorsTier),
          active_only: T::Boolean
        ).void
      end
      def initialize(viewer, include_private, order_by, tier, active_only)
        @include_private = include_private
        @viewer = viewer
        @order_by = order_by
        @tier = tier
        @active_only = !!active_only
      end

      sig { params(sponsorable_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[Sponsorship]]) }
      def fetch(sponsorable_ids)
        sponsorships_scope = ::Sponsorship.paid.with_user_or_org_sponsorable(sponsorable_ids)
        sponsorships_scope = sponsorships_scope.active if active_only?
        sponsorships_scope = sponsorships_scope.with_tier(tier) if tier.present?
        return {} if sponsorships_scope.empty?

        public_sponsorships = sponsorships_scope.privacy_public
          # Include `filter_spam_for` as the last scope since it will run queries itself on the already-scoped
          # query, so we want that set of sponsorships to be as small as possible:
          .filter_spam_for(viewer)
        public_sponsorships = if !order_by.nil?
          field = T.must(order_by)[:field]
          direction = T.must(order_by)[:direction]
          public_sponsorships.order("sponsorships.#{field} #{direction}")
        elsif viewer && !public_sponsorships.empty?
          public_sponsorships.ranked_by_sponsor(for_user: viewer)
        else
          public_sponsorships.order("sponsorships.#{DEFAULT_ORDER_FIELD} #{DEFAULT_ORDER_DIRECTION}")
        end

        # Append private sponsorships
        sponsorships = if include_private
          # Don't need to order private sponsorships as the sponsor won't be visible to the viewer anyway:
          private_sponsorships = sponsorships_scope.privacy_private
            # Include `filter_spam_for` as the last scope since it will run queries itself on the already-scoped
            # query, so we want that set of sponsorships to be as small as possible:
            .filter_spam_for(viewer)
          public_sponsorships + private_sponsorships
        else
          public_sponsorships
        end

        sponsorships.group_by(&:sponsorable_id)
      end

      private

      sig { returns T.nilable(T.any(User, Bot)) }
      attr_reader :viewer

      sig { returns T.nilable(T.any(Inputs::SponsorshipOrder, { field: String, direction: String })) }
      attr_reader :order_by

      sig { returns T::Boolean }
      attr_reader :include_private

      sig { returns T.nilable(SponsorsTier) }
      attr_reader :tier

      sig { returns T::Boolean }
      def active_only?
        @active_only
      end
    end
  end
end
