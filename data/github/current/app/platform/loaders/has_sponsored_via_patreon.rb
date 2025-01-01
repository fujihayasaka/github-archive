# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class HasSponsoredViaPatreon < Platform::Loader
      extend T::Sig

      sig { params(user_id: Integer).returns(Promise[T.nilable(T::Boolean)]) }
      def self.load(user_id)
        self.for.load(user_id)
      end

      sig { params(user_ids: T::Array[Integer]).returns(T::Hash[Integer, T.nilable(T::Boolean)]) }
      def fetch(user_ids)
        return Hash.new(false) unless GitHub.sponsors_enabled? && user_ids.present?

        linked_org_ids_by_user_id = linked_org_ids_for(user_ids)
        patreon_sponsorship_sponsor_ids = patreon_sponsorship_sponsor_ids_for(user_ids, linked_org_ids_by_user_id)
        patreon_activity_sponsor_ids = patreon_activity_sponsor_ids_for(user_ids, linked_org_ids_by_user_id)

        user_ids.each_with_object(Hash.new(false)) do |user_id, result|
          linked_org_id = linked_org_ids_by_user_id[user_id]

          # any current sponsorships via Patreon
          has_patreon_sponsorship = patreon_sponsorship_sponsor_ids.include?(user_id) ||
            linked_org_id && patreon_sponsorship_sponsor_ids.include?(linked_org_id)

          # any history of Patreon sponsorships
          has_patreon_activity = patreon_activity_sponsor_ids.include?(user_id) ||
            linked_org_id && patreon_activity_sponsor_ids.include?(linked_org_id)

          result[user_id] = has_patreon_sponsorship || has_patreon_activity
        end
      end

      private

      sig { params(user_ids: T::Array[Integer]).returns(T::Hash[Integer, Integer]) }
      def linked_org_ids_for(user_ids)
        OrganizationProfile.for_organization(user_ids)
          .pluck(:organization_id, :sponsoring_linked_organization_id).to_h
      end

      sig do
        params(
          user_ids: T::Array[Integer],
          linked_org_ids_by_user_id: T::Hash[Integer, Integer]
        ).returns(T::Set[Integer])
      end
      def patreon_sponsorship_sponsor_ids_for(user_ids, linked_org_ids_by_user_id)
        user_id = user_ids.first
        return Set.new unless user_id

        base_query = Sponsorship.patreon
        query_condition_for = -> (user_id, linked_org_id) do
          if linked_org_id
            base_query.from_sponsor(user_id).or(base_query.from_sponsor(linked_org_id))
          else
            base_query.from_sponsor(user_id)
          end
        end

        linked_org_id = linked_org_ids_by_user_id[user_id]
        sponsorships = query_condition_for.call(user_id, linked_org_id)

        user_ids.drop(1).each do |user_id|
          linked_org_id = linked_org_ids_by_user_id[user_id]
          sponsorships = sponsorships.or(query_condition_for.call(user_id, linked_org_id))
        end

        sponsorships.distinct.pluck(:sponsor_id).to_set
      end

      sig do
        params(
          user_ids: T::Array[Integer],
          linked_org_ids_by_user_id: T::Hash[Integer, Integer]
        ).returns(T::Set[Integer])
      end
      def patreon_activity_sponsor_ids_for(user_ids, linked_org_ids_by_user_id)
        user_id = user_ids.first
        return Set.new unless user_id

        base_query = SponsorsActivity.patreon.with_sponsor_action
        query_condition_for = -> (user_id, linked_org_id) do
          if linked_org_id
            base_query.for_sponsor(user_id).or(base_query.for_sponsor(linked_org_id))
          else
            base_query.for_sponsor(user_id)
          end
        end

        linked_org_id = linked_org_ids_by_user_id[user_id]
        activities = query_condition_for.call(user_id, linked_org_id)

        user_ids.drop(1).each do |user_id|
          linked_org_id = linked_org_ids_by_user_id[user_id]
          activities = activities.or(query_condition_for.call(user_id, linked_org_id))
        end

        activities.distinct.pluck(:sponsor_id).to_set
      end
    end
  end
end
