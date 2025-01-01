# typed: strict
#frozen_string_literal: true

module Copilot
  module Payloads
    class AdminableAccounts

      include AvatarHelper
      include GitHub::Memoizer

      EntityObj = T.type_alias do
        {
          id: Integer,
          slug: String,
          avatar_url: String,
          type: String
        }
      end

      sig { returns(::User) }
      attr_reader :user

      sig { params(user: ::User).void }
      def initialize(user)
        @user = user
      end

      sig { returns(T::Hash[Symbol, T::Array[T.any(::Organization, ::Business)]]) }
      memoize def to_h
        {
          organizations: adminable_orgs.map { |org| entity_obj(org) },
          businesses: adminable_businesses.map { |business| entity_obj(business) },
        }
      end

      sig { returns(T::Array[EntityObj]) }
      memoize def to_a
        accounts = adminable_orgs.map { |org| entity_obj(org) } + adminable_businesses.map { |business| entity_obj(business) }
        accounts.sort_by { |account| account[:slug].downcase }
      end

      sig { returns(T::Array[::Organization]) }
      memoize def adminable_orgs
        user.organizations.select { |org| org.adminable_by?(user) }
      end

      sig { returns(ActiveRecord::Relation) }
      memoize def adminable_businesses
        user.businesses(membership_type: :admin)
      end

      private

      sig { params(entity: T.any(::Organization, ::Business)).returns(EntityObj) }
      def entity_obj(entity)
        {
          id: entity.id,
          slug: entity.is_a?(::Organization) ? entity.display_login : entity.slug,
          avatar_url: avatar_url_for(entity),
          type: T.must(entity.class.name) == "Business" ? "Enterprise" : "Organization"
        }
      end
    end
  end
end
