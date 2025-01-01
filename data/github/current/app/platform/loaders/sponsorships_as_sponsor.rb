# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class SponsorshipsAsSponsor < Platform::Loader
      DEFAULT_ORDER_FIELD = "created_at"
      DEFAULT_ORDER_DIRECTION = "DESC"

      # sponsor_id - database ID of a User or Organization to check for sponsorships they receive credit
      #              for as the sponsor
      # viewer - the currently authenticated User or integration, if any
      # order_by - a Hash with keys `:field` and `:direction` to order the results by; will be used in SQL directly,
      #            so needs to be a safe value
      # sponsorable_ids - an Array of Integer database IDs of Users or Organizations to filter the results by, to
      #                   return only sponsorships received by the specified users and orgs
      # active_only - Boolean indicating whether only active sponsorships should be loaded
      sig do
        params(
          sponsor_id: Integer,
          viewer: T.nilable(T.any(User, Bot)),
          order_by: T.nilable(T.any(Inputs::SponsorshipOrder, { field: String, direction: String })),
          sponsorable_ids: T::Array[Integer],
          active_only: T::Boolean
        ).returns(Promise[T.nilable(T::Array[Sponsorship])])
      end
      def self.load(sponsor_id, viewer: nil, order_by: nil, sponsorable_ids: [], active_only: true)
        self.for(viewer, order_by, sponsorable_ids, active_only, **{}).load(sponsor_id)
      end

      sig do
        params(
          viewer: T.nilable(T.any(User, Bot)),
          order_by: T.nilable(T.any(Inputs::SponsorshipOrder, { field: String, direction: String })),
          sponsorable_ids: T::Array[Integer],
          active_only: T::Boolean
        ).void
      end
      def initialize(viewer, order_by, sponsorable_ids, active_only)
        @viewer = viewer
        @order_by = order_by
        @sponsorable_ids = sponsorable_ids
        @active_only = active_only
      end

      sig { params(sponsor_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[Sponsorship]]) }
      def fetch(sponsor_ids)
        linked_orgs_hash = linked_organizations_hash(sponsor_ids)
        linked_sponsor_ids = sponsor_ids.map { |id| linked_orgs_hash[id] }.compact
        all_sponsor_ids = sponsor_ids + linked_sponsor_ids

        sponsorships = ::Sponsorship
          .from_sponsor(all_sponsor_ids)
          .sponsor_visible_to(viewer)
          .listing_approved
          .paid
          # Include `filter_spam_for` as the last scope since it will run queries itself on the already-scoped
          # query, so we want that set of sponsorships to be as small as possible:
          .filter_spam_for(viewer)

        sponsorships = sponsorships.active if active_only?
        sponsorships = sponsorships.with_user_or_org_sponsorable(sponsorable_ids) if sponsorable_ids.present?

        order_sponsorships(sponsorships).group_by do |sponsorship|
          parent_sponsor_id = linked_orgs_hash.key(sponsorship.sponsor_id)
          parent_sponsor_id || sponsorship.sponsor_id
        end
      end

      private

      sig { returns T.nilable(T.any(User, Bot)) }
      attr_reader :viewer

      sig { returns T.nilable(T.any(Inputs::SponsorshipOrder, { field: String, direction: String })) }
      attr_reader :order_by

      sig { returns T::Array[Integer] }
      attr_reader :sponsorable_ids

      sig { params(sponsor_ids: T::Array[Integer]).returns(T::Hash[Integer, Integer]) }
      def linked_organizations_hash(sponsor_ids)
        ::OrganizationProfile
          .where(organization_id: sponsor_ids)
          .with_sponsoring_linked_organization_id
          .pluck(:organization_id, :sponsoring_linked_organization_id)
          .to_h
      end

      sig { params(sponsorships: ::ActiveRecord::Relation).returns(::ActiveRecord::Relation) }
      def order_sponsorships(sponsorships)
        if order_by || !viewer
          sponsorships.order("sponsorships.#{order_field} #{order_direction}")
        elsif sponsorships.respond_to?(:ranked_by_sponsorable)
          T.unsafe(sponsorships).ranked_by_sponsorable(for_user: viewer)
        else
          sponsorships
        end
      end

      sig { returns String }
      def order_field
        order_by ? T.must(order_by)[:field] : DEFAULT_ORDER_FIELD
      end

      sig { returns String }
      def order_direction
        order_by ? T.must(order_by)[:direction] : DEFAULT_ORDER_DIRECTION
      end

      sig { returns T::Boolean }
      def active_only?
        @active_only
      end
    end
  end
end
