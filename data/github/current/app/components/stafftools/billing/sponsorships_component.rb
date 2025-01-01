# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class SponsorshipsComponent < ApplicationComponent
      extend T::Sig

      # sponsor - a User or Organization
      # active_tab - whether the viewer is viewing current or past sponsorships. Either :past or :current
      sig { params(sponsor: T.nilable(GitHubSponsors::Types::Sponsor), active_tab: Symbol).void }
      def initialize(sponsor:, active_tab: :current)
        @sponsor = sponsor
        @active_tab = active_tab
      end

      private

      sig { returns T::Boolean }
      def render?
        GitHub.sponsors_enabled? && @sponsor.present?
      end

      sig { returns Symbol }
      attr_reader :active_tab

      sig { returns GitHubSponsors::Types::Sponsor }
      def sponsor
        T.must(@sponsor)
      end

      sig { returns T::Array[T.any(Sponsorship, ::Billing::SubscriptionItem)] }
      def sponsorships_to_display
        active_tab?(:current) ? active_sponsorships_and_subscription_items : inactive_sponsorships
      end

      sig { returns T::Array[Sponsorship] }
      memoize def all_sponsorships
        results = sponsor
          .sponsorships_as_sponsor
          .listing_approved
          .preload(:sponsors_listing)

        preloaded_listings = results.map(&:sponsors_listing)
        GitHub::PrefillAssociations.prefill_associations(results,
          { sponsorable: { sponsors_listing: :sponsors_tiers } },
          available_records: preloaded_listings)

        preloaded_listings_and_tiers = preloaded_listings + results.flat_map do |result|
          sponsorable = result.sponsorable
          sponsorable&.sponsors_listing&.sponsors_tiers
        end
        GitHub::PrefillAssociations.prefill_associations(results,
          { tier: { sponsors_listing: :sponsors_tiers } },
          available_records: preloaded_listings_and_tiers)

        GitHub::PrefillAssociations.prefill_associations(results,
          { subscription_item: { plan_subscription: :user } },
          available_records: [sponsor]
        )

        results.to_a
      end

      sig { returns T::Array[Sponsorship] }
      memoize def active_sponsorships
        all_sponsorships.select(&:active?)
      end

      sig { returns T::Array[Sponsorship] }
      memoize def inactive_sponsorships
        all_sponsorships.reject(&:active?)
      end

      sig { returns T::Array[::Billing::SubscriptionItem] }
      def active_subscription_items_without_sponsorships
        ::Billing::SubscriptionItem
          .for_account(sponsor)
          .for_sponsors_tiers
          .active
          .where.not(id: active_sponsorships.map(&:subscription_item_id))
          .preload(:subscribable)
          .to_a
      end

      sig { returns T::Array[T.any(Sponsorship, ::Billing::SubscriptionItem)] }
      memoize def active_sponsorships_and_subscription_items
        active_sponsorships.concat(active_subscription_items_without_sponsorships)
      end

      sig { returns T::Array[Integer] }
      memoize def sponsorship_ids
        active_sponsorships.map(&:id).compact
      end

      sig { params(tab: Symbol).returns(T::Boolean) }
      def active_tab?(tab)
        active_tab == tab
      end

      sig { returns T::Boolean }
      def show_sponsorships?
        return inactive_sponsorships.any? if active_tab?(:past)
        active_sponsorships_and_subscription_items.any?
      end

      sig { returns T.nilable(String) }
      def linked_org_stafftools_billing_path
        return unless linked_org
        billing_stafftools_user_path(linked_org)
      end

      sig { returns T.nilable(::Organization) }
      def linked_org
        return unless linked_org_relationship
        T.must(linked_org_relationship).org
      end

      class LinkedOrgRole < T::Enum
        enums do
          Credited = new
          Funder = new
        end
      end

      sig { returns T.nilable(String) }
      memoize def linked_org_message
        case linked_org_relationship&.role
        when LinkedOrgRole::Credited
          " gets credit for sponsorships funded by #{sponsor}"
        when LinkedOrgRole::Funder
          " funds sponsorships from #{sponsor}"
        end
      end

      class LinkedOrgRelationship < T::Struct
        prop :org, ::Organization
        prop :role, LinkedOrgRole
      end

      # Private: Resolves the sponsor to its linked org if any exists.
      #
      # Returns nil if no link exists, otherwise returns a LinkedOrgRelationship.
      sig { returns T.nilable(LinkedOrgRelationship) }
      memoize def linked_org_relationship
        return unless sponsor.organization?
        org_sponsor = T.cast(sponsor, ::Organization)
        if org_sponsor.sponsoring_parent_organization
          sponsoring_parent_organization = T.cast(org_sponsor.sponsoring_parent_organization, ::Organization)
          LinkedOrgRelationship.new(org: sponsoring_parent_organization, role: LinkedOrgRole::Credited)
        elsif org_sponsor.sponsoring_linked_organization
          sponsoring_linked_organization = T.must(org_sponsor.sponsoring_linked_organization)
          LinkedOrgRelationship.new(org: sponsoring_linked_organization, role: LinkedOrgRole::Funder)
        end
      end
    end
  end
end
